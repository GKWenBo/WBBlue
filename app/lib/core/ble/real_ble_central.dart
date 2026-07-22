// 真实实现（第 8 课）：把 flutter_blue_plus 适配到 BleCentral 接口。
//
// 它是唯一 import FBP 的地方（除历史课的页面外）。所有 FBP 类型都在此
// 转换成中立模型再出去——「防腐层」把三方库的形状挡在业务之外，
// 将来换库（如 flutter_reactive_ble）只动这一个文件。
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_central.dart';

class RealBleCentral implements BleCentral {
  BluetoothDevice _device(String id) =>
      BluetoothDevice.fromId(id);

  BluetoothCharacteristic? _findChar(String deviceId, String charUuid) {
    for (final s in _device(deviceId).servicesList) {
      for (final c in s.characteristics) {
        if (c.uuid == Guid(charUuid)) return c;
      }
    }
    return null;
  }

  @override
  Stream<List<BleScanHit>> scan({List<String> services = const []}) {
    FlutterBluePlus.startScan(
      withServices: services.map(Guid.new).toList(),
      timeout: const Duration(seconds: 15),
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 4),
    );
    return FlutterBluePlus.scanResults.map((results) => [
          for (final r in results)
            BleScanHit(
              id: r.device.remoteId.str,
              name: r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName,
              rssi: r.rssi,
              serviceUuids:
                  r.advertisementData.serviceUuids.map((g) => g.str).toList(),
              connectable: r.advertisementData.connectable,
            ),
        ]);
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Stream<BleConnState> connectionState(String deviceId) =>
      _device(deviceId).connectionState.map((s) =>
          s == BluetoothConnectionState.connected
              ? BleConnState.connected
              : BleConnState.disconnected);

  @override
  Future<void> connect(String deviceId,
          {Duration timeout = const Duration(seconds: 10)}) =>
      _device(deviceId).connect(license: License.nonprofit, timeout: timeout);

  @override
  Future<void> disconnect(String deviceId) => _device(deviceId).disconnect();

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final services = await _device(deviceId).discoverServices();
    return [
      for (final s in services)
        BleService(
          uuid: s.serviceUuid.str,
          characteristics: [
            for (final c in s.characteristics)
              BleChar(
                uuid: c.uuid.str,
                read: c.properties.read,
                write: c.properties.write,
                writeNoResponse: c.properties.writeWithoutResponse,
                notify: c.properties.notify,
                indicate: c.properties.indicate,
              ),
          ],
        ),
    ];
  }

  @override
  Future<Uint8List> read(String deviceId, String charUuid) async {
    final c = _findChar(deviceId, charUuid);
    if (c == null) throw StateError('特征不存在：$charUuid');
    return Uint8List.fromList(await c.read());
  }

  @override
  Future<void> write(String deviceId, String charUuid, Uint8List data,
      {bool withResponse = true}) async {
    final c = _findChar(deviceId, charUuid);
    if (c == null) throw StateError('特征不存在：$charUuid');
    await c.write(data, withoutResponse: !withResponse);
  }

  @override
  Stream<Uint8List> subscribe(String deviceId, String charUuid) {
    final c = _findChar(deviceId, charUuid);
    if (c == null) throw StateError('特征不存在：$charUuid');
    // 开启 CCCD 后返回值流；调用方 cancel 时不自动关（教学从简）
    c.setNotifyValue(true);
    return c.onValueReceived.map(Uint8List.fromList);
  }

  @override
  int maxWriteLength(String deviceId) {
    final mtu = _device(deviceId).mtuNow;
    final payload = mtu - 3;
    return payload > 0 ? payload : 20;
  }
}
