//
//  BLECentralModels.swift
//  WBBlueSwift
//
//  Central 抽象层的数据模型:与 CoreBluetooth 类型解耦,
//  让 Mock 实现与 UI 层都不必直接依赖 CBPeripheral 等硬件绑定类型。
//

import CoreBluetooth
import Foundation

/// 蓝牙中心设备状态(对 CBManagerState 的语义化映射)。
enum CentralState: String {
    case unknown = "未知"
    case resetting = "重置中"
    case unsupported = "不支持"
    case unauthorized = "未授权"
    case poweredOff = "已关闭"
    case poweredOn = "已开启"

    /// 非 poweredOn 状态对应的错误,用于 API 调用前置检查。
    var asError: BLEError? {
        switch self {
        case .poweredOn: nil
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        case .resetting: .resetting
        case .unknown: .resetting
        }
    }
}

/// 一次扫描发现(同一设备重复发现时以 id 去重、刷新 RSSI 与 lastSeen)。
struct DiscoveredDevice: Identifiable, Hashable {
    /// iOS 的设备标识:本机生成的会话级 UUID,不是 MAC 地址;
    /// 换手机、设备换随机地址(RPA)后都可能变化,企业侧持久绑定要靠厂商数据/序列号。
    let id: UUID
    let name: String?
    let rssi: Int
    let advertisedServices: [CBUUID]
    let manufacturerData: Data?
    let isConnectable: Bool
    let lastSeen: Date

    var displayName: String {
        name?.isEmpty == false ? name! : "未知设备"
    }
}

/// 连接生命周期事件流的元素。
enum ConnectionEvent {
    case connected
    /// error == nil 表示 App 主动断开;非 nil 为意外断连(超距、设备关机、链路超时)
    case disconnected(error: Error?)
}

/// 发现结果的特征快照(值与 isNotifying 为发现/最近读取时刻的快照)。
struct GATTCharacteristic: Identifiable {
    let uuid: CBUUID
    let properties: CBCharacteristicProperties
    let isNotifying: Bool
    let value: Data?

    var id: String { uuid.uuidString }

    /// 属性徽标,如 ["读", "写", "通知"]。
    var propertyBadges: [String] {
        var badges: [String] = []
        if properties.contains(.read) { badges.append("读") }
        if properties.contains(.write) { badges.append("写") }
        if properties.contains(.writeWithoutResponse) { badges.append("免响应写") }
        if properties.contains(.notify) { badges.append("通知") }
        if properties.contains(.indicate) { badges.append("指示") }
        if properties.contains(.authenticatedSignedWrites) { badges.append("签名写") }
        return badges
    }
}

struct GATTService: Identifiable {
    let uuid: CBUUID
    let isPrimary: Bool
    let characteristics: [GATTCharacteristic]

    var id: String { uuid.uuidString }
}
