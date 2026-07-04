# 第 3 课：连接管理（1 课时）

> 目标：从「看得见」到「连得上」。理解连接状态机、超时与断线感知，搭出设备详情页骨架。

## 一、先上一堂企业选型课：License 参数

写 `device.connect()` 时编译器会拦住你：`license` 是必填参数。这不是技术设计，是**商业模式**——flutter_blue_plus 从 2.0 起由 BSD 改为源码可见的双轨授权：

- `License.nonprofit`：个人 / 教育 / 非营利免费（本教学项目用这个）
- `License.commercial`：**商用需购买付费授权**

企业启示：① 选型时 License 审查和技术评估同权重，公司法务会挡掉「先用了再说」；② 因此不少商业项目停在 1.x（BSD 协议的最后版本）或转投 `flutter_reactive_ble`（Apache-2.0）；③ 我们课程继续用 2.x——API 更好，且你学到的概念在任何 BLE 库间平移。面试被问「Flutter 蓝牙库怎么选」，这段就是满分答案的骨架。

## 二、连接 API 的三个反直觉点

### 1. `connectionState` 流只会发 `connected` / `disconnected`

枚举里的 connecting/disconnecting 在 FBP 2.x 已废弃不再发射。「连接中」的转圈状态**必须自己管**（我们用 `busy` 标志包住 connect/disconnect 动作）。这背后是个正确的架构观：**UI 状态（用户视角的忙闲）≠ 链路状态（协议栈视角的通断）**，混在一起是无数蓝牙 App 状态错乱的根源。

### 2. 断线感知靠流，不靠返回值

`connect()` 返回只代表「这次建连动作结束了」。之后外设关机、走出范围、被系统踢掉——没有任何 Future 会告诉你，**唯一的耳朵是 `connectionState` 流**。所以 Controller 在构造时就订阅它，而不是在 connect 之后。断线后 `device.disconnectReason` 能拿到平台错误码：安卓是 GATT status（8 = 连接超时被动断线，19 = 外设主动断开，22 = 本地终止），iOS 是 NSError code。企业 App 用它区分「用户自己关的设备」和「信号问题掉线」，决定要不要自动重连（第 7 课）。

### 3. 连接前要停止扫描

安卓上扫描与建连共享射频资源，边扫边连会显著提高臭名昭著的 **status 133（GATT_ERROR）** 概率——这是安卓 BLE 最著名的「万金油错误」，官方文档不承认，Stack Overflow 上千贴。本课先记住第一条军规：**connect 之前 stopScan**（我们做在扫描页点击回调里）。133 的完整治理（指数退避重试、清 GATT 缓存）放第 7 课。

另外两个默认行为要知道：`connect()` 默认 `timeout: 35s`（企业一般压到 8–15s，用户等不了 35 秒）；FBP 在安卓上连接成功后会自动请求 MTU 512（`mtu: 512` 默认参数），iOS 忽略此参数由系统协商——第 6 课分包时会回来看它。

## 三、本课代码

```
lib/features/
├── scan/…                      # 第 2 课，本课改动：removeIfGone + 点击跳转（连接前 stopScan）
└── device/
    ├── device_controller.dart  # 连接状态机：busy 标志 + connectionState 订阅 + disconnectReason
    └── device_page.dart        # 详情页骨架：状态卡片 / 连接按钮 / RSSI / GATT 占位（第 4 课）
```

- 兑现第 2 课伏笔：`startScan` 加了 `removeIfGone: 4s`——关掉 LightBlue 虚拟外设，4 秒后条目自动从列表消失，幽灵设备没了。
- `readRssi()`：连接态下主动测信号，注意它是**连接后的链路 RSSI**，与扫描时广播 RSSI 是两条通道。
- DevicePage 持有自己的 DeviceController，页面销毁时 dispose 里主动 `disconnect()`——本课策略「离开页面即断开」，第 7 课引入后台保活后会推翻它（有意为之的教学演进）。

## 四、动手任务

1. iPhone：LightBlue 开心率虚拟外设。
2. 安卓 App：扫描 → 点击该设备 → 详情页点「连接」→ 观察状态翻转为已连接（此时 LightBlue 里能看到 central 连入）。
3. 点「读取 RSSI」几次，拿远拿近对比数值。
4. **被动断线实验**：保持连接，直接在 LightBlue 里关掉虚拟外设 → 观察 App 状态自动翻回未连接、显示断线原因码——这就是「靠流不靠返回值」。
5. **超时实验**：回列表（自动断开），关掉虚拟外设，再点连接 → 等 10 秒观察超时报错。
6. 回到扫描页验证 removeIfGone：扫着扫着关掉外设，看条目 4 秒后消失。

## 验收

1. 实操 2/4/5/6 全部符合预期（截图或口头描述现象即可）。
2. 回答：① 为什么「连接中」状态要 App 自己维护？② `connect()` 成功返回后，还有哪些方式会让连接死掉？代码里靠什么发现？③ 安卓 status 133 是什么？本课学的第一条规避军规是哪条？
