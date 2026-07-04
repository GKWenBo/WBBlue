import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
      disconnectReason = state == BluetoothConnectionState.disconnected
          ? device.disconnectReason
          : null;
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
