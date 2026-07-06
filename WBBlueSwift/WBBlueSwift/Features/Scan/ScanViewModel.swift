//
//  ScanViewModel.swift
//  WBBlueSwift
//
//  扫描页视图模型。演示三个企业级扫描实践:
//  1. 扫描超时自停(持续扫描极耗电,系统也会在后台降级扫描);
//  2. 幽灵设备清理(设备已离开但列表还挂着最后一次广播);
//  3. 服务过滤(减少无关广播回调,也是后台扫描的强制要求)。
//

import CoreBluetooth
import Foundation

@Observable
final class ScanViewModel {

    private let central: any BLECentral
    private let logger = BLELogger.shared

    var state: CentralState = .unknown
    var devices: [DiscoveredDevice] = []
    var isScanning = false
    /// 只扫带心率服务(0x180D)广播的设备
    var filterHeartRateOnly = false

    /// 扫描自停秒数
    private let scanTimeout: TimeInterval = 20
    /// 超过该时长未再收到广播即视为幽灵设备移除
    private let staleAfter: TimeInterval = 6

    private var scanTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    init(central: any BLECentral) {
        self.central = central
    }

    /// 由视图 .task 驱动的状态订阅,视图消失自动取消。
    func observeState() async {
        for await newState in central.stateStream() {
            state = newState
            if newState != .poweredOn, isScanning {
                stopScan()
            }
        }
    }

    func toggleScan() {
        isScanning ? stopScan() : startScan()
    }

    func startScan() {
        guard state == .poweredOn else { return }
        stopScan()
        devices.removeAll()
        isScanning = true

        let services = filterHeartRateOnly ? [BLEConstants.heartRateService] : nil
        scanTask = Task { [weak self] in
            guard let self else { return }
            for await device in central.startScan(services: services) {
                upsert(device)
            }
            isScanning = false
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.scanTimeout ?? 20))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.removeStaleDevices()
            }
        }
    }

    func stopScan() {
        central.stopScan()
        scanTask?.cancel()
        timeoutTask?.cancel()
        cleanupTask?.cancel()
        scanTask = nil
        timeoutTask = nil
        cleanupTask = nil
        isScanning = false
    }

    private func upsert(_ device: DiscoveredDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
            logger.log(category: "扫描", "发现 \(device.displayName) RSSI \(device.rssi)")
        }
    }

    private func removeStaleDevices() {
        let cutoff = Date.now.addingTimeInterval(-staleAfter)
        devices.removeAll { $0.lastSeen < cutoff }
    }
}
