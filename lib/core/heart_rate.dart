// 心率测量特征（0x2A37）解析（第 5 课）。
// 依据蓝牙 SIG GATT Specification Supplement：
//   字节 0 = flags（bit0 决定心率是 uint8 还是 uint16 小端，
//   bit3 含能量消耗 uint16，bit4 含 RR 间期 uint16×N）。
// 纯函数、不碰蓝牙 API——协议解析的纪律，第 6 课私有协议沿用。

/// 解析心率值（BPM）。数据不完整或为空返回 null。
int? parseHeartRate(List<int> data) {
  if (data.isEmpty) return null;
  final flags = data[0];
  final is16bit = (flags & 0x01) != 0;
  if (is16bit) {
    if (data.length < 3) return null;
    // 小端：低字节在前
    return data[1] | (data[2] << 8);
  }
  if (data.length < 2) return null;
  return data[1];
}

/// 解析 RR 间期（毫秒）。flags bit4 置位时才存在，可多个，
/// 原始单位 1/1024 秒。没有则返回空列表。
List<double> parseRrIntervalsMs(List<int> data) {
  if (data.isEmpty) return const [];
  final flags = data[0];
  if ((flags & 0x10) == 0) return const [];
  // 跳过 flags、心率值（1 或 2 字节）、可选的能量消耗（2 字节）
  var offset = 1 + (((flags & 0x01) != 0) ? 2 : 1);
  if ((flags & 0x08) != 0) offset += 2;
  final result = <double>[];
  while (offset + 1 < data.length) {
    final raw = data[offset] | (data[offset + 1] << 8);
    result.add(raw * 1000 / 1024);
    offset += 2;
  }
  return result;
}
