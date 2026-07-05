//
//  HeartRateParserTests.swift
//  WBBlueSwiftTests
//
//  标准心率测量特征(0x2A37)解析单元测试。
//  报文格式见蓝牙 SIG《Heart Rate Service 1.0》。
//

import Foundation
import Testing
@testable import WBBlueSwift

struct HeartRateParserTests {

    @Test("uint8 心率:flags=0x00")
    func uint8Format() throws {
        let m = try #require(HeartRateParser.parse(Data([0x00, 72])))
        #expect(m.bpm == 72)
        #expect(m.sensorContact == .notSupported)
        #expect(m.energyExpended == nil)
        #expect(m.rrIntervals.isEmpty)
    }

    @Test("uint16 心率:flags bit0=1,小端")
    func uint16Format() throws {
        let m = try #require(HeartRateParser.parse(Data([0x01, 0x2C, 0x01])))
        #expect(m.bpm == 300)
    }

    @Test("传感器接触状态:bit1-2")
    func sensorContact() throws {
        // 0b110 = 支持且已接触
        let contact = try #require(HeartRateParser.parse(Data([0x06, 60])))
        #expect(contact.sensorContact == .contactDetected)
        // 0b100 = 支持但未接触
        let noContact = try #require(HeartRateParser.parse(Data([0x04, 60])))
        #expect(noContact.sensorContact == .noContact)
    }

    @Test("能耗字段:bit3,uint16 小端,单位 kJ")
    func energyExpended() throws {
        let m = try #require(HeartRateParser.parse(Data([0x08, 80, 0x10, 0x27])))
        #expect(m.energyExpended == 10000)
    }

    @Test("RR 间期:bit4,单位 1/1024 秒,可多个")
    func rrIntervals() throws {
        // 1024/1024=1.0s,512/1024=0.5s
        let m = try #require(HeartRateParser.parse(Data([0x10, 65, 0x00, 0x04, 0x00, 0x02])))
        #expect(m.rrIntervals == [1.0, 0.5])
    }

    @Test("全字段组合:uint16 + 接触 + 能耗 + RR")
    func allFields() throws {
        let data = Data([0x1F, 0x50, 0x00, 0xE8, 0x03, 0x00, 0x04])
        let m = try #require(HeartRateParser.parse(data))
        #expect(m.bpm == 80)
        #expect(m.sensorContact == .contactDetected)
        #expect(m.energyExpended == 1000)
        #expect(m.rrIntervals == [1.0])
    }

    @Test("空数据与截断数据返回 nil")
    func malformed() {
        #expect(HeartRateParser.parse(Data()) == nil)
        #expect(HeartRateParser.parse(Data([0x01, 0x2C])) == nil)  // uint16 却只有 1 字节值
        #expect(HeartRateParser.parse(Data([0x08, 80, 0x10])) == nil)  // 能耗字段截断
    }
}
