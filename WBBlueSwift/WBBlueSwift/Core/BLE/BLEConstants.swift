//
//  BLEConstants.swift
//  WBBlueSwift
//
//  标准 GATT 服务/特征 UUID 与人类可读短名。
//  16 位短 UUID 是 SIG 分配的公有编号(基于基础 UUID 0000xxxx-0000-1000-8000-00805F9B34FB);
//  128 位随机 UUID 则是厂商私有服务的惯例。
//

import CoreBluetooth

enum BLEConstants {

    // MARK: - 标准服务/特征(SIG 公有)

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let bodySensorLocation = CBUUID(string: "2A38")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInformationService = CBUUID(string: "180A")
    static let manufacturerName = CBUUID(string: "2A29")
    static let clientConfigDescriptor = CBUUID(string: "2902")  // CCCD

    // MARK: - 本项目私有服务(演示企业自定义协议)

    static let customService = CBUUID(string: "FFF0")
    /// 私有协议数据通道:Write + Notify(命令下行、响应上行走同一特征)
    static let customData = CBUUID(string: "FFF1")
    /// 设备信息:只读
    static let customInfo = CBUUID(string: "FFF2")

    // MARK: - 短名表

    private static let shortNames: [String: String] = [
        "180D": "心率服务",
        "2A37": "心率测量",
        "2A38": "传感器位置",
        "180F": "电池服务",
        "2A19": "电池电量",
        "180A": "设备信息",
        "2A29": "厂商名称",
        "2902": "CCCD(通知开关)",
        "1800": "通用访问 GAP",
        "1801": "通用属性 GATT",
        "FFF0": "WB 私有服务",
        "FFF1": "WB 数据通道",
        "FFF2": "WB 设备信息",
    ]

    static func name(for uuid: CBUUID) -> String? {
        shortNames[uuid.uuidString]
    }

    /// 有短名给"短名 (UUID)",否则原样返回 UUID。
    static func displayName(for uuid: CBUUID) -> String {
        if let name = name(for: uuid) {
            return "\(name) (\(uuid.uuidString))"
        }
        return uuid.uuidString
    }
}
