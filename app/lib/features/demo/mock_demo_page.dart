import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/ble/ble_central.dart';
import '../../core/ble/mock_ble_central.dart';
import '../../core/heart_rate.dart';
import '../../core/hex.dart';
import '../../core/protocol/packet.dart';
import '../device/heart_rate_chart.dart';

/// 离线演示页（第 8 课）：整页只依赖 [BleCentral] 抽象，
/// 注入的是 [MockBleCentral]。换成 RealBleCentral 即真机——这就是分层的价值。
class MockDemoPage extends StatefulWidget {
  const MockDemoPage({super.key});

  @override
  State<MockDemoPage> createState() => _MockDemoPageState();
}

class _MockDemoPageState extends State<MockDemoPage> {
  // 仅本页顶层持有具体类型（要用 faultInjection 开关 + dispose）；
  // 传给子页面时收窄为 BleCentral 接口，业务代码只见抽象。
  final MockBleCentral _central = MockBleCentral();

  List<BleScanHit> _hits = const [];
  StreamSubscription<List<BleScanHit>>? _scanSub;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    _scanSub?.cancel();
    _hits = const [];
    _scanSub = _central.scan().listen((hits) => setState(() => _hits = hits));
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _central.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('离线演示（Mock）'),
        actions: [
          Row(
            children: [
              const Text('故障注入', style: TextStyle(fontSize: 12)),
              Switch(
                value: _central.faultInjection,
                onChanged: (v) => setState(() => _central.faultInjection = v),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('无需真机。本页只依赖 BleCentral 接口，注入 MockBleCentral。'
                '故障注入会随机制造掉线与坏帧。'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                for (final h in _hits)
                  ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(h.name),
                    subtitle: Text('${h.id} · RSSI ${h.rssi}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _MockDevicePage(
                          central: _central,
                          hit: h,
                        ),
                      ),
                    ),
                  ),
                if (_hits.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('扫描中…')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个虚拟设备页：HR 设备显示曲线，协议设备显示迷你控制台。
class _MockDevicePage extends StatefulWidget {
  const _MockDevicePage({required this.central, required this.hit});

  final BleCentral central;
  final BleScanHit hit;

  @override
  State<_MockDevicePage> createState() => _MockDevicePageState();
}

class _MockDevicePageState extends State<_MockDevicePage> {
  BleConnState _state = BleConnState.disconnected;
  List<BleService> _services = const [];
  final List<int> _hr = [];
  int? _bpm;
  final List<String> _protoLog = [];
  final PacketAssembler _assembler = PacketAssembler();
  int _seq = 0;

  StreamSubscription<BleConnState>? _stateSub;
  StreamSubscription<Uint8List>? _valueSub;

  String get _id => widget.hit.id;

  @override
  void initState() {
    super.initState();
    _stateSub = widget.central.connectionState(_id).listen((s) {
      setState(() => _state = s);
    });
    _connect();
  }

  Future<void> _connect() async {
    await widget.central.connect(_id);
    final services = await widget.central.discoverServices(_id);
    setState(() => _services = services);
    // HR 设备自动订阅心率
    if (_id == 'MOCK-HR') {
      _valueSub = widget.central
          .subscribe(_id, MockUuids.hrMeasure)
          .listen((bytes) {
        final bpm = parseHeartRate(bytes);
        if (bpm != null) {
          setState(() {
            _bpm = bpm;
            _hr.add(bpm);
            if (_hr.length > 120) _hr.removeAt(0);
          });
        }
      });
    } else {
      // 协议设备：订阅通知，字节喂进组包器
      _valueSub =
          widget.central.subscribe(_id, MockUuids.protoNotify).listen((bytes) {
        for (final e in _assembler.feed(bytes)) {
          setState(() {
            if (e is PacketReceived) {
              _protoLog.insert(0,
                  '↓ 回帧 cmd=0x${e.packet.cmd.toRadixString(16)} '
                  'payload=${toHexString(e.packet.payload)}');
            } else if (e is PacketErrorEvent) {
              _protoLog.insert(0, '坏帧：${e.error.name}（已重同步）');
            }
          });
        }
      });
    }
  }

  Future<void> _sendFrame() async {
    final frame = PacketCodec.encode(Packet(
      cmd: 0x10,
      seq: _seq++ & 0xFF,
      payload: Uint8List.fromList([0x01, 0x02, 0x03]),
    ));
    setState(() => _protoLog.insert(0, '↑ 发送 cmd=0x10 payload=01 02 03'));
    for (final part in PacketCodec.chunks(frame, widget.central.maxWriteLength(_id))) {
      await widget.central.write(_id, MockUuids.protoWrite, part);
    }
  }

  @override
  void dispose() {
    _valueSub?.cancel();
    _stateSub?.cancel();
    widget.central.disconnect(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _state == BleConnState.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.hit.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(connected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled),
              title: Text(connected ? '已连接' : '未连接'),
              subtitle: Text('${_services.length} 个服务'),
            ),
          ),
          if (_id == 'MOCK-HR' && _hr.isNotEmpty) ...[
            const SizedBox(height: 16),
            HeartRateChart(samples: _hr, currentBpm: _bpm),
          ],
          if (_id == 'MOCK-PROTO') ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: connected ? _sendFrame : null,
              icon: const Icon(Icons.send),
              label: const Text('发送命令帧'),
            ),
            const SizedBox(height: 12),
            for (final line in _protoLog)
              Text(line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
