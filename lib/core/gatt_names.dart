// 常见标准 UUID 的人话名（第 4 课）。
// 完整表见蓝牙 SIG「Assigned Numbers」文档；私有 128-bit UUID 无名可查，
// 语义只存在于厂商协议文档里——这就是 GATT「只定容器不定语义」的体现。
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const Map<String, String> _serviceNames = {
  '1800': '通用访问 (GAP)',
  '1801': '通用属性 (GATT)',
  '180A': '设备信息',
  '180D': '心率',
  '180F': '电池',
  '181A': '环境感知',
  'FE59': 'Nordic DFU',
};

const Map<String, String> _characteristicNames = {
  '2A00': '设备名称',
  '2A05': '服务变更',
  '2A19': '电池电量',
  '2A29': '厂商名称',
  '2A37': '心率测量',
  '2A38': '传感器位置',
};

/// 128-bit 标准 UUID（0000xxxx-0000-1000-8000-00805F9B34FB）取短形式，
/// 私有 UUID 原样返回。
String shortUuid(Guid g) {
  final s = g.str.toUpperCase();
  if (s.length == 36 &&
      s.startsWith('0000') &&
      s.contains('-0000-1000-8000-00805F9B34FB')) {
    return s.substring(4, 8);
  }
  return s;
}

String serviceDisplayName(Guid g) {
  final short = shortUuid(g);
  final known = _serviceNames[short];
  return known == null ? '服务 $short' : '$known ($short)';
}

String characteristicDisplayName(Guid g) {
  final short = shortUuid(g);
  final known = _characteristicNames[short];
  return known == null ? '特征 $short' : '$known ($short)';
}
