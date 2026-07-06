# 02 CoreBluetooth 核心知识

## 角色:Central 与 Peripheral

- **Central(中心)**:扫描、发起连接、消费数据。手机 App 通常是 Central,对应 `CBCentralManager`。本项目:[CentralManager.swift](../WBBlueSwift/Core/BLE/CentralManager.swift)。
- **Peripheral(外设)**:广播、被连接、提供数据。手环/血糖仪/门锁,对应设备固件;iPhone 也能当外设(`CBPeripheralManager`),本项目"外设模式"页即是:[PeripheralModeView.swift](../WBBlueSwift/Features/Peripheral/PeripheralModeView.swift)。

## GAP:广播与连接的规则层

### 广播包(Advertising)

外设周期性(常见 100ms–1s)在 37/38/39 三个广播信道发包,最大 31 字节(Legacy),由 AD Structure 列表组成:Flags、服务 UUID 列表、LocalName、厂商数据(Manufacturer Data,前 2 字节是 SIG 分配的公司 ID)等。扫描响应(Scan Response)可再补 31 字节。

CoreBluetooth 中广播数据以 `advertisementData` 字典给出:`CBAdvertisementDataServiceUUIDsKey`、`CBAdvertisementDataLocalNameKey`、`CBAdvertisementDataManufacturerDataKey` 等,解析见 `CentralManager.centralManager(_:didDiscover:advertisementData:rssi:)`。

**注意**:`peripheral.name` 与广播里的 LocalName 可能不同(前者可能来自 GAP 服务缓存);iOS 拿不到对方 MAC 地址,`peripheral.identifier` 是**本机生成的会话级 UUID**——换手机就变,设备用随机可解析地址(RPA)时也可能变。企业侧持久绑定设备要靠厂商数据里的序列号或连接后读设备信息服务。

### 连接生命周期(面试口述版)

1. 外设广播 → Central 扫描到(`didDiscover`);
2. Central 发起连接(`connect`),链路层建立连接后 `didConnect`;
3. **服务发现**:`discoverServices` → `discoverCharacteristics`,拿到 GATT 句柄(必做,句柄不能跨连接复用);
4. 可选:协商连接参数(interval/latency/timeout)、更新 ATT_MTU(iOS 自动协商,App 无法主动指定);
5. 数据交互:读/写/订阅;
6. 断开:主动 `cancelPeripheralConnection` 或链路超时(supervision timeout),都走 `didDisconnectPeripheral`。

## GATT:数据组织层

```
Peripheral
└── Service 0x180D(心率服务)
    ├── Characteristic 0x2A37(心率测量) properties: Notify
    │   └── Descriptor 0x2902(CCCD:写 1 开通知、2 开指示)
    └── Characteristic 0x2A38(传感器位置) properties: Read
```

### 特征属性(properties)与操作对应

| 属性 | ATT 操作 | 特点 | 代码落点 |
|---|---|---|---|
| Read | Read Request | 拉取式 | `PeripheralSession.readValue` |
| Write | Write Request | 有确认、可靠、慢(一来一回) | `writeValue(withResponse: true)` |
| WriteWithoutResponse | Write Command | 无确认、吞吐高、需自查发送窗口 | `writeValue(withResponse: false)` + `canSendWriteWithoutResponse` |
| Notify | Handle Value Notification | 推送、无确认 | `notifications(characteristic:)` |
| Indicate | Handle Value Indication | 推送、**有确认**、慢但可靠(血糖仪等医疗设备常用) | 同上,系统自动回 ACK |

订阅 = 写 CCCD 描述符。CoreBluetooth 封装成 `setNotifyValue(true, for:)`,结果回调 `didUpdateNotificationState`——**它可能失败**(典型:特征要求加密链路,报 `insufficientAuthentication`,见 [06-配对绑定与安全](06-配对绑定与安全.md))。

## MTU 与分包

- ATT_MTU 默认 23B,减 3 字节 ATT 头,单帧净负载 20B;
- 连接后 iOS 自动协商更大 MTU(iPhone 通常 185,BLE 5 设备可到 251/512);
- App 取值:`peripheral.maximumWriteValueLength(for:)`(本项目经 `BLECentral.maximumWriteLength` 暴露);
- 业务数据超过单帧就要**分包**,对端**组包**——见 [04-私有二进制协议](04-私有二进制协议.md) 与 `PacketCodec.chunks(of:mtuPayload:)`。

## UUID 体系

- 16 位短 UUID(如 0x180D)是 SIG 公有编号,本质是 128 位基础 UUID `0000xxxx-0000-1000-8000-00805F9B34FB` 的缩写;
- 厂商私有服务用自生成的 128 位 UUID(本项目演示用 FFF0/FFF1/FFF2,正式产品应该用完整 128 位随机 UUID 避免冲突);
- 短名映射表:[BLEConstants.swift](../WBBlueSwift/Core/BLE/BLEConstants.swift)。

## 扫描的工程实践(代码:ScanViewModel)

1. **服务过滤**:`scanForPeripherals(withServices: [0x180D])`,省电、减少无关回调,且是后台扫描的硬性要求(后台不允许无过滤扫描);
2. **超时自停**:持续扫描极耗电,20s 无果就停,引导用户重试;
3. **AllowDuplicates**:默认系统会去重(同一设备只回调一次),开 `CBCentralManagerScanOptionAllowDuplicatesKey` 才能持续刷新 RSSI(更耗电,后台无效);
4. **幽灵设备清理**:设备离开后列表还挂着最后一次广播,按 `lastSeen` 超时移除;
5. **连接前停扫**:射频资源竞争,停扫能显著加快建连。
