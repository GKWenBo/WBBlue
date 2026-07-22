// Mock 实现（第 8 课）：一组虚拟设备，无需真机即可走通
// 扫描 → 连接 → 服务发现 → 订阅 → 私有协议收发 全流程，并可注入故障。
//
// 价值：模拟器/CI 上离线演示与自动化测试；异常路径（掉线、坏帧）可复现——
// 真机很难稳定制造这些故障。
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/packet.dart';
import 'ble_central.dart';

/// 虚拟设备 UUID 常量。
class MockUuids {
  static const hrService = '180D';
  static const hrMeasure = '2A37';
  static const protoService = 'FF00';
  static const protoWrite = 'FF01';
  static const protoNotify = 'FF02';
}

class MockBleCentral implements BleCentral {
  MockBleCentral({this.faultInjection = false, Random? random})
      : _random = random ?? Random();

  /// 打开后：连接后可能随机掉线（演示重连）、协议回帧可能被打散或损坏（演示组包）。
  bool faultInjection;
  final Random _random;

  // ── 虚拟设备目录 ──
  static final List<BleScanHit> _catalog = [
    const BleScanHit(
      id: 'MOCK-HR',
      name: 'Mock 心率带',
      rssi: -45,
      serviceUuids: [MockUuids.hrService],
    ),
    const BleScanHit(
      id: 'MOCK-PROTO',
      name: 'Mock 固件设备',
      rssi: -58,
      serviceUuids: [MockUuids.protoService],
    ),
  ];

  final Map<String, StreamController<BleConnState>> _conn = {};
  final Map<String, StreamController<Uint8List>> _notify = {};
  final Map<String, PacketAssembler> _rxAssembler = {};
  Timer? _faultTimer;
  StreamController<List<BleScanHit>>? _scanCtrl;

  @override
  Stream<List<BleScanHit>> scan({List<String> services = const []}) {
    _scanCtrl?.close();
    final hits = services.isEmpty
        ? _catalog
        : _catalog
            .where((h) => h.serviceUuids.any(services.contains))
            .toList();
    final ctrl = StreamController<List<BleScanHit>>();
    _scanCtrl = ctrl;
    // 模拟设备逐个被发现
    () async {
      final found = <BleScanHit>[];
      for (final h in hits) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (ctrl.isClosed) return;
        found.add(h);
        ctrl.add(List.of(found));
      }
    }();
    return ctrl.stream;
  }

  @override
  Future<void> stopScan() async {
    await _scanCtrl?.close();
    _scanCtrl = null;
  }

  StreamController<BleConnState> _connCtrl(String id) =>
      _conn.putIfAbsent(id, () => StreamController<BleConnState>.broadcast());

  @override
  Stream<BleConnState> connectionState(String deviceId) {
    final ctrl = _connCtrl(deviceId);
    // 订阅时补发当前状态（默认未连接）
    return ctrl.stream;
  }

  @override
  Future<void> connect(String deviceId, {Duration timeout = const Duration(seconds: 8)}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _connCtrl(deviceId).add(BleConnState.connected);
    _scheduleFaultDisconnect(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _faultTimer?.cancel();
    _connCtrl(deviceId).add(BleConnState.disconnected);
  }

  /// 故障注入：随机在 4-10 秒后制造一次意外掉线，用于演示自动重连。
  void _scheduleFaultDisconnect(String deviceId) {
    _faultTimer?.cancel();
    if (!faultInjection) return;
    final ms = 4000 + _random.nextInt(6000);
    _faultTimer = Timer(Duration(milliseconds: ms), () {
      _connCtrl(deviceId).add(BleConnState.disconnected);
    });
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (deviceId == 'MOCK-HR') {
      return const [
        BleService(uuid: MockUuids.hrService, characteristics: [
          BleChar(uuid: MockUuids.hrMeasure, notify: true),
        ]),
      ];
    }
    return const [
      BleService(uuid: MockUuids.protoService, characteristics: [
        BleChar(uuid: MockUuids.protoWrite, write: true, writeNoResponse: true),
        BleChar(uuid: MockUuids.protoNotify, notify: true),
      ]),
    ];
  }

  @override
  Future<Uint8List> read(String deviceId, String charUuid) async {
    return Uint8List.fromList([0x00]);
  }

  @override
  Future<void> write(
    String deviceId,
    String charUuid,
    Uint8List data, {
    bool withResponse = true,
  }) async {
    if (charUuid != MockUuids.protoWrite) return;
    // 固件侧组包：把收到的字节喂进接收组包器（跨多次写累积，处理分包）
    final asm = _rxAssembler.putIfAbsent(deviceId, () => PacketAssembler());
    for (final event in asm.feed(data)) {
      if (event is PacketReceived) {
        _respondTo(deviceId, event.packet);
      }
    }
  }

  /// 固件回帧：cmd 置高位表示「响应」，payload 原样回显（ACK）。
  void _respondTo(String deviceId, Packet req) {
    final resp = Packet(
      cmd: req.cmd | 0x80,
      seq: req.seq,
      payload: req.payload,
    );
    var frame = PacketCodec.encode(resp);

    final ctrl = _notify['$deviceId/${MockUuids.protoNotify}'];
    if (ctrl == null || ctrl.isClosed) return;

    if (faultInjection && _random.nextDouble() < 0.25) {
      // 25% 概率损坏 CRC，演示接收端「坏帧重同步」
      frame = Uint8List.fromList(frame);
      frame[frame.length - 1] ^= 0xFF;
    }
    if (faultInjection && _random.nextBool()) {
      // 一半概率把回帧拆两次发，演示接收端半包处理
      final mid = frame.length ~/ 2;
      ctrl.add(Uint8List.sublistView(frame, 0, mid));
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        if (!ctrl.isClosed) ctrl.add(Uint8List.sublistView(frame, mid));
      });
    } else {
      ctrl.add(frame);
    }
  }

  @override
  Stream<Uint8List> subscribe(String deviceId, String charUuid) {
    if (deviceId == 'MOCK-HR' && charUuid == MockUuids.hrMeasure) {
      return _heartRateStream();
    }
    // 协议通知：持久 broadcast，write 时向它推回帧
    final key = '$deviceId/$charUuid';
    final ctrl = _notify.putIfAbsent(
        key, () => StreamController<Uint8List>.broadcast());
    return ctrl.stream;
  }

  /// 心率通知流：每秒一个样本，缓慢正弦波动 + 噪声，编码为 [flags=0, bpm]。
  Stream<Uint8List> _heartRateStream() {
    late StreamController<Uint8List> ctrl;
    Timer? timer;
    var tick = 0;
    ctrl = StreamController<Uint8List>(
      onListen: () {
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          final bpm = (72 + 12 * sin(tick / 6) + _random.nextInt(4)).round();
          tick++;
          ctrl.add(Uint8List.fromList([0x00, bpm & 0xFF]));
        });
      },
      onCancel: () => timer?.cancel(),
    );
    return ctrl.stream;
  }

  @override
  int maxWriteLength(String deviceId) => 20; // 模拟默认 MTU 23 → 负载 20

  void dispose() {
    _faultTimer?.cancel();
    for (final c in _conn.values) {
      c.close();
    }
    for (final c in _notify.values) {
      c.close();
    }
    _scanCtrl?.close();
  }
}
