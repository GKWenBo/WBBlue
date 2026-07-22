// BLE 能力的抽象接口（第 8 课）。
//
// 业务与 UI 只依赖这个接口，不直接 import flutter_blue_plus。
// 真实实现 RealBleCentral（包 FBP）与 MockBleCentral（虚拟设备）共同遵循，
// 于是硬件可替换、可离线演示、可单元测试——这是企业架构的关键一层。
//
// 接口只暴露平台中立的模型（下面这些 class），不泄露任何 FBP 类型，
// 否则「抽象」就是假的：换实现时业务代码仍会被 FBP 的类型绑死。
import 'dart:typed_data';

enum BleConnState { disconnected, connected }

/// 一次扫描命中（平台中立，不含 FBP 的 ScanResult）。
class BleScanHit {
  const BleScanHit({
    required this.id,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
    this.connectable = true,
  });

  final String id;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
  final bool connectable;
}

/// GATT 特征快照（只带业务关心的属性位）。
class BleChar {
  const BleChar({
    required this.uuid,
    this.read = false,
    this.write = false,
    this.writeNoResponse = false,
    this.notify = false,
    this.indicate = false,
  });

  final String uuid;
  final bool read;
  final bool write;
  final bool writeNoResponse;
  final bool notify;
  final bool indicate;
}

/// GATT 服务快照。
class BleService {
  const BleService({required this.uuid, required this.characteristics});
  final String uuid;
  final List<BleChar> characteristics;
}

/// Central（主机）能力接口。所有方法以设备 id（字符串）寻址，
/// 屏蔽了安卓 MAC / iOS UUID 的差异。
abstract interface class BleCentral {
  /// 扫描并持续吐出「累积命中列表」快照。services 非空时按服务 UUID 过滤。
  Stream<List<BleScanHit>> scan({List<String> services});
  Future<void> stopScan();

  /// 指定设备的连接状态流（可多路订阅，订阅时补发当前状态）。
  Stream<BleConnState> connectionState(String deviceId);

  Future<void> connect(String deviceId, {Duration timeout});
  Future<void> disconnect(String deviceId);

  Future<List<BleService>> discoverServices(String deviceId);

  Future<Uint8List> read(String deviceId, String charUuid);

  Future<void> write(
    String deviceId,
    String charUuid,
    Uint8List data, {
    bool withResponse = true,
  });

  /// 订阅通知：内部负责写 CCCD 开启；取消订阅（cancel）时关闭。
  Stream<Uint8List> subscribe(String deviceId, String charUuid);

  /// 连接态单帧最大写负载（ATT_MTU - 3），分包依据。
  int maxWriteLength(String deviceId);
}
