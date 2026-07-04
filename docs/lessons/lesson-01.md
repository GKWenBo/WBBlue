# 第 1 课：BLE 理论地基（1 课时）

> 本课不写代码。目标是把第 2 课起所有 API 背后的概念一次讲透——企业面试里蓝牙岗一半的问题出自本课。

## 一、BLE 不是「蓝牙的低配版」

蓝牙 4.0 起协议栈里其实有两套互不兼容的东西：

| | 经典蓝牙（BR/EDR） | 低功耗蓝牙（BLE / LE） |
|---|---|---|
| 典型用途 | 音频（耳机/音箱）、大数据流 | 传感器、手环、门锁、工业设备 |
| 功耗 | 高，持续连接 | 极低，纽扣电池可跑数年 |
| 手机 App 可编程性 | iOS 基本封死（仅 MFi/特定 profile） | **双端开放 API，App 开发的主战场** |

企业里说「做蓝牙开发」，99% 指 BLE。iPhone 连蓝牙耳机走经典蓝牙，跟我们写的代码无关。

## 二、GAP：谁广播、谁扫描、谁连谁

GAP（Generic Access Profile）定义设备的**角色与连接建立方式**：

- **Peripheral（外设）**：对外广播「我在这里」，等待被连接。如手环、血压计。资源受限的一方。
- **Central（主机/中心）**：扫描广播，发起连接。如手机 App。可同时连多个外设。
- 另有 Broadcaster（只广播不可连，如 Beacon）/ Observer（只扫描不连接）两个轻角色。

**连接前世界只有广播与扫描；连接后广播停止，进入一对一通信。**（BLE 5.0 后外设可边连边广播，但心智模型先按停止记。）

## 三、广播包：31 字节的自我介绍

外设在 3 个广播信道（37/38/39，避开 Wi-Fi 主频段）上周期性发广播包。经典（Legacy）广播载荷上限 **31 字节**，格式是一串 **AD Structure**：`[长度 1B][类型 1B][数据 N B]` 连续排列。常见 AD Type：

| Type | 含义 | 备注 |
|---|---|---|
| `0x01` Flags | 可发现模式等标志位 | 几乎必带 |
| `0x09`/`0x08` | 完整/缩短设备名 | 名字放不下就进 Scan Response |
| `0x03`/`0x07` | 16-bit / 128-bit Service UUID 列表 | 企业 App 常按它过滤目标设备 |
| `0xFF` | **Manufacturer Specific Data** | 前 2 字节是厂商 ID，后面随便放——企业私有协议最爱：不连接就能广播电量、状态、MAC |

扫描方还可以主动要一份 **Scan Response**（再加 31 字节），放不下的名字/数据放这里。

**面试点**：为什么有些设备在 iOS 上扫到的名字和安卓不一样？——iOS 会用 GATT 里的 Device Name 缓存覆盖广播名，且 iOS 拿不到外设 MAC 地址（只给一个本机生成的 UUID，同一外设在不同 iPhone 上 UUID 不同）。安卓拿得到真 MAC。这直接影响企业 App「按 MAC 绑定设备」的方案设计——iOS 端只能改用广播里的厂商数据（如把序列号放进 0xFF 字段）来识别设备。

## 四、连接生命周期（本课验收题）

一次完整连接，口述版：

1. **外设广播**：按广播间隔（如 100ms–1s，间隔越短越费电越容易被发现）在 37/38/39 信道发包。
2. **主机扫描**：按扫描窗口/间隔监听信道，收到广播 → 上报（App 拿到设备名、RSSI、广播数据）。
3. **发起连接**：主机在收到广播的瞬间回一个 CONNECT_IND。外设停止广播，双方按**连接参数**跳频通信。
4. **连接参数**（面试高频）：
   - **Connection Interval**（连接间隔，7.5ms–4s）：双方多久碰头交换一次数据。小 = 快但费电；iOS 会拒绝过小的请求。
   - **Peripheral Latency**（从机延迟）：外设可跳过 N 次碰头以省电。
   - **Supervision Timeout**（监督超时）：这么久没通上信就算断线——这就是「设备关机后 App 过几秒才知道断了」的原因。
