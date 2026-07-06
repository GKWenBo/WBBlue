# WBBlueSwift 技术文档

原生 iOS 企业级 BLE 示例项目(Swift + async/await + SwiftUI),覆盖企业蓝牙开发的核心知识点与异常处理方案。

## 运行

- 环境:Xcode 26+,iOS 26 部署目标。
- **模拟器**:直接运行。模拟器无蓝牙硬件,App 自动使用 Mock 数据源(两台虚拟设备),可离线走通 扫描 → 连接 → 服务浏览 → 读写 → 订阅心率 → 私有协议收发 全流程;扫描页右上角 ⚙️ 可开故障注入(连接超时/强制断连)演示异常处理。
- **真机**:扫描页 ⚙️ 关闭"使用 Mock 数据源"即走真实 CoreBluetooth。两台 iPhone 互测:A 机开"外设模式"页,B 机扫描连接;或用 nRF Connect / LightBlue 模拟外设。
- 单元测试:`⌘U`,或命令行:

```bash
xcodebuild -project WBBlueSwift.xcodeproj -scheme WBBlueSwift \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:WBBlueSwiftTests
```

## 文档目录

| 篇 | 内容 |
|---|---|
| [01-架构与并发模型](01-架构与并发模型.md) | 分层设计、BLECentral 协议抽象、continuation/AsyncStream 封装模式、MainActor 并发选型 |
| [02-CoreBluetooth 核心知识](02-CoreBluetooth核心知识.md) | GAP/GATT、广播包结构、连接生命周期、MTU、UUID 体系、特征属性 |
| [03-异常处理手册](03-异常处理手册.md) | 十类异常场景:现象 / 原因 / 方案 / 代码落点(本项目最核心一篇) |
| [04-私有二进制协议](04-私有二进制协议.md) | 帧结构、CRC16、半包粘包组包、MTU 分包、与 OTA 的关系 |
| [05-后台模式与状态恢复](05-后台模式与状态恢复.md) | bluetooth-central 后台模式、State Restoration、后台广播降级 |
| [06-配对绑定与安全](06-配对绑定与安全.md) | Just Works/Passkey、insufficientAuthentication、iOS 没有绑定 API 的现实 |
| [07-面试高频 FAQ](07-面试高频FAQ.md) | OTA、iBeacon、Mesh、Android/iOS 双端差异、高频问答 |
| [08-真机验收清单](08-真机验收清单.md) | 双 iPhone 手工验收步骤 |

## 代码地图

```
WBBlueSwift/
├── AppModel.swift                    依赖容器:Mock/真实 central 切换
├── ContentView.swift                 根 TabView
├── Core/
│   ├── BLE/
│   │   ├── BLECentral.swift          ★ 抽象接口(真实/Mock 双实现契约)
│   │   ├── BLECentralModels.swift    与 CoreBluetooth 解耦的数据模型
│   │   ├── CentralManager.swift      ★ CBCentralManager 封装(超时/状态/扫描)
│   │   ├── PeripheralSession.swift   ★ 单设备 GATT 会话(continuation 封装)
│   │   ├── ReconnectOrchestrator.swift ★ 自动重连状态机(指数退避)
│   │   ├── MockCentral.swift         虚拟设备 + 故障注入
│   │   ├── BLEError.swift            统一错误 + 恢复建议
│   │   └── BLEConstants.swift        UUID 短名表
│   ├── Protocol/PacketCodec.swift    ★ 私有协议:CRC16/组包/分包(11 项单测)
│   ├── Parsers/HeartRateParser.swift 0x2A37 标准解析(7 项单测)
│   ├── Utils/                        Hex、Backoff(9 项单测)
│   └── Logging/BLELogger.swift       os.Logger + 环形缓冲双通道
└── Features/                         扫描/详情/心率/协议控制台/外设模式/日志
```

★ = 企业开发的重点阅读文件。
