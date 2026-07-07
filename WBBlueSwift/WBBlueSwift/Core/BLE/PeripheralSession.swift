//
//  PeripheralSession.swift
//  WBBlueSwift
//
//  单设备 GATT 会话:持有 CBPeripheral,把"发起调用 → 委托回调"的
//  分离式 API 封装为 async/await。
//
//  封装模式:
//  - 一次性回调(读/写/发现/RSSI)→ CheckedContinuation,按特征 UUID 键控;
//  - 多次回调(通知数据)→ AsyncThrowingStream;
//  - 断连时 failAll:把所有挂起 continuation 以 disconnected 错误收尾——
//    否则 await 方永远悬挂,这是 continuation 封装最典型的泄漏点。
//
//  委托回调队列 = 主队列(创建 CBCentralManager 时传入),
//  全类型默认 MainActor 隔离,因此无需锁;高吞吐场景的专用队列改法见 docs/01。
//

@preconcurrency import CoreBluetooth
import Foundation

final class PeripheralSession: NSObject {

    let peripheral: CBPeripheral
    private let logger = BLELogger.shared

    // MARK: - 挂起的 continuation(全部在断连时统一失败)

    private var discoverContinuation: CheckedContinuation<[GATTService], Error>?
    private var pendingCharacteristicDiscovery = 0
    private var readContinuations: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private var writeContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var notifyStateContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]
    private var notifyStreams: [CBUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private var rssiContinuation: CheckedContinuation<Int, Error>?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    private var shortID: String { String(peripheral.identifier.uuidString.prefix(8)) }

    // MARK: - 服务发现

    func discoverServices() async throws -> [GATTService] {
        guard peripheral.state == .connected else { throw BLEError.notConnected }
        guard discoverContinuation == nil else {
            throw BLEError.operationNotSupported("服务发现已在进行中")
        }
        logger.log(category: "GATT", "开始服务发现 \(shortID)")
        return try await withCheckedThrowingContinuation { continuation in
            discoverContinuation = continuation
            peripheral.discoverServices(nil)
        }
    }

    private func findCharacteristic(_ uuid: CBUUID) throws -> CBCharacteristic {
        for service in peripheral.services ?? [] {
            if let characteristic = service.characteristics?.first(where: { $0.uuid == uuid }) {
                return characteristic
            }
        }
        throw BLEError.characteristicNotFound(uuid)
    }

    /// 已发现结果的快照(供 UI 渲染)。
    var snapshot: [GATTService] {
        (peripheral.services ?? []).map { service in
            GATTService(
                uuid: service.uuid,
                isPrimary: service.isPrimary,
                characteristics: (service.characteristics ?? []).map {
                    GATTCharacteristic(
                        uuid: $0.uuid,
                        properties: $0.properties,
                        isNotifying: $0.isNotifying,
                        value: $0.value
                    )
                }
            )
        }
    }

    // MARK: - 读 / 写 / RSSI

    func readValue(characteristic uuid: CBUUID) async throws -> Data {
        let characteristic = try findCharacteristic(uuid)
        guard characteristic.properties.contains(.read) else {
            throw BLEError.operationNotSupported("特征 \(BLEConstants.displayName(for: uuid)) 不可读")
        }
        return try await withCheckedThrowingContinuation { continuation in
            readContinuations[uuid] = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    func writeValue(characteristic uuid: CBUUID, data: Data, withResponse: Bool) async throws {
        let characteristic = try findCharacteristic(uuid)
        if withResponse {
            guard characteristic.properties.contains(.write) else {
                throw BLEError.operationNotSupported("特征不支持有响应写")
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeContinuations[uuid] = continuation
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
        } else {
            guard characteristic.properties.contains(.writeWithoutResponse) else {
                throw BLEError.operationNotSupported("特征不支持免响应写")
            }
            // 免响应写没有回执,但要尊重发送窗口,否则数据会被静默丢弃。
            while !peripheral.canSendWriteWithoutResponse {
                try await Task.sleep(for: .milliseconds(10))
                guard peripheral.state == .connected else { throw BLEError.notConnected }
            }
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }

    func readRSSI() async throws -> Int {
        guard peripheral.state == .connected else { throw BLEError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            rssiContinuation = continuation
            peripheral.readRSSI()
        }
    }

    func maximumWriteLength(withResponse: Bool) -> Int {
        peripheral.maximumWriteValueLength(for: withResponse ? .withResponse : .withoutResponse)
    }

    // MARK: - 通知

    /// 开启通知并返回数据流;消费方取消(for-await 退出)时自动关闭通知。
    func notifications(characteristic uuid: CBUUID) async throws -> AsyncThrowingStream<Data, Error> {
        let characteristic = try findCharacteristic(uuid)
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            throw BLEError.operationNotSupported("特征不支持通知/指示")
        }

        // 等 didUpdateNotificationState 确认 CCCD 写入成功(可能因需配对而失败)。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notifyStateContinuations[uuid] = continuation
            peripheral.setNotifyValue(true, for: characteristic)
        }

        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        notifyStreams[uuid]?.finish()  // 同一特征重复订阅时替换旧流
        notifyStreams[uuid] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopNotifications(characteristic: uuid)
            }
        }
        return stream
    }

    private func stopNotifications(characteristic uuid: CBUUID) {
        notifyStreams.removeValue(forKey: uuid)
        guard peripheral.state == .connected,
              let characteristic = try? findCharacteristic(uuid) else { return }
        peripheral.setNotifyValue(false, for: characteristic)
        logger.log(category: "GATT", "已关闭通知 \(BLEConstants.displayName(for: uuid))")
    }

    // MARK: - 断连清理(异常处理关键点)

    /// 连接断开时调用:所有挂起操作立即失败、所有通知流收尾,防止调用方永久悬挂。
    func failAll(_ error: Error) {
        discoverContinuation?.resume(throwing: error)
        discoverContinuation = nil
        pendingCharacteristicDiscovery = 0

        for (_, continuation) in readContinuations { continuation.resume(throwing: error) }
        readContinuations.removeAll()
        for (_, continuation) in writeContinuations { continuation.resume(throwing: error) }
        writeContinuations.removeAll()
        for (_, continuation) in notifyStateContinuations { continuation.resume(throwing: error) }
        notifyStateContinuations.removeAll()
        for (_, continuation) in notifyStreams { continuation.finish(throwing: error) }
        notifyStreams.removeAll()

        rssiContinuation?.resume(throwing: error)
        rssiContinuation = nil
    }
}