5. **MTU 协商**：默认 ATT MTU = 23 字节（有效载荷 20B）。连接后任一方可请求更大 MTU（安卓最高 517，iOS 系统自动协商、通常 185+，App 不能主动指定）。**第 6 课分包组包的根源就在这里。**
6. **服务发现**：主机遍历外设的 GATT 表（下一节），拿到所有 Service/Characteristic 句柄。
7. **数据交互**：读 / 写 / 订阅通知。
8. **断开**：任一方主动断开，或超时被动断线。外设通常恢复广播。

## 五、GATT：连接后的数据世界

GATT（Generic Attribute Profile）把外设的数据组织成一棵三层树：

```
Peripheral（GATT Server，数据在外设侧）
└── Service 服务（功能模块，如「心率服务 0x180D」）
    └── Characteristic 特征（具体数据项，如「心率测量 0x2A37」）
        ├── Value（真正的数据字节）
        ├── Properties（允许的操作：Read / Write / WriteNoResponse / Notify / Indicate）
        └── Descriptor 描述符（元数据，最重要的是 CCCD 0x2902——订阅开关）
```

- 手机是 GATT **Client**，外设是 GATT **Server**（谁存数据谁是 Server，和连接发起方无关）。
- **UUID**：标准服务用 16-bit 短 UUID（如 0x180D），本质是嵌在蓝牙基础 UUID `0000xxxx-0000-1000-8000-00805F9B34FB` 里的占位；企业私有服务必须自造 128-bit UUID。
- 企业设备的典型形态：一个私有 Service 下两条 Characteristic——一条 **Write**（App→设备，下发指令）+ 一条 **Notify**(设备→App，上报数据)，合起来当「蓝牙串口」用。第 4~6 课就围绕这个形态展开。

## 六、回收第 0 课思考题

1. **Android 12 前扫描为何要定位权限？** BLE 广播（尤其商场里铺满的 iBeacon）可以三角定位你的位置，Google 索性把「能扫蓝牙」视同「能定位」。iOS 不这么划权限，是因为 CoreBluetooth 从 API 层就不给 App 拿 MAC/原始 iBeacon 数据（定位能力被单独关进 CoreLocation）。
2. **`neverForLocation` 的代价？** 系统会把 iBeacon 等定位类广播从扫描结果里过滤掉。做设备连接类 App 该加（省一个吓人的定位弹窗）；做室内定位/导购/资产追踪的产品不能加。

## 七、实操任务（两台手机，不写代码）

1. **iPhone 打开 LightBlue → 底部 Virtual Devices → 新建一个 "Heart Rate" 虚拟外设**（保持 LightBlue 在前台）。
2. **安卓打开 nRF Connect → SCANNER 扫描**，找到它（名字通常是 HeartRate 或 iPhone 的名字）：
   - 点开条目（先别 CONNECT）：看 RSSI、Advertising interval，展开看原始 AD Structure —— 对照第三节认一认 Flags / Service UUID / 名字各是哪几个字节。
   - 把 iPhone 拿远/装进口袋，观察 RSSI 变化。
3. **点 CONNECT**：连接后看 GATT 树——找到 Heart Rate Service (0x180D) 和其中的 Heart Rate Measurement (0x2A37)，看它的 Properties 是不是 Notify。点旁边的三箭头图标订阅，观察 LightBlue 推来的模拟心率值。
4. 断开，观察 iPhone 侧外设恢复可被扫描。

> 顺带你就完成了一次「主机视角」的完整生命周期：扫描 → 解析广播 → 连接 → 服务发现 → 订阅 → 断开。第 2~5 课我们用 Flutter 代码把这条链路一步步重写出来。

## 验收（回复我即可）

1. 不看讲义，口述一次 BLE 连接从广播到断开的完整生命周期（提到连接间隔与监督超时的作用）。
2. 你在 nRF Connect 里实际看到的：Heart Rate 虚拟外设广播里带了哪个 Service UUID？0x2A37 的 Properties 是什么？
3. 思考题：为什么企业设备几乎都用「一条 Write + 一条 Notify」的特征对，而不是让 App 轮询 Read？
