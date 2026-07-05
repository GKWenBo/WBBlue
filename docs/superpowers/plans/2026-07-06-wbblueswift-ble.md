# WBBlueSwift 企业级 BLE 项目实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 注:本次为 autonomous /goal 模式,由同一会话 inline 执行(executing-plans),计划持有者与执行者为同一上下文,故各任务给出接口签名、测试用例与验收命令,不重复粘贴全部实现源码。

**Goal:** 在壳工程上构建覆盖企业 BLE 全知识点的原生 iOS 项目(async/await + SwiftUI),含异常处理方案、单元测试与 8 篇技术文档,编译与测试全部通过。

**Architecture:** Core 层为协议抽象的 BLE SDK 雏形(CoreBluetooth 封装 + Mock 双实现),Feature 层为 SwiftUI 页签逐一演示知识点;纯逻辑(编解码/解析/退避)全部纯函数化并用 Swift Testing 覆盖。

**Tech Stack:** Swift 5.9+/Xcode 26.5、CoreBluetooth、SwiftUI + @Observable、Swift Charts、Swift Testing、os.Logger。

## Global Constraints

- 部署目标 iOS 26.5,仅 iPhone 模拟器验证编译;工程为文件系统同步组(加文件即编译,勿改 pbxproj 文件列表)。
- Info.plist 由构建设置生成:蓝牙权限用 `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` 注入。
- 所有 UI 类型 `@MainActor`;CoreBluetooth 委托回调派发主队列。
- 每个任务结束:`xcodebuild build`(或 `test`)通过后 git commit。
- 验收命令:
  - 构建:`xcodebuild -project WBBlueSwift/WBBlueSwift.xcodeproj -scheme WBBlueSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  - 测试:同上 `test -only-testing:WBBlueSwiftTests`

---

### Task 1: 工程配置基线

**Files:** Modify `WBBlueSwift.xcodeproj/project.pbxproj`(仅构建设置)

- [ ] 两个 configuration 加 `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "App 使用蓝牙扫描并连接周边 BLE 设备(演示企业蓝牙开发全流程)。";`
- [ ] 基线构建通过 → commit

### Task 2: Hex 与 Backoff 纯函数(TDD)

**Files:** Create `WBBlueSwift/Core/Utils/Hex.swift`, `WBBlueSwift/Core/Utils/Backoff.swift`; Test `WBBlueSwiftTests/HexTests.swift`, `BackoffTests.swift`

**Produces:** `Data.init?(hexString:)`, `Data.hexString(separator:)`; `Backoff.delay(attempt:base:cap:jitter:) -> TimeInterval`(attempt 从 1 起,指数 `base*2^(attempt-1)` 封顶 cap,jitter 为 0…ratio 的随机乘数,注入 RandomNumberGenerator 以便测试)。

- [ ] 失败测试 → 实现 → 测试通过 → commit

### Task 3: HeartRateParser(TDD)

**Files:** Create `WBBlueSwift/Core/Parsers/HeartRateParser.swift`; Test `WBBlueSwiftTests/HeartRateParserTests.swift`

**Produces:** `struct HeartRateMeasurement { bpm: Int; sensorContact: SensorContact; energyExpended: Int?; rrIntervals: [Double] }`,`HeartRateParser.parse(_ data: Data) -> HeartRateMeasurement?`。用例:uint8/uint16、含能耗、含 RR(1/1024 秒换算)、空数据返回 nil。

- [ ] 失败测试 → 实现 → 测试通过 → commit

### Task 4: PacketCodec 私有协议(TDD,企业核心)

**Files:** Create `WBBlueSwift/Core/Protocol/PacketCodec.swift`; Test `WBBlueSwiftTests/PacketCodecTests.swift`

**Produces:**
- 帧结构:`0xA5 0x5A | cmd(1) | seq(1) | len(2,LE) | payload(len) | crc16(2,LE, CCITT-FALSE, 覆盖 cmd..payload)`
- `struct Packet { cmd: UInt8; seq: UInt8; payload: Data }`
- `PacketCodec.encode(_ packet: Packet) -> Data`
- `PacketCodec.crc16(_ data: Data) -> UInt16`
- `struct PacketAssembler`(流式组包状态机):`mutating func feed(_ chunk: Data) -> [PacketAssembler.Event]`,Event = `.packet(Packet)` / `.error(PacketError)`;跨 chunk 半包、粘包、CRC 错帧丢弃复位、坏头逐字节重同步。
- `PacketCodec.chunks(of data: Data, mtuPayload: Int) -> [Data]` 分包。

- [ ] 失败测试(≥8 用例)→ 实现 → 测试通过 → commit

### Task 5: BLE 基础类型 + 日志

**Files:** Create `Core/BLE/BLEError.swift`, `Core/BLE/BLEConstants.swift`, `Core/Logging/BLELogger.swift`

**Produces:** `enum BLEError: LocalizedError`(poweredOff/unauthorized/unsupported/timeout(operation)/disconnected/notConnected/characteristicNotFound/gatt(CBATTError.Code)/…含 recoverySuggestion);`BLEConstants.name(for: CBUUID) -> String?` 短名表;`BLELogger.shared`:`log(_ level:_ message:)` 写 os.Logger + @Observable 环形缓冲(500 条)供 UI。

- [ ] 构建通过 → commit

### Task 6: 抽象接口与模型(双实现契约)

**Files:** Create `Core/BLE/BLECentralModels.swift`, `Core/BLE/BLECentral.swift`

**Produces:**
- `struct DiscoveredDevice: Identifiable`(id: UUID、name、rssi、advertisedServices、manufacturerData、lastSeen、isConnectable)
- `enum CentralState`(unknown/poweredOff/unauthorized/unsupported/poweredOn/resetting)
- `enum ConnectionEvent { connected, disconnected(error: Error?), reconnecting(attempt: Int) }`
- `struct GATTCharacteristic`(uuid、properties、isNotifying、value)/`struct GATTService`(uuid、characteristics)
- `protocol BLECentral: AnyObject`(@MainActor):`state`、`stateStream()`、`scan(services:) -> AsyncStream<DiscoveredDevice>`、`stopScan()`、`connect(id:timeout:) async throws`、`disconnect(id:)`、`connectionEvents(id:) -> AsyncStream<ConnectionEvent>`、`discoverServices(id:) async throws -> [GATTService]`、`readValue/writeValue(withResponse:)/setNotify -> AsyncThrowingStream<Data, Error>`、`readRSSI`。

- [ ] 构建通过 → commit

### Task 7: CentralManager + PeripheralSession(真实实现)

**Files:** Create `Core/BLE/CentralManager.swift`, `Core/BLE/PeripheralSession.swift`

**Consumes:** Task 6 协议。**Produces:** `final class CentralManager: NSObject, BLECentral`,委托回调主队列;connect 超时竞速(Task + Task.sleep,超时 cancelPeripheralConnection 并抛 `.timeout`);PeripheralSession 持有 CBPeripheral 并实现 CBPeripheralDelegate,读/写/发现用 continuation 表(按 CBUUID 键控),notify 用 AsyncThrowingStream,断连时 finish 所有挂起 continuation(防泄漏,关键异常点)。

- [ ] 构建通过 → commit

### Task 8: ReconnectOrchestrator(自动重连状态机)

**Files:** Create `Core/BLE/ReconnectOrchestrator.swift`

**Consumes:** BLECentral + Backoff。**Produces:** `@MainActor @Observable final class ReconnectOrchestrator`:`enum Phase { idle, connecting, connected, waitingRetry(attempt: Int, delay: TimeInterval), failed(Error) }`;`start(deviceID:)` 监听 connectionEvents,意外断连→按 Backoff 重试(默认 base 1s、cap 30s、最多 6 次),`stopAndDisconnect()` 用户主动断开置 idle 不重连。

- [ ] 构建通过 → commit

### Task 9: MockCentral(模拟器离线全流程)

**Files:** Create `Core/BLE/MockCentral.swift`

**Produces:** `final class MockCentral: BLECentral`:虚拟设备"WB 心率带 (Mock)"(0x180D/0x2A37 心率正弦波動通知、0x2A38 可读、自定义服务 FFF0/FFF1 写入回显私有协议帧)+"WB 温湿度计 (Mock)";可注入故障开关(连接超时、随机断连)演示重连。App 侧:模拟器编译默认用 Mock,真机默认用 CentralManager,可在设置切换。

- [ ] 构建通过 → commit

### Task 10: Feature — 扫描页 + 设备详情页

**Files:** Create `Features/Scan/ScanViewModel.swift`, `Features/Scan/ScanView.swift`, `Features/Device/DeviceDetailViewModel.swift`, `Features/Device/DeviceDetailView.swift`, `Features/Device/CharacteristicRow.swift`;Modify `ContentView.swift`, `WBBlueSwiftApp.swift`

蓝牙状态横幅(引导跳设置)、扫描开关/服务过滤/超时自停/幽灵设备清理;详情页:重连状态条(Orchestrator)、服务浏览器、属性徽标、hex 读写 sheet、订阅开关、RSSI。

- [ ] 构建通过 → commit

### Task 11: Feature — 心率图表 + 私有协议控制台 + 外设模式 + 日志页

**Files:** Create `Features/HeartRate/HeartRateView.swift`(+VM,Swift Charts 滑窗曲线)、`Features/Console/ProtocolConsoleView.swift`(+VM,FFF1 发私有帧收回显,分包演示)、`Features/Peripheral/PeripheralModeViewModel.swift`+`PeripheralModeView.swift`(CBPeripheralManager 广播 0x180D,双机互测)、`Features/Logs/LogsView.swift`

- [ ] 构建通过 → commit

### Task 12: 技术文档 8 篇

**Files:** Create `WBBlueSwift/docs/README.md` 及 `01…07` 共 8 篇(见设计文档 §6,含异常处理手册逐条对应代码位置、真机手工验收清单)。

- [ ] 文档完成、互链、无 TBD → commit

### Task 13: 终验

- [ ] `xcodebuild build` + `xcodebuild test` 全绿;更新根 README 指向双工程 → commit
