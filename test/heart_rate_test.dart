import 'package:flutter_test/flutter_test.dart';

import 'package:wb_ble_app/core/heart_rate.dart';

void main() {
  group('parseHeartRate', () {
    test('uint8 格式（flags bit0 = 0）', () {
      expect(parseHeartRate([0x00, 0x48]), 72);
    });

    test('uint16 小端格式（flags bit0 = 1）', () {
      // 0x0148 = 328，验证低字节在前
      expect(parseHeartRate([0x01, 0x48, 0x01]), 328);
    });

    test('带 RR 间期的真实帧：首字节是 flags 不是心率', () {
      expect(parseHeartRate([0x10, 0x48, 0x34, 0x02]), 72);
    });

    test('空数据与截断数据返回 null', () {
      expect(parseHeartRate([]), isNull);
      expect(parseHeartRate([0x00]), isNull);
      expect(parseHeartRate([0x01, 0x48]), isNull);
    });
  });

  group('parseRrIntervalsMs', () {
    test('flags bit4 未置位时为空', () {
      expect(parseRrIntervalsMs([0x00, 0x48]), isEmpty);
    });

    test('单个 RR 间期：0x0234 = 564 → 550.78ms', () {
      final rr = parseRrIntervalsMs([0x10, 0x48, 0x34, 0x02]);
      expect(rr, hasLength(1));
      expect(rr.first, closeTo(564 * 1000 / 1024, 0.01));
    });

    test('uint16 心率 + 能量消耗字段偏移正确', () {
      // flags 0x19 = bit0(u16) + bit3(能量) + bit4(RR)
      final rr = parseRrIntervalsMs([
        0x19, 0x48, 0x00, // 心率 uint16
        0x10, 0x00, // 能量消耗
        0x00, 0x04, // RR = 0x0400 = 1024 → 1000ms
      ]);
      expect(rr, hasLength(1));
      expect(rr.first, closeTo(1000, 0.01));
    });
  });
}
