import 'package:flutter_test/flutter_test.dart';

import 'package:wb_ble_app/core/hex.dart';

void main() {
  group('tryParseHex 宽容解析', () {
    test('空格分隔', () {
      expect(tryParseHex('48 69'), [0x48, 0x69]);
    });

    test('连续写法与大小写混合', () {
      expect(tryParseHex('4869aB'), [0x48, 0x69, 0xAB]);
    });

    test('0x 前缀与逗号分隔', () {
      expect(tryParseHex('0x48,0x69'), [0x48, 0x69]);
    });

    test('奇数长度非法', () {
      expect(tryParseHex('486'), isNull);
    });

    test('非法字符', () {
      expect(tryParseHex('48 GG'), isNull);
    });

    test('空输入非法', () {
      expect(tryParseHex('  '), isNull);
    });
  });

  group('toHexString', () {
    test('大写补零空格分隔', () {
      expect(toHexString([0x01, 0xAB, 0x00]), '01 AB 00');
    });
  });

  group('tryDecodeUtf8', () {
    test('可打印文本', () {
      expect(tryDecodeUtf8([0x48, 0x69]), 'Hi');
    });

    test('含控制字符返回 null（纯二进制只显示 hex）', () {
      expect(tryDecodeUtf8([0x01, 0x02]), isNull);
    });

    test('非法 UTF-8 返回 null', () {
      expect(tryDecodeUtf8([0xFF, 0xFE]), isNull);
    });
  });
}
