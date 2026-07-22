// 企业私有二进制协议层（第 6 课）。
//
// BLE 特征本质是「字节管道」，半包/粘包是常态：通知按 MTU 切割到达、
// 外设固件缓冲会合并多帧一起发。所以应用层必须自带帧同步机制。
//
// 帧结构（多字节字段一律小端）：
//   ┌──────┬──────┬─────┬─────┬────────┬─────────┬────────┐
//   │ 0xA5 │ 0x5A │ cmd │ seq │ len(2) │ payload │ crc(2) │
//   └──────┴──────┴─────┴─────┴────────┴─────────┴────────┘
//   crc = CRC-16/CCITT-FALSE，覆盖 cmd..payload。
//
// seq 用于请求/响应配对与丢包检测；len 上限防御损坏帧撑爆内存。
// 纯 Dart、不碰蓝牙 API——协议层可完全脱离硬件做单元测试。
import 'dart:typed_data';

/// 一帧业务数据。
class Packet {
  const Packet({required this.cmd, required this.seq, required this.payload});

  final int cmd;
  final int seq;
  final Uint8List payload;

  @override
  bool operator ==(Object other) =>
      other is Packet &&
      other.cmd == cmd &&
      other.seq == seq &&
      _bytesEqual(other.payload, payload);

  @override
  int get hashCode => Object.hash(cmd, seq, Object.hashAll(payload));

  @override
  String toString() =>
      'Packet(cmd: 0x${cmd.toRadixString(16)}, seq: $seq, '
      'payload: ${payload.length}B)';
}

/// 协议层错误。
enum PacketError {
  /// CRC 校验失败：链路误码，或帧边界判断错误
  crcMismatch,

  /// len 字段超过 [PacketCodec.maxPayloadLength]
  payloadTooLong,
}

/// 帧编解码 + 分包（纯静态工具）。
abstract final class PacketCodec {
  static const List<int> header = [0xA5, 0x5A];

  /// 单帧负载上限；超过按坏帧丢弃，防止损坏的 len 字段导致无限等待或内存暴涨。
  static const int maxPayloadLength = 512;

  /// CRC-16/CCITT-FALSE（poly 0x1021, init 0xFFFF），覆盖入参全部字节。
  static int crc16(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= (byte << 8) & 0xFFFF;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  /// 编码为完整帧字节。
  static Uint8List encode(Packet packet) {
    final len = packet.payload.length;
    // body = cmd + seq + len(2) + payload，CRC 覆盖 body
    final body = BytesBuilder()
      ..addByte(packet.cmd)
      ..addByte(packet.seq)
      ..addByte(len & 0xFF)
      ..addByte((len >> 8) & 0xFF)
      ..add(packet.payload);
    final bodyBytes = body.toBytes();

    final crc = crc16(bodyBytes);
    return (BytesBuilder()
          ..add(header)
          ..add(bodyBytes)
          ..addByte(crc & 0xFF)
          ..addByte((crc >> 8) & 0xFF))
        .toBytes();
  }

  /// 把任意长度数据按写入负载上限切块。
  /// [mtuPayload] 来自协商后的 MTU（ATT_MTU - 3），是分包依据。
  static List<Uint8List> chunks(Uint8List data, int mtuPayload) {
    if (data.isEmpty || mtuPayload <= 0) return const [];
    final result = <Uint8List>[];
    for (var start = 0; start < data.length; start += mtuPayload) {
      final end = (start + mtuPayload < data.length)
          ? start + mtuPayload
          : data.length;
      result.add(Uint8List.sublistView(data, start, end));
    }
    return result;
  }
}

/// 组包事件：一个完整帧，或一个协议错误。
sealed class PacketEvent {
  const PacketEvent();
}

class PacketReceived extends PacketEvent {
  const PacketReceived(this.packet);
  final Packet packet;

  @override
  bool operator ==(Object other) =>
      other is PacketReceived && other.packet == packet;

  @override
  int get hashCode => packet.hashCode;
}

class PacketErrorEvent extends PacketEvent {
  const PacketErrorEvent(this.error);
  final PacketError error;

  @override
  bool operator ==(Object other) =>
      other is PacketErrorEvent && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// 流式组包状态机。持续 [feed] 到达的字节块，吐出完整帧或错误事件。
///
/// 坏帧（CRC 错 / 超长）会被丢弃，并从帧头之后逐字节重新同步——
/// 保证一个坏帧不拖垮整条流。这是半包、粘包、坏帧三种情况的统一处理器。
class PacketAssembler {
  final BytesBuilder _builder = BytesBuilder();
  Uint8List _buffer = Uint8List(0);

  /// 固定头长度：header(2) + cmd(1) + seq(1) + len(2)
  static const int _minHeader = 6;

  List<PacketEvent> feed(List<int> chunk) {
    // 把新块并入缓冲区
    _builder.add(_buffer);
    _builder.add(chunk);
    _buffer = _builder.takeBytes();

    final events = <PacketEvent>[];
    while (true) {
      // 1. 找帧头，丢弃头之前的垃圾字节
      final headerIndex = _indexOfHeader(_buffer);
      if (headerIndex < 0) {
        // 没找到完整帧头：保留末字节（可能是被截断的 0xA5）
        if (_buffer.length > 1) {
          _buffer = Uint8List.sublistView(_buffer, _buffer.length - 1);
        }
        return events;
      }
      if (headerIndex > 0) {
        _buffer = Uint8List.sublistView(_buffer, headerIndex);
      }

      // 2. 至少要有固定头 6 字节才能读出 len
      if (_buffer.length < _minHeader) return events;
      final len = _buffer[4] | (_buffer[5] << 8);

      if (len > PacketCodec.maxPayloadLength) {
        events.add(const PacketErrorEvent(PacketError.payloadTooLong));
        _dropHeaderAndResync();
        continue;
      }

      // 3. 等待整帧到齐
      final frameLength = _minHeader + len + 2;
      if (_buffer.length < frameLength) return events;

      // 4. CRC 校验（覆盖 cmd..payload，即 body）
      final body = Uint8List.sublistView(_buffer, 2, _minHeader + len);
      final expected = PacketCodec.crc16(body);
      final received =
          _buffer[frameLength - 2] | (_buffer[frameLength - 1] << 8);
      if (expected != received) {
        events.add(const PacketErrorEvent(PacketError.crcMismatch));
        _dropHeaderAndResync();
        continue;
      }

      events.add(PacketReceived(Packet(
        cmd: _buffer[2],
        seq: _buffer[3],
        payload: Uint8List.fromList(
            Uint8List.sublistView(_buffer, _minHeader, _minHeader + len)),
      )));
      _buffer = Uint8List.sublistView(_buffer, frameLength);
    }
  }

  /// 丢掉当前帧头两字节，从其后逐字节重新找同步点。
  void _dropHeaderAndResync() {
    _buffer = Uint8List.sublistView(_buffer, 2);
  }

  /// 返回 header 在 buffer 中的起始下标，找不到返回 -1。
  static int _indexOfHeader(Uint8List buffer) {
    for (var i = 0; i + 1 < buffer.length; i++) {
      if (buffer[i] == PacketCodec.header[0] &&
          buffer[i + 1] == PacketCodec.header[1]) {
        return i;
      }
    }
    return -1;
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
