# 第 0 课：环境与项目初始化（0.5 课时）

## 本课目标

1. 项目跑通：wb_ble_app 在你的安卓手机和 iPhone 上都能启动。
2. 测试台搭好：另一台手机能扮演 BLE 外设。
3. 理解两件事：为什么蓝牙开发必须真机；为什么权限配置是双端两套逻辑。

## 一、为什么模拟器不能测蓝牙

- **iOS 模拟器**：CoreBluetooth 在模拟器上直接不可用（`CBCentralManager` 状态永远是 `.unsupported`）。模拟器没有蓝牙硬件栈，Apple 也从未桥接宿主 Mac 的蓝牙。
- **安卓模拟器**：新版模拟器有实验性的蓝牙透传，但极不稳定，企业开发没人用。
- **企业现实**：蓝牙团队人手至少一台安卓 + 一台 iPhone + 若干目标硬件。双端蓝牙栈行为差异大（扫描节流、后台策略、缓存机制），只测一端约等于没测。你的「一安卓 + 一 iPhone」正是标准配置。

## 二、我们的测试拓扑

企业场景 95% 是 **手机 App 做 Central（主机），硬件设备做 Peripheral（外设）**。没有硬件时，用另一台手机模拟外设：

```
┌─────────────────┐         BLE          ┌──────────────────────┐
│   手机 A         │ ◄──────────────────► │   手机 B              │
│   wb_ble_app    │   扫描/连接/读写/订阅   │   nRF Connect (安卓)  │
│   角色: Central  │                      │   LightBlue (iOS)    │
└─────────────────┘                      │   角色: Peripheral    │
                                         └──────────────────────┘
```

两台手机可以互换角色。注意：**iPhone 做外设时广播不带 MAC 地址且部分字段受限**（iOS 系统行为），所以模拟外设优先用安卓 + nRF Connect，功能最全。

### 需要安装的工具 App

| 手机 | App | 用途 |
|---|---|---|
| 安卓 | **nRF Connect for Mobile**（Nordic 出品，Play 商店） | 扫描分析 + GATT Server 模拟外设 + 广播自定义数据，蓝牙开发第一神器 |
| iPhone | **LightBlue**（Punch Through 出品，App Store） | iOS 端扫描分析 + 创建虚拟外设 |

## 三、权限配置（本课已完成，代码里看）

### Android —— [AndroidManifest.xml](../../android/app/src/main/AndroidManifest.xml)

Android 12（API 31）是分水岭，企业开发的第一坑：

| | Android ≤ 11 | Android 12+ |
|---|---|---|
| 扫描 | `BLUETOOTH` + 运行时**定位**权限（历史原因：BLE 广播可做室内定位） | `BLUETOOTH_SCAN`（运行时） |
| 连接 | `BLUETOOTH` / `BLUETOOTH_ADMIN` | `BLUETOOTH_CONNECT`（运行时） |

- 旧权限加 `android:maxSdkVersion="30"`，只在老系统上生效。
- `BLUETOOTH_SCAN` 上声明了 `neverForLocation`：承诺不用扫描结果推位置，就**不再需要定位权限**。代价：系统会过滤掉 iBeacon 等定位类广播。企业里做普通设备连接都这么配；做室内定位/Beacon 的产品则不能加。

### iOS —— [Info.plist](../../ios/Runner/Info.plist)

只需一条：`NSBluetoothAlwaysUsageDescription`（用途文案）。**没有它，App 一调蓝牙 API 直接闪退**，这是 iOS 蓝牙开发最经典的第一次崩溃。iOS 不区分扫描/连接权限，用户只面对一次「是否允许使用蓝牙」弹窗。

## 四、动手任务（你的验收作业）

1. 安卓手机装 **nRF Connect**，iPhone 装 **LightBlue**。
2. 分别在两台真机上运行项目：
   ```bash
   cd /Users/wenbo/Desktop/WBAIProject/wb_ble_app
   flutter devices          # 确认两台手机都被识别（iPhone 需信任电脑；首跑需在 Xcode 里配置签名 Team）
   flutter run -d <设备id>
   ```
3. 打开 nRF Connect 的 SCANNER 页随便扫一扫，感受一下周围的 BLE 广播世界（第 1 课我们会逐字段解读它显示的内容）。

三项都完成后告诉我，勾掉 [PROGRESS.md](../PROGRESS.md) 里的验收项，进入第 1 课。

## 本课思考题（下课口头回答）

1. 为什么 Android 12 之前扫描蓝牙要定位权限，而 iOS 从来不要？
2. `neverForLocation` 省掉了定位权限，代价是什么？什么产品不能加它？
