import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wb_ble_app/features/scan/scan_controller.dart';

/// ScanResult / AdvertisementData 是纯 Dart 类，构造不触发平台通道，
/// 因此展示逻辑可以脱离蓝牙硬件做单元测试（第 8 课会把这个思路推广到全链路）。
ScanResult _result({String advName = ''}) {
  return ScanResult(
    device: BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF'),
    advertisementData: AdvertisementData(
      advName: advName,
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: const {},
      serviceData: const {},
      serviceUuids: const [],
    ),
    rssi: -50,
    timeStamp: DateTime.now(),
  );
}

void main() {
  test('显示名优先取广播名 advName', () {
    expect(ScanController.displayName(_result(advName: 'HR-Sim')), 'HR-Sim');
  });

  test('无广播名且无系统缓存名时为空（UI 显示占位符并可被过滤）', () {
    expect(ScanController.displayName(_result()), isEmpty);
  });
}
