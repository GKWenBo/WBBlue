//
//  PacketCodecTests.swift
//  WBBlueSwiftTests
//
//  私有二进制协议单元测试:CRC16、帧编码、流式组包(半包/粘包/坏帧重同步)、分包。
//

import Foundation
import Testing
@testable import WBBlueSwift

struct PacketCodecTests {

    // MARK: - CRC16

    @Test("CRC-16/CCITT-FALSE 标准校验向量:'123456789' -> 0x29B1")
    func crcKnownVector() {
        let data = Data("123456789".utf8)
        #expect(PacketCodec.crc16(data) == 0x29B1)
    }

    // MARK: - 编码

    @Test("帧结构:A5 5A | cmd | seq | len(LE) | payload | crc(LE)")
    func encodeLayout() {
        let packet = Packet(cmd: 0x01, seq: 0x02, payload: Data([0xAA, 0xBB]))
        let frame = PacketCodec.encode(packet)

        #expect(frame.count == 6 + 2 + 2)
        #expect(Array(frame.prefix(2)) == [0xA5, 0x5A])
        #expect(frame[2] == 0x01)
        #expect(frame[3] == 0x02)
        #expect(frame[4] == 0x02 && frame[5] == 0x00)  // len = 2, 小端
        #expect(Array(frame[6...7]) == [0xAA, 0xBB])

        let crc = PacketCodec.crc16(frame[2...7])
        #expect(frame[8] == UInt8(crc & 0xFF))
        #expect(frame[9] == UInt8(crc >> 8))
    }

    @Test("空负载帧")
    func encodeEmptyPayload() {
        let frame = PacketCodec.encode(Packet(cmd: 0x10, seq: 0, payload: Data()))
        #expect(frame.count == 8)
    }

    // MARK: - 组包

    @Test("整帧一次喂入 -> 一个 packet 事件")
    func assembleWhole() {
        let packet = Packet(cmd: 0x01, seq: 1, payload: Data([0x01, 0x02, 0x03]))
        var assembler = PacketAssembler()
        let events = assembler.feed(PacketCodec.encode(packet))
        #expect(events == [.packet(packet)])
    }

    @Test("半包:帧跨两个 chunk 到达")
    func assembleSplit() {
        let packet = Packet(cmd: 0x02, seq: 5, payload: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let frame = PacketCodec.encode(packet)
        var assembler = PacketAssembler()
        #expect(assembler.feed(frame.prefix(5)) == [])
        #expect(assembler.feed(frame.suffix(from: 5)) == [.packet(packet)])
    }

    @Test("粘包:两帧在同一个 chunk")
    func assembleCoalesced() {
        let a = Packet(cmd: 0x01, seq: 1, payload: Data([0x11]))
        let b = Packet(cmd: 0x01, seq: 2, payload: Data([0x22]))
        var assembler = PacketAssembler()
        let events = assembler.feed(PacketCodec.encode(a) + PacketCodec.encode(b))
        #expect(events == [.packet(a), .packet(b)])
    }

    @Test("CRC 错帧:上报 crcMismatch 并复位,后续好帧不受影响")
    func assembleBadCRC() {
        let good = Packet(cmd: 0x03, seq: 9, payload: Data([0x01]))
        var bad = PacketCodec.encode(good)
        bad[bad.count - 1] ^= 0xFF  // 破坏 CRC
        var assembler = PacketAssembler()
        let events = assembler.feed(bad + PacketCodec.encode(good))
        #expect(events == [.error(.crcMismatch), .packet(good)])
    }

    @Test("垃圾前缀:逐字节重同步后仍能解出帧")
    func assembleGarbagePrefix() {
        let packet = Packet(cmd: 0x04, seq: 3, payload: Data([0x55]))
        var assembler = PacketAssembler()
        let events = assembler.feed(Data([0x00, 0xA5, 0x01]) + PacketCodec.encode(packet))
        let packets: [Packet] = events.compactMap {
            guard case let .packet(p) = $0 else { return nil }
            return p
        }
        #expect(packets == [packet])
    }

    @Test("超长 len 字段:上报 payloadTooLong 并重同步")
    func assembleOversized() {
        // 手工构造 len = 0xFFFF 的帧头
        let evil = Data([0xA5, 0x5A, 0x01, 0x00, 0xFF, 0xFF])
        let good = Packet(cmd: 0x05, seq: 1, payload: Data())
        var assembler = PacketAssembler()
        let events = assembler.feed(evil + PacketCodec.encode(good))
        #expect(events.first == .error(.payloadTooLong))
        #expect(events.contains(.packet(good)))
    }

    // MARK: - 分包

    @Test("按 MTU 负载上限分包,末块为余量")
    func chunking() {
        let data = Data((0..<50).map { UInt8($0) })
        let chunks = PacketCodec.chunks(of: data, mtuPayload: 20)
        #expect(chunks.count == 3)
        #expect(chunks[0].count == 20 && chunks[1].count == 20 && chunks[2].count == 10)
        #expect(chunks.reduce(Data(), +) == data)
    }

    @Test("空数据分包为空数组")
    func chunkingEmpty() {
        #expect(PacketCodec.chunks(of: Data(), mtuPayload: 20).isEmpty)
    }
}
