# WBBlueSwift —— iOS 企业级 BLE 示例项目设计文档

日期:2026-07-06
状态:已确认(autonomous 模式下由 Claude 依据 /goal 目标自主确定,供用户事后审阅)

## 1. 目标

在已建好的壳工程 `WBBlueSwift/`(Xcode 26.5,iOS 26.5,SwiftUI App 模板,文件系统同步组)之上,构建一个**尽可能覆盖企业蓝牙开发全部知识点**的原生 iOS 项目:

1. 覆盖企业 BLE 开发核心知识:扫描、连接、GATT 读写、订阅通知、私有二进制协议、分包组包、自动重连、后台与状态恢复、Peripheral 角色、配对绑定、MTU 等。
2. 内置**异常场景解决方案**:蓝牙关闭/未授权、连接超时、意外断连自动重连(指数退避+抖动)、写失败重试、订阅失败、状态恢复。
3. 技术栈:Swift 5.9+、async/await(continuation + AsyncStream)、SwiftUI、@Observable、Swift Charts、Swift Testing。
4. 完整技术文档(`WBBlueSwift/docs/`,中文),方便后续查阅与面试复习。
5. `xcodebuild build` 与 `xcodebuild test` 全部通过。

对齐仓库内 Flutter 课程大纲(`app/docs/PROGRESS.md` 第 0–11 课)的全部主题。

## 2. 方案取舍

考虑过三种组织方式:

- **A. 按课时组织的教学 Demo 集合**(每课一个独立页面):知识点直观,但代码重复、无企业架构示范价值。
- **B. 单一"设备管家"App,分层架构 + 功能页签**(推荐):Core 层是可复用的企业级 BLE SDK 雏形,Feature 层演示每个知识点;架构本身就是教学内容。
- **C. 纯 SDK(Swift Package)+ 薄壳 App**:最工程化,但壳工程已是 App 模板,拆包增加复杂度且不利于单文件查阅。

**选 B**:Core 层按 SDK 标准写(协议抽象、可 Mock、可单测),Feature 层用 SwiftUI 页签逐一演示。

## 3. 架构

```
WBBlueSwift/
├── WBBlueSwiftApp.swift        # 入口,注入 BLECentralService(真机)/MockCentral(模拟器可切)
├── ContentView.swift            # TabView:扫描 / 心率 / 外设模式 / 日志 / 关于文档
├── Core/
│   ├── BLE/
│   │   ├── BLEError.swift              # 统一错误枚举,LocalizedError + 恢复建议
│   │   ├── BLEConstants.swift          # 标准服务/特征 UUID 与短名映射
│   │   ├── BLECentral.swift            # 抽象协议(真实/Mock 双实现的接口)
│   │   ├── CentralManager.swift        # CBCentralManager 封装:状态流、扫描流、连接(带超时)
│   │   ├── PeripheralSession.swift     # 单设备会话:服务发现/读/写/订阅,continuation+AsyncStream
│   │   ├── ReconnectOrchestrator.swift # 自动重连状态机(指数退避+抖动,可取消)
│   │   ├── MockCentral.swift           # 模拟器可跑的虚拟心率设备(全流程离线演示)
│   │   └── (状态恢复:restore identifier + willRestoreState,文档详述)
│   ├── Protocol/
│   │   └── PacketCodec.swift           # 私有协议:帧头/命令/长度/负载/CRC16 + 分包组包器
│   ├── Parsers/
│   │   └── HeartRateParser.swift       # 0x2A37 标准心率解析(flags/uint8|16/能耗/RR)
│   ├── Utils/
│   │   ├── Hex.swift                   # hex 编解码
│   │   └── Backoff.swift               # 指数退避纯函数(可单测)
│   └── Logging/
│       └── BLELogger.swift             # os.Logger + 内存环形缓冲(供日志页 UI)
├── Features/
│   ├── Scan/        # 扫描页:状态提示、服务过滤、RSSI、广播数据解析、连接入口
│   ├── Device/      # 设备详情:服务浏览器、特征属性徽标、读/写对话、订阅开关、RSSI 刷新
│   ├── HeartRate/   # 心率页:订阅 0x2A37,Swift Charts 实时曲线
│   ├── Peripheral/  # 外设模式:CBPeripheralManager 广播心率服务(两台 iPhone 互测)
│   └── Logs/        # 日志查看页
└── docs/            # 技术文档(见 §6)
```