// MARK: - CBPeripheralDelegate(主队列回调,动态隔离与 MainActor 一致)

extension PeripheralSession: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            discoverContinuation?.resume(throwing: BLEError.wrap(error))
            discoverContinuation = nil
            return
        }
        let services = peripheral.services ?? []
        logger.log(category: "GATT", "发现 \(services.count) 个服务,继续发现特征")
        guard !services.isEmpty else {
            discoverContinuation?.resume(returning: [])
            discoverContinuation = nil
            return
        }
        pendingCharacteristicDiscovery = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            logger.log(.warning, category: "GATT",
                       "服务 \(service.uuid) 特征发现失败:\(error.localizedDescription)")
        }
        pendingCharacteristicDiscovery -= 1
        if pendingCharacteristicDiscovery <= 0 {
            discoverContinuation?.resume(returning: snapshot)
            discoverContinuation = nil
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let uuid = characteristic.uuid

        // 同一个回调承载"读响应"与"通知推送"两种语义:有挂起的读先满足读。
        if let continuation = readContinuations.removeValue(forKey: uuid) {
            if let error {
                continuation.resume(throwing: BLEError.wrap(error))
            } else {
                continuation.resume(returning: characteristic.value ?? Data())
            }
            return
        }

        if let stream = notifyStreams[uuid] {
            if let error {
                stream.finish(throwing: BLEError.wrap(error))
                notifyStreams.removeValue(forKey: uuid)
            } else {
                stream.yield(characteristic.value ?? Data())
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let continuation = writeContinuations.removeValue(forKey: characteristic.uuid) else { return }
        if let error {
            continuation.resume(throwing: BLEError.wrap(error))
        } else {
            continuation.resume()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let continuation = notifyStateContinuations.removeValue(forKey: characteristic.uuid) else { return }
        if let error {
            // 典型失败:CBATTError.insufficientAuthentication —— 特征要求配对加密
            continuation.resume(throwing: BLEError.wrap(error))
        } else {
            logger.log(category: "GATT",
                       "通知已\(characteristic.isNotifying ? "开启" : "关闭") \(BLEConstants.displayName(for: characteristic.uuid))")
            continuation.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let continuation = rssiContinuation else { return }
        rssiContinuation = nil
        if let error {
            continuation.resume(throwing: BLEError.wrap(error))
        } else {
            continuation.resume(returning: RSSI.intValue)
        }
    }
}
