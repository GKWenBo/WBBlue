# wb_ble_app —— BLE 实战学习仓库

两个平行项目,同一套企业 BLE 知识体系:

| 目录 | 技术栈 | 说明 |
|---|---|---|
| [`WBBlueSwift/`](WBBlueSwift/) | **Swift 原生**:CoreBluetooth + async/await + SwiftUI + Swift Testing | 完整企业级示例:扫描/连接/GATT/订阅/私有协议/自动重连/外设模式/Mock 架构,27 项单测,技术文档 9 篇 → [文档入口](WBBlueSwift/docs/README.md) |
| [`app/`](app/) | Flutter + flutter_blue_plus | 按课时推进的双端实战课程 → [课程进度](app/docs/PROGRESS.md) |

## WBBlueSwift 快速开始

```bash
open WBBlueSwift/WBBlueSwift.xcodeproj
```

模拟器直接运行(自动使用 Mock 虚拟设备,可离线走通全流程 + 故障注入演示异常处理);真机在扫描页 ⚙️ 切换真实 CoreBluetooth。详见 [WBBlueSwift/docs/README.md](WBBlueSwift/docs/README.md)。
