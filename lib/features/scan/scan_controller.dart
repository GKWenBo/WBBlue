import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 扫描页的状态与逻辑（第 2 课）。
///
/// 职责：把 flutter_blue_plus 的三条广播流（适配器状态 / 扫描结果 / 是否扫描中）
/// 收拢成一份可监听的 UI 状态。依赖方向 View → Controller → 插件，
/// Controller 不依赖任何 Widget，为第 8 课抽接口做 Mock 留好口子。
class ScanController extends ChangeNotifier {
  ScanController() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      adapterState = state;
      // 蓝牙被用户关闭时系统会自动终止扫描，累积结果已经过期，一并清掉
      if (state != BluetoothAdapterState.on) {
        results = const [];
      }
      notifyListeners();
    });

    // scanResults 是「累积快照流」：每次发射本轮扫描至今发现的全部设备。
    // 注意它不会自动移除已消失的设备，除非 startScan 配了 removeIfGone。
    _resultsSub = FlutterBluePlus.scanResults.listen(
      (snapshot) {
        results = snapshot;
        notifyListeners();
      },
      onError: (Object e) {
        lastError = '$e';
        notifyListeners();
      },
    );

    _scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      isScanning = scanning;
      notifyListeners();
    });
  }

  /// 标准心率服务（第 1 课在 nRF Connect 里看到的 0x180D）
  static final Guid heartRateService = Guid('180D');

  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  List<ScanResult> results = const [];
  bool isScanning = false;
  String? lastError;

  /// 过滤开关：隐藏无名设备（环境噪音大半是无名广播）
  bool hideUnnamed = true;

  /// 过滤开关：只扫心率服务（withServices 在系统层过滤，比拿到再筛省电）
  bool onlyHeartRate = false;

  late final StreamSubscription<BluetoothAdapterState> _adapterSub;
  late final StreamSubscription<List<ScanResult>> _resultsSub;
  late final StreamSubscription<bool> _scanningSub;

  /// 应用「隐藏无名设备」后的展示列表。
  /// 刻意不按 RSSI 排序：RSSI 每秒都在抖，实时排序会让条目上下乱跳没法点击。
  List<ScanResult> get visibleResults => hideUnnamed
      ? results.where((r) => displayName(r).isNotEmpty).toList()
      : results;

  /// 名字的三个来源按可靠度取：广播名 → 系统缓存名 → 空
  static String displayName(ScanResult r) {
    if (r.advertisementData.advName.isNotEmpty) {
      return r.advertisementData.advName;
    }
    return r.device.platformName;
  }

  Future<void> startScan() async {
    lastError = null;
    notifyListeners();
    try {
      // timeout 必带：安卓 30 秒内启停扫描超 5 次会被系统节流，
      // 无限扫既费电又容易触发节流惩罚。
      await FlutterBluePlus.startScan(
        withServices: onlyHeartRate ? [heartRateService] : const [],
        timeout: const Duration(seconds: 15),
        // 默认同一设备只上报一次（广播变化才再报），
        // 开 continuousUpdates 才能看到 RSSI 实时跳动
        continuousUpdates: true,
      );
    } catch (e) {
      // 权限被拒 / 蓝牙未开 / 定位服务未开都会走到这里，是业务分支不是兜底
      lastError = '$e';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  Future<void> toggleScan() => isScanning ? stopScan() : startScan();

  void setHideUnnamed(bool value) {
    hideUnnamed = value;
    notifyListeners();
  }

  /// 切换服务过滤后需重启扫描才生效（过滤条件是 startScan 的入参）
  Future<void> setOnlyHeartRate(bool value) async {
    onlyHeartRate = value;
    notifyListeners();
    if (isScanning) {
      await stopScan();
      await startScan();
    }
  }

  @override
  void dispose() {
    _adapterSub.cancel();
    _resultsSub.cancel();
    _scanningSub.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}
