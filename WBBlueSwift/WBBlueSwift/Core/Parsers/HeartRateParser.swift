//
//  HeartRateParser.swift
//  WBBlueSwift
//
//  标准心率测量特征(0x2A37)解析,格式见蓝牙 SIG《Heart Rate Service 1.0》:
//
//  flags(1B):
//    bit0    心率值格式:0=uint8,1=uint16(小端)
//    bit1-2  传感器接触:0x/1x 组合,见 SensorContact
//    bit3    能耗字段存在(uint16 小端,单位 kJ)
//    bit4    RR 间期存在(每个 uint16 小端,单位 1/1024 秒,可多个)
//
//  解析为纯函数,截断/空数据返回 nil,便于单元测试与上层容错。
//

import Foundation

struct HeartRateMeasurement: Equatable {
    enum SensorContact: Equatable {
        /// 设备不支持接触检测(flags bit2 = 0)
        case notSupported
        /// 支持但未检测到接触
        case noContact
        /// 支持且已接触
        case contactDetected
    }

    let bpm: Int
    let sensorContact: SensorContact
    /// 累计能耗,单位 kJ;设备未上报时为 nil
    let energyExpended: Int?
    /// RR 间期序列,单位秒
    let rrIntervals: [Double]
}

enum HeartRateParser {

    static func parse(_ data: Data) -> HeartRateMeasurement? {
        // Data 的下标继承自原始缓冲区偏移,先归零以便按绝对位置访问。
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        let flags = bytes[0]
        var offset = 1

        let bpm: Int
        if flags & 0x01 != 0 {
            guard bytes.count >= offset + 2 else { return nil }
            bpm = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2
        } else {
            bpm = Int(bytes[offset])
            offset += 1
        }

        let sensorContact: HeartRateMeasurement.SensorContact
        switch (flags >> 1) & 0b11 {
        case 0b10: sensorContact = .noContact
        case 0b11: sensorContact = .contactDetected
        default: sensorContact = .notSupported
        }

        var energyExpended: Int?
        if flags & 0x08 != 0 {
            guard bytes.count >= offset + 2 else { return nil }
            energyExpended = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            offset += 2
        }

        var rrIntervals: [Double] = []
        if flags & 0x10 != 0 {
            while offset + 2 <= bytes.count {
                let raw = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                rrIntervals.append(Double(raw) / 1024.0)
                offset += 2
            }
        }

        return HeartRateMeasurement(
            bpm: bpm,
            sensorContact: sensorContact,
            energyExpended: energyExpended,
            rrIntervals: rrIntervals
        )
    }
}
