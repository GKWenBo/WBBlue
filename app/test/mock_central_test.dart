import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_ble_app/core/ble/ble_central.dart';
import 'package:wb_ble_app/core/ble/mock_ble_central.dart';
import 'package:wb_ble_app/core/heart_rate.dart';
import 'package:wb_ble_app/core/protocol/packet.dart';

void main() {
  // 关掉故障注入，让全流程确定可断言（故障路径由 packet_test 覆盖）。
  late MockBleCentral central;

  setUp(() => central = MockBleCentral(faultInjection: false));
  tearDown(() => central.dispose());

  test('扫描能发现两台虚拟设备', () async {
    final hits = await central
        .scan()
        .firstWhere((list) => list.length >= 2)
        .timeout(const Duration(seconds: 2));
    expect(hits.map((h) => h.id), containsAll(['MOCK-HR', 'MOCK-PROTO']));
  });

  test('全流程离线跑通：连接→发现→私有协议往返', () async {
    const id = 'MOCK-PROTO';
    await central.connect(id);
    final services = await central.discoverServices(id);
    final proto = services.firstWhere((s) => s.uuid == MockUuids.protoService);
    expect(proto.characteristics.map((c) => c.uuid),
        containsAll([MockUuids.protoWrite, MockUuids.protoNotify]));

    // 先订阅通知，再下发命令帧
    final received = <int>[];
    final sub = central
        .subscribe(id, MockUuids.protoNotify)
        .listen(received.addAll);

    final frame = PacketCodec.encode(
        Packet(cmd: 0x10, seq: 0x01, payload: Uint8List.fromList([0xAB, 0xCD])));
    await central.write(id, MockUuids.protoWrite, frame);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    // 客户端侧组包，解出固件回帧
    final events = PacketAssembler().feed(received);
    expect(events, hasLength(1));
    final resp = (events.single as PacketReceived).packet;
    expect(resp.cmd, 0x10 | 0x80); // 响应置高位
    expect(resp.seq, 0x01); // seq 配对
    expect(resp.payload, [0xAB, 0xCD]); // 负载回显
  });

  test('心率虚拟设备推出可解析的 BPM', () async {
    final first = await central
        .subscribe('MOCK-HR', MockUuids.hrMeasure)
        .first
        .timeout(const Duration(seconds: 3));
    final bpm = parseHeartRate(first);
    expect(bpm, isNotNull);
    expect(bpm, inInclusiveRange(40, 200)); // 生理合理区间
  });

  test('连接/断开事件流可观测', () async {
    const id = 'MOCK-HR';
    final states = <BleConnState>[];
    final sub = central.connectionState(id).listen(states.add);
    await central.connect(id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await central.disconnect(id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    expect(states, [BleConnState.connected, BleConnState.disconnected]);
  });
}
