import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_ble_app/core/protocol/packet.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('crc16 CCITT-FALSE', () {
    test('标准校验值 "123456789" = 0x29B1', () {
      // CRC-16/CCITT-FALSE 官方 check 值，验证多项式实现正确
      final data = _bytes('123456789'.codeUnits);
      expect(PacketCodec.crc16(data), 0x29B1);
    });

    test('空数据 = 0xFFFF（初值）', () {
      expect(PacketCodec.crc16(const []), 0xFFFF);
    });
  });

  group('encode / 单帧结构', () {
    test('帧头、字段布局、CRC 正确', () {
      final frame = PacketCodec.encode(
        Packet(cmd: 0x10, seq: 0x01, payload: _bytes([0xAA, 0xBB])),
      );
      // A5 5A | 10 01 | 02 00 | AA BB | crc(2)
      expect(frame.sublist(0, 2), [0xA5, 0x5A]);
      expect(frame[2], 0x10); // cmd
      expect(frame[3], 0x01); // seq
      expect(frame[4], 0x02); // len 低字节（小端）
      expect(frame[5], 0x00); // len 高字节
      expect(frame.sublist(6, 8), [0xAA, 0xBB]);
      expect(frame.length, 10); // 6 头 + 2 负载 + 2 crc
    });

    test('空负载帧', () {
      final frame =
          PacketCodec.encode(Packet(cmd: 0x01, seq: 0, payload: _bytes([])));
      expect(frame.length, 8); // 6 + 0 + 2
      expect(frame[4], 0x00);
      expect(frame[5], 0x00);
    });
  });

  group('PacketAssembler 组包', () {
    final packet =
        Packet(cmd: 0x20, seq: 0x05, payload: _bytes([1, 2, 3, 4]));

    test('单帧完整到达', () {
      final events = PacketAssembler().feed(PacketCodec.encode(packet));
      expect(events, [PacketReceived(packet)]);
    });

    test('半包：一帧被拆成两块分别到达', () {
      final frame = PacketCodec.encode(packet);
      final asm = PacketAssembler();
      final e1 = asm.feed(frame.sublist(0, 4)); // 不足一帧
      expect(e1, isEmpty);
      final e2 = asm.feed(frame.sublist(4)); // 补齐
      expect(e2, [PacketReceived(packet)]);
    });

    test('粘包：两帧在同一块里', () {
      final p2 = Packet(cmd: 0x21, seq: 0x06, payload: _bytes([9]));
      final glued = Uint8List.fromList(
          [...PacketCodec.encode(packet), ...PacketCodec.encode(p2)]);
      final events = PacketAssembler().feed(glued);
      expect(events, [PacketReceived(packet), PacketReceived(p2)]);
    });

    test('帧头前的垃圾字节被跳过', () {
      final frame = PacketCodec.encode(packet);
      final dirty = Uint8List.fromList([0x00, 0xFF, 0x12, ...frame]);
      final events = PacketAssembler().feed(dirty);
      expect(events, [PacketReceived(packet)]);
    });

    test('逐字节喂入也能组出完整帧', () {
      final frame = PacketCodec.encode(packet);
      final asm = PacketAssembler();
      final events = <PacketEvent>[];
      for (final b in frame) {
        events.addAll(asm.feed([b]));
      }
      expect(events, [PacketReceived(packet)]);
    });

    test('CRC 错帧被报错并重同步，后续好帧仍可解出', () {
      final bad = PacketCodec.encode(packet);
      bad[bad.length - 1] ^= 0xFF; // 破坏 CRC 高字节
      final good = PacketCodec.encode(
          Packet(cmd: 0x22, seq: 0x07, payload: _bytes([7, 7])));
      final events =
          PacketAssembler().feed(Uint8List.fromList([...bad, ...good]));
      expect(events.first, const PacketErrorEvent(PacketError.crcMismatch));
      expect(events.last, PacketReceived(
          Packet(cmd: 0x22, seq: 0x07, payload: _bytes([7, 7]))));
    });

    test('超长 len 字段被判坏帧，不撑爆内存', () {
      // 手工构造 len = 0xFFFF 的伪帧头
      final asm = PacketAssembler();
      final events =
          asm.feed(_bytes([0xA5, 0x5A, 0x01, 0x00, 0xFF, 0xFF, 0x00]));
      expect(events, [const PacketErrorEvent(PacketError.payloadTooLong)]);
    });
  });

  group('chunks 分包（按 MTU）', () {
    test('按负载上限切块', () {
      final data = _bytes(List.generate(50, (i) => i));
      final parts = PacketCodec.chunks(data, 20);
      expect(parts.map((p) => p.length), [20, 20, 10]);
      // 拼回来应完全一致
      final rejoined = parts.expand((p) => p).toList();
      expect(rejoined, data);
    });

    test('空数据或非法 MTU 返回空', () {
      expect(PacketCodec.chunks(_bytes([]), 20), isEmpty);
      expect(PacketCodec.chunks(_bytes([1, 2]), 0), isEmpty);
    });
  });
}
