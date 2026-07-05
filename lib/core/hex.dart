// 字节与十六进制文本互转（第 4 课）。
// 纯函数、不依赖蓝牙，便于单元测试——所有协议层字节处理都遵循这个原则。
import 'dart:convert';
import 'dart:typed_data';

/// 宽容解析十六进制输入：接受 "48 65 6C"、"48656C"、"0x48,0x65" 等写法。
/// 非法输入返回 null（奇数长度、含非法字符）。
Uint8List? tryParseHex(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'0x', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s,:-]'), '');
  if (cleaned.isEmpty || cleaned.length.isOdd) return null;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) return null;
  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// [72, 105] → "48 69"
String toHexString(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// 尝试按 UTF-8 解码为可打印文本；含控制字符或解码失败返回 null。
/// 用于值展示的「hex + 文本」双显示，纯二进制数据只显示 hex。
String? tryDecodeUtf8(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    final text = utf8.decode(bytes);
    final printable = text.runes.every((r) => r >= 0x20 || r == 0x0A);
    return printable ? text : null;
  } on FormatException {
    return null;
  }
}
