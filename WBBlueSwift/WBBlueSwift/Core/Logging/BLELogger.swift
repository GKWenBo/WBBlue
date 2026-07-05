//
//  BLELogger.swift
//  WBBlueSwift
//
//  双通道日志:os.Logger(可在 Console.app / Instruments 过滤 subsystem)
//  + 内存环形缓冲(App 内日志页展示,现场排障不用连电脑)。
//  蓝牙问题强依赖时序,完整日志是企业项目定位断连/丢包问题的第一手段。
//

import Foundation
import os

@Observable
final class BLELogger {

    enum Level: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String
    }

    static let shared = BLELogger()

    /// 环形缓冲上限,超出丢最旧。
    private let capacity = 500
    private let osLogger = Logger(subsystem: "com.wb.WBBlueSwift", category: "BLE")

    private(set) var entries: [Entry] = []

    func log(_ level: Level = .info, category: String, _ message: String) {
        entries.append(Entry(date: .now, level: level, category: category, message: message))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        switch level {
        case .debug: osLogger.debug("[\(category)] \(message)")
        case .info: osLogger.info("[\(category)] \(message)")
        case .warning: osLogger.warning("[\(category)] \(message)")
        case .error: osLogger.error("[\(category)] \(message)")
        }
    }

    func clear() {
        entries.removeAll()
    }
}