关键决策:

- **并发模型**:UI 层类型标注 `@MainActor` + `@Observable`;CBCentralManager 委托回调派发到主队列(教学项目吞吐量低,简单正确优先;docs 中说明高吞吐场景应使用专用串行队列的改法)。异步 API 用 `CheckedContinuation` 包装一次性回调,`AsyncStream` 包装多值回调(扫描结果、通知数据、连接事件),超时用结构化并发竞速实现。
- **可测试性**:纯逻辑(编解码、解析、退避、hex)全部为纯函数/纯结构体,Swift Testing 单测覆盖;CoreBluetooth 依赖通过 `BLECentral` 协议抽象,`MockCentral` 让模拟器无硬件也能完整走通扫描→连接→订阅→私有协议流程。
- **Info.plist**:壳工程用 `GENERATE_INFOPLIST_FILE`,通过 `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` 构建设置注入蓝牙用途声明;后台模式(`bluetooth-central`/`bluetooth-peripheral`)与状态恢复的完整配置在文档中给出(真机长期后台需要,示例工程默认不开启以保持模板简单——若构建设置支持则直接开启)。

## 4. 异常处理矩阵(核心交付之一)

| 场景 | 方案 | 落点 |
|---|---|---|
| 蓝牙关闭/未授权/不支持 | 状态流驱动 UI 引导(跳设置);API 调用前置检查抛 `BLEError` | CentralManager + ScanView |
| 扫描无结果/幽灵设备 | 服务过滤、超时停止、按最近可见时间清理 | ScanViewModel |
| 连接超时 | `connect` 带超时竞速,超时主动 `cancelPeripheralConnection` | CentralManager |
| 意外断连 | 断连事件流 → ReconnectOrchestrator 指数退避+抖动自动重连,用户手动断开则不重连 | ReconnectOrchestrator |
| 服务/特征发现失败 | 错误向上抛,UI 呈现;短暂重试策略见文档 | PeripheralSession |
| 写失败/无响应写背压 | withResponse 失败重试;withoutResponse 检查 `canSendWriteWithoutResponse` | PeripheralSession |
| 订阅失败(CCCD 无权限/需配对) | 错误映射 `CBATTError.insufficientAuthentication` → 提示配对 | PeripheralSession + docs |
| 分包乱序/CRC 错误 | 组包器状态机丢弃坏帧并复位,单测覆盖 | PacketCodec |
| App 被杀后台恢复 | state restoration(restore identifier + willRestoreState)完整讲解与代码路径 | docs + CentralManager 注释 |

## 5. 测试策略

- 单元测试(Swift Testing,模拟器可跑):PacketCodec(编码/解码/CRC/分包/组包/坏帧)、HeartRateParser(8/16 位、RR、能耗)、Hex、Backoff(上限、抖动范围)。
- 编译验收:`xcodebuild build` + `xcodebuild test`(iPhone 17 Pro 模拟器)零错误。
- 真机流程(文档给出手工验收清单):两台 iPhone 一台跑 App、一台跑外设模式(或 LightBlue)。

## 6. 技术文档(WBBlueSwift/docs/)

1. `README.md` — 文档索引 + 工程运行方式
2. `01-架构与并发模型.md` — 分层、协议抽象、continuation/AsyncStream 封装模式
3. `02-CoreBluetooth 核心知识.md` — GAP/GATT、广播包、连接参数、MTU、UUID、属性
4. `03-异常处理手册.md` — 上表逐条展开:现象/原因/方案/代码位置
5. `04-私有二进制协议.md` — 帧结构、CRC16、分包组包、与 OTA 的关系
6. `05-后台模式与状态恢复.md` — bluetooth-central、state restoration、iOS 后台广播降级
7. `06-配对绑定与安全.md` — Just Works/Passkey、insufficientAuthentication、iOS 无绑定 API 的现实
8. `07-面试高频 FAQ.md` — 对齐第 11 课:OTA、iBeacon、Mesh、双端差异

## 7. 验收标准

- [ ] `xcodebuild build` 通过(iPhone 17 Pro 模拟器)
- [ ] `xcodebuild test` 全部单测通过
- [ ] 模拟器 Mock 模式可离线走通扫描→连接→浏览服务→订阅心率→私有协议收发
- [ ] docs/ 8 篇文档完整、互相引用、无 TBD
