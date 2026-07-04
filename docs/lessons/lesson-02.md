# 第 2 课：扫描实战（1 课时）

> 本课起开始写代码。目标：App 能扫到并列出另一台手机模拟的外设，理解权限、节流、结果流三大工程要点。

## 一、权限：代码里「没写」的那部分去哪了

第 0 课我们在 AndroidManifest 里配了两套权限，本课不引入 permission_handler——因为读 flutter_blue_plus 安卓端源码（`FlutterBluePlusPlugin.java` 的 `onMethodCall("startScan")`）会发现它在扫描前自动做了三件事：

1. **检查定位服务开关**（`androidCheckLocationServices`，默认 true）：Android ≤ 11 上系统定位总开关没开时，BLE 扫描静默返回空结果——这是企业开发著名深坑，插件直接帮你拦下来报错。
2. **按系统版本申请运行时权限**：API 31+ 申请 `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`；API ≤ 30 申请 `ACCESS_FINE_LOCATION`。第一次扫描时你会看到系统弹「允许 xx 查找附近的设备」（Android 12+ 的文案）。
3. **检查蓝牙适配器状态**，没开直接报错。

**工程启示**：插件帮你申请 ≠ 你不用管。权限被永久拒绝后 `startScan` 会抛错，UI 必须接住并引导用户去设置页——所以 Controller 里 `try/catch` 不是防御性套路，是必须的业务分支。iOS 则简单：首次触发蓝牙 API 时系统自动弹一次授权框（文案就是 Info.plist 里那句），拒绝后 `adapterState` 变 `unauthorized`。

## 二、扫描三条流

flutter_blue_plus 把扫描建模成三条广播流 + 一个动作，我们的 `ScanController` 就是订阅它们再转成 UI 状态：

| API | 是什么 | 用法要点 |
|---|---|---|
| `FlutterBluePlus.adapterState` | 蓝牙开关状态流 | 关蓝牙时扫描自动停，UI 要显示「请打开蓝牙」空态 |
| `FlutterBluePlus.scanResults` | **累积快照流**：每次发射的是"本轮扫描至今发现的全部设备"列表 | 与 `onScanResults`（逐个发射）二选一，列表 UI 用前者省事 |
| `FlutterBluePlus.isScanning` | 是否正在扫描 | 驱动按钮的 开始/停止 状态，别自己维护 bool |
| `FlutterBluePlus.startScan(...)` | 动作 | `withServices` 按服务 UUID 过滤；`timeout` 自动停止；`continuousUpdates: true` 才会持续刷新 RSSI |

三个必知行为：

- **去重**：默认同一设备只上报一次（广播内容变了才再报）。想要 RSSI 实时跳动必须 `continuousUpdates: true`（我们开了，代价是回调频繁，生产项目常配 `continuousDivisor` 降频）。
- **列表不会自动"减员"**：设备关机走远，它仍留在累积列表里。想自动移除要配 `removeIfGone`。企业 App 的扫描页几乎都有这个需求，否则用户看着一堆"幽灵设备"。
- **安卓扫描节流**：30 秒内启动扫描超过 5 次，系统直接给你静默降级/拒绝（logcat 有 `App 'xxx' is scanning too frequently`）。所以扫描要带 `timeout`、按钮要防连点，别写"进页面就无限扫"。

## 三、扫描结果里有什么

`ScanResult`：`device`（`remoteId` + `platformName`）、`rssi`、`advertisementData`、`timeStamp`。

`AdvertisementData` 就是第 1 课广播包的解析产物：`advName` / `connectable` / `serviceUuids` / `manufacturerData`（`Map<厂商ID, 字节>`）/ `serviceData` / `txPowerLevel`。

两个双端差异（第 1 课理论的代码印证）：

- `device.remoteId`：安卓 = 真 MAC（`AA:BB:CC:DD:EE:FF`），iOS = 系统生成的 UUID，换台 iPhone 就不同 → 跨平台"设备唯一标识"必须自己从广播（如厂商数据）或 GATT 里取。
- 名字有三个来源：广播里的 `advName`、系统缓存的 `platformName`、连接后 GATT 里的 Device Name。显示优先级建议 `advName` → `platformName` → 占位符。

## 四、本课代码结构

```
lib/
├── main.dart                        # App 入口，home 指向扫描页
└── features/scan/
    ├── scan_controller.dart         # ChangeNotifier：订阅三条流 → UI 状态
    └── scan_page.dart               # 扫描列表 UI（空态/错误态/结果列表/过滤开关）
```

依赖方向 View → Controller → flutter_blue_plus，Controller 不 import Flutter Widget，后面第 8 课抽接口做 Mock 时它几乎不用改。

UI 细节里的工程判断：

- **列表不按 RSSI 实时排序**：RSSI 每秒都在抖，实时排序 = 条目上下乱跳没法点。企业做法：按发现顺序稳定排列，RSSI 只作为条目内的信号图标。
- 过滤做成两个开关：「隐藏无名设备」（环境里 90% 的广播是无名的耳机/信标，噪音）和「只看心率服务」（`withServices: [Guid("180D")]`，在系统层过滤，比拿到结果再筛更省电）。

## 五、动手任务

1. iPhone：LightBlue 开启 Heart Rate 虚拟外设（前台、亮屏）。
2. 安卓：`flutter run` 装上 App → 点扫描 → **观察第一次的系统权限弹窗长什么样**（这是 Android 12+ 的「附近的设备」权限，不是定位）。
3. 找到心率外设，打开「只看心率服务」开关验证过滤，观察 RSSI 随距离变化。
4. 换边：安卓开 nRF Connect → ADVERTISER 页新建一条广播（随便加个 Complete Local Name）；iPhone 上 `flutter run` 本 App 扫它，对比 iOS 的授权弹窗与 remoteId 形态。

## 验收

1. App（安卓端）扫到 LightBlue 心率外设，服务过滤开关工作正常。
2. App（iOS 端）扫到 nRF Connect 的自定义广播。
3. 回答：① 扫描列表里同一台设备，安卓和 iOS 显示的 remoteId 有什么本质不同？对「记住已绑定设备」功能意味着什么？② 为什么扫描必须带 timeout、按钮要防连点？③ `scanResults` 列表里的设备关机了，条目会消失吗？怎么让它消失？
