//
//  DeviceDetailViewModel.swift
//  WBBlueSwift
//
//  设备详情视图模型:经 ReconnectOrchestrator 保持连接,
//  重连成功后自动重新发现服务并恢复订阅(GATT 句柄与 CCCD 在断连后全部失效)。
//

import CoreBluetooth
import Foundation

@Observable
final class DeviceDetailViewModel {

    let device: DiscoveredDevice
    let orchestrator: ReconnectOrchestrator

    private let central: any BLECentral
    private let logger = BLELogger.shared

    var services: [GATTService] = []
    /// 特征 UUID → 最近一次读到/通知到的值
    var latestValues: [String: Data] = [:]
    /// 当前在 UI 上开着通知的特征
    var notifyingCharacteristics: Set<String> = []
    var rssi: Int?
    var errorMessage: String?

    private var notifyTasks: [String: Task<Void, Never>] = [:]

    var hasHeartRate: Bool {
        services.contains { $0.uuid == BLEConstants.heartRateService }
    }
    var hasCustomProtocol: Bool {
        services.contains { $0.uuid == BLEConstants.customService }
    }

    init(central: any BLECentral, device: DiscoveredDevice) {
        self.central = central
        self.device = device
        self.orchestrator = ReconnectOrchestrator(central: central)
    }

    func start() {
        orchestrator.start(deviceID: device.id) { [weak self] in
            await self?.onConnected()
        }
    }

    /// 每次(重)连成功:重新发现服务 + 恢复订阅。
    private func onConnected() async {
        do {
            services = try await central.discoverServices(id: device.id)
            errorMessage = nil
            let toRestore = notifyingCharacteristics
            for uuid in toRestore {
                await subscribe(CBUUID(string: uuid))
            }
            await refreshRSSI()
        } catch {
            errorMessage = error.localizedDescription
            logger.log(.error, category: "详情", "服务发现失败:\(error.localizedDescription)")
        }
    }

    func teardown() {
        for task in notifyTasks.values { task.cancel() }
        notifyTasks.removeAll()
        orchestrator.stopAndDisconnect(deviceID: device.id)
    }

    // MARK: - GATT 操作

    func read(_ uuid: CBUUID) async {
        do {
            latestValues[uuid.uuidString] = try await central.readValue(id: device.id, characteristic: uuid)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 返回是否写成功(供写入面板反馈)。
    func write(_ uuid: CBUUID, hex: String, withResponse: Bool) async -> Bool {
        guard let data = Data(hexString: hex), !data.isEmpty else {
            errorMessage = "hex 格式不合法"
            return false
        }
        do {
            try await central.writeValue(
                id: device.id, characteristic: uuid, data: data, withResponse: withResponse
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleNotify(_ uuid: CBUUID) async {
        if notifyingCharacteristics.contains(uuid.uuidString) {
            notifyingCharacteristics.remove(uuid.uuidString)
            notifyTasks.removeValue(forKey: uuid.uuidString)?.cancel()  // 取消任务 → 流终止 → 关 CCCD
        } else {
            await subscribe(uuid)
        }
    }

    private func subscribe(_ uuid: CBUUID) async {
        do {
            let stream = try await central.notifications(id: device.id, characteristic: uuid)
            notifyingCharacteristics.insert(uuid.uuidString)
            notifyTasks[uuid.uuidString]?.cancel()
            notifyTasks[uuid.uuidString] = Task { [weak self] in
                do {
                    for try await data in stream {
                        self?.latestValues[uuid.uuidString] = data
                    }
                } catch {
                    // 断连导致的流终止:保留订阅意图,等重连恢复;错误提示交给状态条。
                    self?.logger.log(.warning, category: "详情",
                                     "通知流中断 \(uuid.uuidString):\(error.localizedDescription)")
                }
            }
            errorMessage = nil
        } catch {
            notifyingCharacteristics.remove(uuid.uuidString)
            errorMessage = error.localizedDescription
        }
    }

    func refreshRSSI() async {
        rssi = try? await central.readRSSI(id: device.id)
    }
}
