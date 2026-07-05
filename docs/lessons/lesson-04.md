# 第 4 课：GATT 读写（1 课时）

> 目标：连接后发现服务，读写自建 Characteristic——App 第一次真正「和设备说话」。

## 一、服务发现：为什么每次连接都要做

`discoverServices()` 做的事：主机沿 ATT 协议遍历外设的属性表，把 Service/Characteristic/Descriptor 的 **UUID → 句柄（handle）映射**拉回本地。之后所有读写操作走的都是句柄，不是 UUID。

为什么不能把上次的句柄存下来直接用？因为**句柄表属于「这一次连接看到的这台设备固件」**：设备固件升级、服务结构变化后句柄会重排。双端系统都做了 GATT 缓存加速（安卓缓存服务表，iOS 也缓存），这带来企业开发经典坑：**设备 OTA 后 App 还在用系统缓存的旧表**，读写莫名失败——安卓要靠反射调 `BluetoothGatt#refresh()` 清缓存（FBP 未直接暴露），iOS 靠外设发 Service Changed 指示。课程记住结论：连接后必发现、发现结果不落盘、OTA 后异常先怀疑缓存。

FBP 细节：`discoverServices()` 默认 `subscribeToServicesChanged: true`——自动订阅 GATT 标准的 Service Changed 特征（0x2A05），服务结构变化时插件会收到通知。

## 二、读：一问一答

`characteristic.read()` = ATT Read Request → Read Response，单包最多 **MTU-1 字节**；更长的值协议层有 Read Blob 续传（FBP 自动处理）。读完后 `characteristic.lastValue` 缓存最近一次值，`lastValueStream` 是值变化流（读、写、通知都会喂它——第 5 课订阅时它是主角）。

拿到的是 `List<int>` 裸字节。**GATT 只定义容器，不定义语义**：`[0x64]` 在电池特征里是 100%，在音量特征里可能是最大音量。标准特征的语义查蓝牙 SIG 的 Assigned Numbers 文档；私有特征的语义由厂商协议文档定义——这就是第 6 课私有协议的入口。

## 三、写：企业协议的核心选型题

| | Write **with** Response | Write **without** Response |
|---|---|---|
| ATT 层 | Write Request，外设必须回 Write Response | Write Command，发完即忘 |
| 可靠性 | ATT 层确认，失败会抛错 | 无确认（但链路层仍保证送达顺序与重传†） |
| 吞吐 | 一个连接间隔一般只能一笔 | 一个连接间隔可塞多笔，吞吐高数倍 |
| 单笔上限 | MTU-3；更长可 `allowLongWrite`（Prepared Write 分段） | MTU-3，超了直接失败 |
| 企业用途 | **指令通道**：配置、控制、关键命令 | **数据通道**：OTA 固件包、音频流、日志批量上传 |

† 面试易错点：without response 不是 UDP。BLE 链路层本身有 CRC 校验 + 重传，Write Command 丢的风险主要在**外设应用层缓冲溢出**（发太快对方处理不过来）——所以 OTA 用它时要自己做流控（每 N 包等设备回一个进度通知），这正是第 6 课协议设计的内容之一。

选型口诀：**低频关键写用 with response，高频吞吐写用 without response + 应用层流控**。`write()` 的一个坑：`withoutResponse: true` 时若特征不支持 WNR 属性会抛错，UI 必须按 `properties` 提供选项（我们的写入对话框就是这么做的）。

## 四、本课代码

```
lib/
├── core/
│   ├── hex.dart                 # 十六进制解析/格式化 + UTF-8 尝试解码（纯函数，带单测）
│   └── gatt_names.dart          # 标准 UUID → 中文名（0x180D 心率服务…）
└── features/device/
    ├── device_controller.dart   # 新增：discoverServices / read / write，断线自动清空服务表
    └── gatt_browser.dart        # 服务浏览器：Service 分组 → 特征卡片（属性徽标/值/读写按钮）
```

- 连接成功后**自动**服务发现（企业 App 的标准流程，用户不该关心这一步）；断线时清空 `services`——句柄表跟着连接走，这是第一节理论的代码表达。
- 特征卡片：属性徽标（读/写/免响写/通知/指示）、值的 hex + UTF-8 双显示、读按钮、写按钮（弹框输 hex，可选写类型）。
- hex 工具是纯函数并配了单测——所有字节处理逻辑不碰蓝牙就能测（第 8 课主题的又一次预演）。

## 五、动手任务：自建特征

**正向（安卓当外设，iPhone 跑 App）**：
1. 安卓 nRF Connect → 右上角菜单 → **Configure GATT server** → 添加 Service（自定义 128-bit UUID，或用模板）→ 在该 Service 下添加 Characteristic：属性勾 **Read + Write**，初始值随便填几个字节（如 `01 02 03`）。
2. nRF Connect → ADVERTISER → 新建广播（勾 Connectable），开启。
3. Mac 上 `flutter run` 到 iPhone → 扫描连接 → 服务浏览器找到你的自定义特征 → **读**出 `01 02 03` → **写**入 `48 69`（"Hi"）→ 回 nRF Connect 服务器页看到值已变。

**反向（iPhone 当外设，安卓跑 App）**：
4. LightBlue → Virtual Devices → 新建（选 Blank 或任意模板，确认有可读写特征）→ 安卓打开 wb_ble_app 连接读写一遍。

## 验收

1. 实操 3 的读、写、对端确认三步截图或口述现象。
2. 回答：① 为什么句柄不能跨连接复用？系统 GATT 缓存会带来什么企业级坑？② OTA 固件传输该用哪种写？丢包风险真正来自哪里、怎么防？③ `read()` 回来的 `[0x64]` 是什么意思？——这个问题的正确答案是什么？
