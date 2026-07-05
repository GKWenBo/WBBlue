//
//  BLEError.swift
//  WBBlueSwift
//
//  统一错误模型。企业项目的经验:把 CoreBluetooth 分散在各委托回调里的
//  NSError 收敛为一个带恢复建议的枚举,UI 层只对这一种错误做展示与引导。
//

import CoreBluetooth
import Foundation

enum BLEError: LocalizedError {
    /// 蓝牙开关关闭
    case poweredOff
    /// 用户拒绝了蓝牙权限(设置 > App > 蓝牙)
    case unauthorized
    /// 硬件不支持 BLE(老设备/部分模拟器场景)
    case unsupported
    /// 蓝牙栈正在重置,稍后恢复
    case resetting
    /// 操作超时(连接、读写、发现服务等)
    case timeout(operation: String)
    /// 目标设备不在已发现缓存中(iOS 的 identifier 是本机会话缓存,不是 MAC)
    case deviceNotFound
    /// 尚未连接就发起 GATT 操作
    case notConnected
    /// 连接意外断开;underlying 为系统给出的原因(可能为 nil)
    case disconnected(underlying: Error?)
    case serviceNotFound(CBUUID)
    case characteristicNotFound(CBUUID)
    /// 特征不具备所需属性(如对只读特征发起写)
    case operationNotSupported(String)
    /// ATT 层错误(如 insufficientAuthentication = 需要配对)
    case att(CBATTError.Code)
    /// 其余系统错误原样透传
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .poweredOff: "蓝牙已关闭"
        case .unauthorized: "蓝牙权限被拒绝"
        case .unsupported: "设备不支持低功耗蓝牙"
        case .resetting: "蓝牙正在重置"
        case .timeout(let operation): "\(operation)超时"
        case .deviceNotFound: "未找到目标设备"
        case .notConnected: "设备未连接"
        case .disconnected(let error):
            "连接已断开" + (error.map { ":\($0.localizedDescription)" } ?? "")
        case .serviceNotFound(let uuid): "未发现服务 \(BLEConstants.displayName(for: uuid))"
        case .characteristicNotFound(let uuid): "未发现特征 \(BLEConstants.displayName(for: uuid))"
        case .operationNotSupported(let reason): "操作不支持:\(reason)"
        case .att(let code): "GATT 错误(ATT \(code.rawValue))"
        case .underlying(let error): error.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .poweredOff: "请在控制中心或设置中打开蓝牙。"
        case .unauthorized: "请到 设置 > 隐私与安全性 > 蓝牙 中允许本 App 使用蓝牙。"
        case .unsupported: "请更换支持 BLE 的设备。"
        case .resetting: "系统蓝牙栈重置中,稍候会自动恢复,无需操作。"
        case .timeout: "确认设备在范围内且未被其他手机连接,然后重试。"
        case .deviceNotFound: "重新扫描以刷新设备缓存。"
        case .notConnected: "先连接设备再执行该操作。"
        case .disconnected: "已启用自动重连的会话会按指数退避自动恢复。"
        case .att(let code) where code == .insufficientAuthentication:
            "该特征要求加密链路:系统将弹出配对请求,接受配对后重试。"
        default: nil
        }
    }

    /// 把 CoreBluetooth 回调中的 NSError 归一化为 BLEError。
    static func wrap(_ error: Error) -> BLEError {
        if let bleError = error as? BLEError { return bleError }
        if let attError = error as? CBATTError, let code = CBATTError.Code(rawValue: attError.errorCode) {
            return .att(code)
        }
        return .underlying(error)
    }
}
