# 第 8 课：架构分层与可测试性（1 课时）

> 前 7 课的代码直接调 flutter_blue_plus，能跑但「测不了、离线演示不了、换库要伤筋动骨」。这课把 BLE 能力抽象成接口，做真实 + Mock 双实现，一次性解决这三个问题——这是资深与初级的分水岭。

## 一、为什么要抽象：三个说得出口的理由

面试问「你怎么组织蓝牙代码」，答案不是「用了 MVVM」，而是这三个具体痛点：

1. **可测试**：蓝牙逻辑依赖真机、真设备、真信号，无法进 CI。抽象出接口后，用 Mock 替身就能在纯 Dart 环境跑全流程测试（本课新增 4 条 `mock_central_test`，`flutter test` 秒级跑完，零硬件）。
2. **可离线演示**：面试演示、UI 联调、给产品看效果，总不能每次都掏两台手机配对。Mock 虚拟设备让模拟器直接跑通扫描→连接→订阅→协议往返。
3. **可替换（防腐层）**：第 3 课讲过 FBP 2.x 商用要付费。万一公司法务否了、要换成 `flutter_reactive_ble`，如果业务代码里到处是 `BluetoothDevice`、`ScanResult`，就是全项目大改；如果只有一个适配器文件 import 了 FBP，就只改那一个文件。

核心原则一句话：**业务与 UI 只依赖抽象接口，不依赖具体的三方库类型**。

## 二、接口设计：泄露 FBP 类型 = 假抽象

看 [ble_central.dart](../../lib/core/ble/ble_central.dart)：接口 `BleCentral` 的每个方法，参数和返回值都是**平台中立模型**——`BleScanHit`、`BleService`、`BleChar`、`BleConnState`，以及 `String` 型的 deviceId / charUuid。

关键点：接口里**一个 FBP 类型都不出现**。如果 `discoverServices` 返回 `List<BluetoothService>`（FBP 类型），那抽象就是假的——业务代码拿到的还是 FBP 对象，换库时照样全崩。用 `String` 做 deviceId 还顺手抹平了第 2 课的双端差异（安卓 MAC / iOS UUID），业务层根本不需要知道底下是什么。

这一层在架构里叫**防腐层（Anti-Corruption Layer）**：把三方库的形状挡在门外，不让它「腐蚀」你的业务模型。

## 三、双实现

**真实实现** [real_ble_central.dart](../../lib/core/ble/real_ble_central.dart)：包 FBP，把 `ScanResult → BleScanHit`、`BluetoothService → BleService` 逐一转换。它是**除历史课页面外唯一 import FBP 的文件**——防腐层的边界就这么一个文件宽。

**Mock 实现** [mock_ble_central.dart](../../lib/core/ble/mock_ble_central.dart)：两台虚拟设备，逻辑全自造：

- **Mock 心率带**：订阅 2A37 后每秒推一个 BPM 样本，`72 + 12·sin(t) + 噪声`，编码成标准心率帧 `[flags=0, bpm]`——直接喂给第 5 课的 `parseHeartRate`。
- **Mock 固件设备**：私有服务下一写（FF01）一通知（FF02）。收到命令帧后，固件侧也用 `PacketAssembler` 组包（模拟真实固件跨多次写累积），然后回一帧「响应」（cmd 置高位 `| 0x80`、seq 配对、payload 回显）。
- **故障注入**：开关打开后，连接后 4-10 秒随机掉线（演示第 7 课自动重连）、回帧有 25% 概率损坏 CRC、50% 概率被拆成两次发（演示第 6 课组包的坏帧重同步与半包处理）。**真机很难稳定制造这些故障，Mock 可以按概率复现**——这是测试异常路径的利器。

## 四、依赖注入与「同一份 UI 两种数据源」

看 [mock_demo_page.dart](../../lib/features/demo/mock_demo_page.dart)：子页面 `_MockDevicePage` 的字段类型是 `final BleCentral central`——它**不知道**自己拿到的是 Mock 还是真机。顶层注入 `MockBleCentral`，就跑虚拟设备；注入 `RealBleCentral`，同一套 UI 代码就驱动真硬件。这就是依赖注入：**依赖的是接口，实例从外部塞进来**。

Swift 兄弟项目把这个做到了极致——扫描页一个 ⚙️ 开关切换真实/Mock，整个 App 复用。我们的 Flutter 课为了不推翻前 7 课已验收的页面，把 Mock 演示做成独立入口（扫描页右上角🧪图标）；生产项目的正解是让所有页面都走 `BleCentral`，把 FBP 彻底关进防腐层。

> 教学取舍说明：第 2-7 课的页面仍直接用 FBP（那是当时的教学重点）。本课是「如果重构成可测试架构该怎么做」的示范层，两者并存，正好对比「耦合写法」和「解耦写法」的差别。

## 五、可测试性的兑现

[mock_central_test.dart](../../test/mock_central_test.dart) 4 条测试，全部零硬件：

- 扫描发现两台虚拟设备；
- **全流程离线跑通**：连接 → 服务发现 → 下发命令帧 → 收到并解出固件回帧（cmd 置高位、seq 配对、payload 回显都断言到）；
- 心率设备推出可被 `parseHeartRate` 解析的合理 BPM；
- 连接/断开事件流可观测。

第二条尤其关键：它把「协议往返」这个最核心的业务逻辑，在没有任何蓝牙硬件的情况下端到端验证了。这就是抽象换来的东西——**能测的架构，才是能维护的架构**。

## 六、动手任务

1. 直接在**模拟器**（或任意真机）跑 App → 扫描页右上角点🧪图标进入「离线演示」。
2. 点「Mock 心率带」→ 无需任何外设，看心率曲线自己滚动。
3. 返回点「Mock 固件设备」→ 点「发送命令帧」→ 看到 `↑ 发送` 和 `↓ 回帧`（payload 原样回显）。
4. 打开右上角「故障注入」开关 → 反复发帧，观察偶尔出现「坏帧：crcMismatch（已重同步）」但下一帧恢复正常；连接也会偶尔自己掉。
5. 跑 `flutter test test/mock_central_test.dart`，感受「全流程测试 2 秒跑完、不插任何设备」。

## 验收

1. `flutter test` 全绿（新增 Mock 4 条，共 40 条）。
2. 离线演示页在模拟器上跑通心率曲线 + 协议回帧。
3. 回答：① 抽象 BLE 接口带来哪三个具体好处？② 为什么接口方法的返回值不能是 `BluetoothService` 这类 FBP 类型？这层叫什么？③ 「同一套 UI 既能跑 Mock 又能跑真机」靠的是什么机制？
