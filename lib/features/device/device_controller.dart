import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/gatt_names.dart';
import '../../core/heart_rate.dart';

/// 设备详情页的连接状态机（第 3 课）。
///
/// 两层状态刻意分开：
/// - [connectionState]：链路状态，来自协议栈，只有 connected/disconnected 两值
///   （FBP 2.x 不再发射 connecting/disconnecting）；
/// - [busy]：UI 状态，connect/disconnect 动作进行中，由本类自己维护。
/// 混用两者是蓝牙 App 状态错乱的经典根源。
class DeviceController extends ChangeNotifier {
  DeviceController(this.device) {
    // 断线感知只能靠这条流：外设关机/走远/被系统踢掉都不会有 Future 通知。
    // 因此订阅发生在构造时，而不是 connect 之后。
    _stateSub = device.connectionState.listen((state) {
      connectionState = state;
      if (state == BluetoothConnectionState.disconnected) {
        disconnectReason = device.disconnectReason;
        // 句柄表属于「这一次连接」：断线即作废，不缓存不落盘
        services = const [];
        // 订阅同理（CCCD 随连接复位），流已由 cancelWhenDisconnected 取消
        _valueSubs.clear();
        currentBpm = null;
      } else {
        disconnectReason = null;
      }
      notifyListeners();
    });
  }

  final BluetoothDevice device;

  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  bool busy = false;
  DisconnectReason? disconnectReason;
  String? lastError;

  /// 连接态下 readRssi 的结果（链路 RSSI，与扫描时的广播 RSSI 是两条通道）
  int? linkRssi;

  /// 本次连接发现的服务表（第 4 课）
  List<BluetoothService> services = const [];
  bool discovering = false;

  /// 心率样本环形缓存（第 5 课）：上限约 2 分钟，防止长订阅内存无限涨
  static const int maxHrSamples = 120;
  final List<int> hrSamples = [];
  int? currentBpm;

  late final StreamSubscription<BluetoothConnectionState> _stateSub;

  bool get isConnected =>
      connectionState == BluetoothConnectionState.connected;

  Future<void> connect() async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await device.connect(
        // 教学/个人作品属非营利用途；FBP 2.x 商用需购买授权（见讲义第一节）
        license: License.nonprofit,
        // 默认 35s 用户等不起，企业惯例压到 8-15s
        timeout: const Duration(seconds: 10),
      );
      // 企业 App 的标准流程：连上即发现服务，用户不该关心这一步
      await discoverServices();
    } catch (e) {
      // 超时 / 外设不在了 / 安卓 133 都从这里出来，是业务分支不是兜底
      lastError = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    busy = true;
    notifyListeners();
    try {
      await device.disconnect();
    } catch (e) {
      lastError = '$e';
    } finally {
      busy = false;
      linkRssi = null;
      notifyListeners();
    }
  }

  /// 服务发现：把外设属性表拉回本地建立 UUID→句柄映射。
  /// 每次连接后必做——句柄表随固件升级重排，不可跨连接复用（讲义第一节）。
  Future<void> discoverServices() async {
    if (!isConnected) return;
    discovering = true;
    notifyListeners();
    try {
      services = await device.discoverServices();
    } catch (e) {
      lastError = '$e';
    } finally {
      discovering = false;
      notifyListeners();
    }
  }

  /// 订阅/取消订阅通知（第 5 课）。
  /// setNotifyValue 在协议层做两件事：本地向系统蓝牙栈注册回调 +
  /// 远端向 CCCD（0x2902）写 01 00 / 00 00。
  /// 订阅状态不自己存 bool，UI 直接读 c.isNotifying（反查 CCCD，单一事实来源）。
  Future<void> toggleNotify(BluetoothCharacteristic c) async {
    try {
      final enable = !c.isNotifying;
      if (enable && !_valueSubs.containsKey(c.uuid)) {
        // 先挂监听再开闸，避免开闸瞬间的首包漏掉。
        // onValueReceived 只含读回与通知（不混写回显），上报处理统一接它。
        final sub = c.onValueReceived.listen((value) {
          if (shortUuid(c.uuid) == '2A37') {
            final bpm = parseHeartRate(value);
            if (bpm != null) {
              currentBpm = bpm;
              hrSamples.add(bpm);
              if (hrSamples.length > maxHrSamples) hrSamples.removeAt(0);
            }
          }
          notifyListeners();
        });
        // 断线自动取消订阅，防泄漏（订阅生命周期 ≤ 连接生命周期）
        device.cancelWhenDisconnected(sub);
        _valueSubs[c.uuid] = sub;
      }
      await c.setNotifyValue(enable);
      if (!enable) {
        await _valueSubs.remove(c.uuid)?.cancel();
      }
    } catch (e) {
      lastError = '$e';
    }
    notifyListeners();
  }

  final Map<Guid, StreamSubscription<List<int>>> _valueSubs = {};

  /// 读特征值。结果同时进 characteristic.lastValue，UI 直接读它展示。
  Future<void> readCharacteristic(BluetoothCharacteristic c) async {
    try {
      await c.read();
    } catch (e) {
      lastError = '$e';
    }
    notifyListeners();
  }

  /// 写特征值。写类型选错（特征不支持）会在这里抛出，交给 UI 展示。
  Future<bool> writeCharacteristic(
    BluetoothCharacteristic c,
    List<int> data, {
    required bool withResponse,
  }) async {
    try {
      await c.write(data, withoutResponse: !withResponse);
      notifyListeners();
      return true;
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<void> readRssi() async {
    if (!isConnected) return;
    try {
      linkRssi = await device.readRssi();
    } catch (e) {
      lastError = '$e';
    }
    notifyListeners();
  }

  /// 断线原因的人话版：安卓是 GATT status，iOS 是 NSError code，
  /// 企业 App 靠它区分「用户主动断」和「信号掉线」来决定是否自动重连（第 7 课）。
  static String describeDisconnect(DisconnectReason? reason) {
    if (reason == null || reason.code == null) return '';
    return '断开原因 code ${reason.code}'
        '${reason.description == null ? '' : '（${reason.description}）'}';
  }

  @override
  void dispose() {
    _stateSub.cancel();
    // 本课策略「离开页面即断开」；第 7 课引入后台保活后会调整
    device.disconnect();
    super.dispose();
  }
}
