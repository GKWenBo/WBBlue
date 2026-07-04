# Flutter BLE 实战课程进度

> 规则：**完成上一课并通过验收，才进入下一课。** 每课验收后在此勾选并记录日期与结论。
>
> 单课时约 1.5 小时：理论讲解 30min + 带练编码 50min + 真机验收 10min。
> 测试环境：两台手机——一台跑本 App（Central），另一台用 nRF Connect（安卓）/ LightBlue（iOS）模拟外设（Peripheral）。

## 课程总表

| 状态 | 课时 | 主题 | 验收标准 |
|:---:|---|---|---|
| ✅ | 第 0 课 | 环境与项目初始化 | 双端真机跑起空项目；两台手机装好 nRF Connect / LightBlue |
| 🔄 | 第 1 课 | BLE 理论地基（GAP/GATT/广播/MTU） | 能口述一次 BLE 连接的完整生命周期 |
| ⬜ | 第 2 课 | 扫描实战（运行时权限 / startScan / RSSI / 广播解析） | App 能扫到并列出另一台手机模拟的外设 |
| ⬜ | 第 3 课 | 连接管理（connect / 状态流 / 超时） | 与模拟外设建连断连，UI 状态实时正确 |
| ⬜ | 第 4 课 | GATT 读写（discoverServices / read / write） | 读写模拟外设上的自建 Characteristic 成功 |
| ⬜ | 第 5 课 | 订阅通知（Notify/Indicate / CCCD / 心率服务实战） | 实时心率数据流稳定刷新 |
| ⬜ | 第 6 课 | 私有二进制协议（帧结构 / CRC / 分包组包）★企业核心 | 协议编解码层完成 + 单元测试通过 |
| ⬜ | 第 7 课 | 稳定性工程（自动重连状态机 / 异常场景） | 外设消失再出现，App 自动恢复连接 |
| ⬜ | 第 8 课 | 架构分层与可测试性（接口抽象 + Mock 双实现） | Mock 下全流程可离线演示 |
| ⬜ | 第 9 课 | 双端平台差异与后台（iOS 状态恢复 / Android 前台服务） | 双端后台配置完成，能讲清差异 |
| ⬜ | 第 10 课 | 综合项目验收：「设备管家」全流程 | 双端真机演示全流程通过 |
| ⬜ | 第 11 课（可选） | 面试冲刺（高频题 / OTA / iBeacon / 配对绑定 / Mesh） | 模拟问答一轮 |

图例：⬜ 未开始 · 🔄 进行中 · ✅ 已验收

## 验收记录

### 第 0 课 —— ✅ 已验收（2026-07-04 开课，2026-07-04 验收）
- [x] 创建 Flutter 项目（Android + iOS），引入 flutter_blue_plus
- [x] Android 12+/11- 分层蓝牙权限配置（AndroidManifest.xml）
- [x] iOS 蓝牙用途声明（Info.plist：NSBluetoothAlwaysUsageDescription）
- [x] 安卓手机安装 nRF Connect（Play 商店受限，改用 GitHub Releases 官方 APK 4.29.1 + adb 安装）
- [x] iPhone 安装 LightBlue
- [x] 双端真机 `flutter run` 跑起空项目

备注：本机 Flutter 下载引擎产物需带国内镜像环境变量（`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`），否则首次 iOS 构建会因慢速下载假死。
思考题（Android 12 前扫描为何要定位权限 / neverForLocation 的代价）随第 1 课理论一并讲解确认。

### 第 1 课 —— 🔄 进行中（2026-07-04 开讲）
- [ ] 理论：GAP/GATT、广播包结构、连接生命周期、MTU（讲义 lessons/lesson-01.md）
- [ ] 实操：LightBlue 建虚拟外设，nRF Connect 扫描→连接→读 GATT 树（纯手机，不写代码）
- [ ] 验收：口述一次 BLE 连接的完整生命周期 + 回答本课与第 0 课思考题
