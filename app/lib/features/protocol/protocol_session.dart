import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/hex.dart';
import '../../core/protocol/packet.dart';

/// 一条协议控制台记录（发送 / 收到 / 错误 / 提示）。
class ProtocolLogEntry {
  ProtocolLogEntry(this.kind, this.text) : time = DateTime.now();

  final ProtocolLogKind kind;
  final String text;
  final DateTime time;
}

enum ProtocolLogKind { tx, rx, error, info }

/// 私有协议会话（第 6 课）：把「一条写特征 + 一条通知特征」封装成帧收发通道。
///
/// - 发送：Packet → encode → 按 MTU 分包 → 逐块写入；
/// - 接收：notify 字节流 → 持续 feed 进 PacketAssembler → 解出完整帧或错误。
///
/// 组包状态机 [_assembler] 跨多次通知累积，正确处理半包/粘包/坏帧——
/// 这是「字节管道」之上重建「消息边界」的核心，纯逻辑部分已在 packet_test 覆盖。
class ProtocolSession extends ChangeNotifier {
  ProtocolSession({
    required this.device,
    required this.writeChar,
    required this.notifyChar,
  });

  final BluetoothDevice device;
  final BluetoothCharacteristic writeChar;
  final BluetoothCharacteristic notifyChar;

  final List<ProtocolLogEntry> log = [];
  final PacketAssembler _assembler = PacketAssembler();
  StreamSubscription<List<int>>? _sub;
  int _seq = 0;
  bool _started = false;

  /// 开始接收：订阅通知特征并把字节喂给组包器。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _sub = notifyChar.onValueReceived.listen(_onBytes);
      device.cancelWhenDisconnected(_sub!);
      if (!notifyChar.isNotifying) {
        await notifyChar.setNotifyValue(true);
      }
      _add(ProtocolLogKind.info, '已订阅 ${notifyChar.uuid.str} 等待上报');
    } catch (e) {
      _add(ProtocolLogKind.error, '订阅失败：$e');
    }
  }

  void _onBytes(List<int> bytes) {
    _add(ProtocolLogKind.info, '↓ 原始 ${toHexString(bytes)}');
    for (final event in _assembler.feed(bytes)) {
      switch (event) {
        case PacketReceived(:final packet):
          _add(
            ProtocolLogKind.rx,
            '帧 cmd=0x${packet.cmd.toRadixString(16).padLeft(2, '0')} '
            'seq=${packet.seq} '
            'payload=${toHexString(packet.payload)}',
          );
        case PacketErrorEvent(:final error):
          _add(ProtocolLogKind.error, '坏帧：${error.name}（已重同步）');
      }
    }
  }

  /// 发送一帧：自动分配递增 seq，按写特征的 MTU 上限分包。
  Future<void> send(int cmd, Uint8List payload) async {
    final packet = Packet(cmd: cmd, seq: _nextSeq(), payload: payload);
    final frame = PacketCodec.encode(packet);
    // 单帧写负载上限 = ATT_MTU - 3；免响写 vs 有响写取各自上限
    final withResponse = writeChar.properties.write;
    final mtuPayload = _maxWriteLength(withResponse);
    final parts = PacketCodec.chunks(frame, mtuPayload);
    _add(
      ProtocolLogKind.tx,
      '↑ 帧 cmd=0x${cmd.toRadixString(16).padLeft(2, '0')} '
      'seq=${packet.seq} 共 ${frame.length}B / ${parts.length} 包',
    );
    try {
      for (final part in parts) {
        await writeChar.write(part, withoutResponse: !withResponse);
      }
    } catch (e) {
      _add(ProtocolLogKind.error, '写入失败：$e');
    }
  }

  int _nextSeq() {
    final s = _seq;
    _seq = (_seq + 1) & 0xFF; // 单字节循环
    return s;
  }

  /// 连接态单帧最大写负载。FBP 暴露 device.mtuNow（ATT_MTU），减 3 得 ATT 负载。
  int _maxWriteLength(bool withResponse) {
    final mtu = device.mtuNow;
    final payload = mtu - 3;
    return payload > 0 ? payload : 20; // 兜底默认 MTU 23 → 负载 20
  }

  void _add(ProtocolLogKind kind, String text) {
    log.insert(0, ProtocolLogEntry(kind, text));
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }

  void clear() {
    log.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
