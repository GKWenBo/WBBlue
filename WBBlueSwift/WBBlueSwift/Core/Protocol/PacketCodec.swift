//
//  PacketCodec.swift
//  WBBlueSwift
//
//  企业私有二进制协议层。BLE 特征是"字节管道",半包/粘包是常态
//  (通知按 MTU 切割到达、外设固件缓冲合并发送),必须自带帧同步:
//
//  帧结构(所有多字节字段小端):
//    ┌──────┬──────┬─────┬─────┬────────┬─────────┬────────┐
//    │ 0xA5 │ 0x5A │ cmd │ seq │ len(2) │ payload │ crc(2) │
//    └──────┴──────┴─────┴─────┴────────┴─────────┴────────┘
//  crc = CRC-16/CCITT-FALSE,覆盖 cmd..payload。
//
//  seq 用于请求/响应配对与丢包检测;len 上限防御恶意/损坏帧撑爆内存。
//

import Foundation

/// 一帧业务数据。
struct Packet: Equatable {
    let cmd: UInt8
    let seq: UInt8
    let payload: Data
}

enum PacketError: Error, Equatable {
    /// CRC 校验失败(链路误码或帧边界判断错误)
    case crcMismatch
    /// len 字段超过 `PacketCodec.maxPayloadLength`
    case payloadTooLong
}

enum PacketCodec {

    static let header: [UInt8] = [0xA5, 0x5A]
    /// 单帧负载上限;超过按坏帧丢弃,防止损坏的 len 字段导致无限等待或内存暴涨。
    static let maxPayloadLength = 512

    // MARK: - CRC-16/CCITT-FALSE(poly 0x1021, init 0xFFFF)

    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    // MARK: - 编码

    static func encode(_ packet: Packet) -> Data {
        var body = Data([packet.cmd, packet.seq])
        let len = UInt16(packet.payload.count)
        body.append(UInt8(len & 0xFF))
        body.append(UInt8(len >> 8))
        body.append(packet.payload)

        let crc = crc16(body)
        var frame = Data(header)
        frame.append(body)
        frame.append(UInt8(crc & 0xFF))
        frame.append(UInt8(crc >> 8))
        return frame
    }

    // MARK: - 分包

    /// 把任意长度数据按写入负载上限切块(上限来自协商后的 MTU,
    /// 即 `peripheral.maximumWriteValueLength(for:)`)。
    static func chunks(of data: Data, mtuPayload: Int) -> [Data] {
        guard !data.isEmpty, mtuPayload > 0 else { return [] }
        return stride(from: 0, to: data.count, by: mtuPayload).map { start in
            data.subdata(in: start..<min(start + mtuPayload, data.count))
        }
    }
}

/// 流式组包状态机。持续 `feed` 到达的字节块,吐出完整帧或错误事件。
/// 坏帧(CRC 错/超长)会被丢弃并从帧头之后逐字节重新同步,保证一个坏帧不拖垮整条流。
struct PacketAssembler {

    enum Event: Equatable {
        case packet(Packet)
        case error(PacketError)
    }

    private var buffer = Data()

    mutating func feed(_ chunk: Data) -> [Event] {
        buffer.append(chunk)
        var events: [Event] = []

        while true {
            // 1. 寻找帧头,丢弃头之前的垃圾字节
            guard let headerRange = buffer.firstRange(of: PacketCodec.header) else {
                // 保留末字节:可能是被截断的 0xA5
                if buffer.count > 1 { buffer.removeFirst(buffer.count - 1) }
                return events
            }
            if headerRange.lowerBound > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<headerRange.lowerBound)
            }

            // 2. 至少要有固定头 6 字节才能读出 len
            guard buffer.count >= 6 else { return events }
            let bytes = [UInt8](buffer.prefix(6))
            let len = Int(bytes[4]) | Int(bytes[5]) << 8

            if len > PacketCodec.maxPayloadLength {
                events.append(.error(.payloadTooLong))
                buffer.removeFirst(2)  // 跳过帧头,逐字节重同步
                continue
            }

            // 3. 等待整帧到齐
            let frameLength = 6 + len + 2
            guard buffer.count >= frameLength else { return events }
            let frame = [UInt8](buffer.prefix(frameLength))

            // 4. CRC 校验(覆盖 cmd..payload)
            let expected = PacketCodec.crc16(Data(frame[2..<(6 + len)]))
            let received = UInt16(frame[frameLength - 2]) | UInt16(frame[frameLength - 1]) << 8
            if expected != received {
                events.append(.error(.crcMismatch))
                buffer.removeFirst(2)
                continue
            }

            events.append(.packet(Packet(
                cmd: frame[2],
                seq: frame[3],
                payload: Data(frame[6..<(6 + len)])
            )))
            buffer.removeFirst(frameLength)
        }
    }
}
