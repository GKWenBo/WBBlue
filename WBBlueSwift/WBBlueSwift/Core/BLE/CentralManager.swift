//
//  CentralManager.swift
//  WBBlueSwift
//
//  BLECentral 的 CoreBluetooth 真实实现。
//
//  关键设计:
//  - 委托回调派发主队列(queue: nil),与全工程默认 MainActor 隔离一致,免锁;
//  - CBPeripheral 必须强持有(sessions 字典),否则系统会立刻取消连接;
//  - connect 自带超时:CoreBluetooth 的 connect 永不超时,超时后必须
//    cancelPeripheralConnection,否则设备回到范围内会"幽灵连接"成功;
//  - 状态恢复(后台被杀拉活)所需的 restore identifier 见 docs/05,
//    示例工程未开启后台模式故不传。
//

import CoreBluetooth
import Foundation

final class CentralManager: NSObject, BLECentral {

    private var central: CBCentralManager!
    private let logger = BLELogger.shared

    /// 已发现的外设强引用缓存(id → CBPeripheral)。connect 前必须能查到。
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    /// 已连接/连接中设备的 GATT 会话。
    private var sessions: [UUID: PeripheralSession] = [:]

    private var stateContinuations: [UUID: AsyncStream<CentralState>.Continuation] = [:]
    private var scanContinuation: AsyncStream<DiscoveredDevice>.Continuation?
    private var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var eventContinuations: [UUID: [UUID: AsyncStream<ConnectionEvent>.Continuation]] = [:]
    /// 记录哪些断开是 App 主动发起的,用于区分 disconnected 事件的 error 语义。
    private var intentionalDisconnects: Set<UUID> = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - 状态

    var state: CentralState {
        CentralState(central.state)
    }

    func stateStream() -> AsyncStream<CentralState> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<CentralState>.makeStream()
        stateContinuations[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stateContinuations.removeValue(forKey: key)
            }
        }
        continuation.yield(state)
        return stream
    }

    // MARK: - 扫描

    func startScan(services: [CBUUID]?) -> AsyncStream<DiscoveredDevice> {
        scanContinuation?.finish()
        let (stream, continuation) = AsyncStream<DiscoveredDevice>.makeStream()
        scanContinuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopScan()
            }
        }

        guard state == .poweredOn else {
            logger.log(.warning, category: "扫描", "蓝牙未就绪(\(state.rawValue)),扫描流直接结束")
            continuation.finish()
            return stream
        }

        // 允许重复发现:同一设备的广播会反复回调,用于持续刷新 RSSI。
        central.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        logger.log(category: "扫描", "开始扫描" + (services.map { " 过滤:\($0)" } ?? "(无过滤)"))
        return stream
    }

    func stopScan() {
        if central.state == .poweredOn, central.isScanning {
            central.stopScan()
            logger.log(category: "扫描", "停止扫描")
        }
        scanContinuation?.finish()
        scanContinuation = nil
    }

    // MARK: - 连接

    func connect(id: UUID, timeout: TimeInterval) async throws {
        if let error = state.asError { throw error }
        guard let peripheral = knownPeripherals[id] else { throw BLEError.deviceNotFound }
        guard peripheral.state != .connected else { return }
        guard connectContinuations[id] == nil else {
            throw BLEError.operationNotSupported("该设备正在连接中")
        }

        logger.log(category: "连接", "连接 \(peripheral.name ?? id.uuidString),超时 \(Int(timeout))s")
        sessions[id] = PeripheralSession(peripheral: peripheral)

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.failConnect(id: id, error: BLEError.timeout(operation: "连接"))
        }
        defer { timeoutTask.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuations[id] = continuation
            central.connect(peripheral)
        }
    }

    /// 连接失败统一出口:恢复挂起的 connect、撤销系统层连接请求。
    private func failConnect(id: UUID, error: Error) {
        guard let continuation = connectContinuations.removeValue(forKey: id) else { return }
        if let peripheral = knownPeripherals[id] {
            // 必须撤销:不撤销的话系统会无限期保留连接意图,设备出现时"幽灵连接"。
            central.cancelPeripheralConnection(peripheral)
        }
        sessions.removeValue(forKey: id)
        logger.log(.error, category: "连接", "连接失败:\(error.localizedDescription)")
        continuation.resume(throwing: error)
    }

    func disconnect(id: UUID) {
        guard let peripheral = knownPeripherals[id] else { return }
        intentionalDisconnects.insert(id)
        central.cancelPeripheralConnection(peripheral)
        logger.log(category: "连接", "主动断开 \(peripheral.name ?? id.uuidString)")
    }

    func connectionEvents(for id: UUID) -> AsyncStream<ConnectionEvent> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<ConnectionEvent>.makeStream()
        eventContinuations[id, default: [:]][key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.eventContinuations[id]?.removeValue(forKey: key)
            }
        }
        return stream
    }

    private func broadcast(_ event: ConnectionEvent, for id: UUID) {
        for continuation in (eventContinuations[id] ?? [:]).values {
            continuation.yield(event)
        }
    }

    // MARK: - GATT 转发到会话

    private func session(for id: UUID) throws -> PeripheralSession {
        guard let session = sessions[id], session.peripheral.state == .connected else {
            throw BLEError.notConnected
        }
        return session
    }

    func discoverServices(id: UUID) async throws -> [GATTService] {
        try await session(for: id).discoverServices()
    }

    func readValue(id: UUID, characteristic: CBUUID) async throws -> Data {
        try await session(for: id).readValue(characteristic: characteristic)
    }

    func writeValue(id: UUID, characteristic: CBUUID, data: Data, withResponse: Bool) async throws {
        try await session(for: id).writeValue(
            characteristic: characteristic, data: data, withResponse: withResponse
        )
    }

    func notifications(id: UUID, characteristic: CBUUID) async throws -> AsyncThrowingStream<Data, Error> {
        try await session(for: id).notifications(characteristic: characteristic)
    }

    func maximumWriteLength(id: UUID, withResponse: Bool) -> Int {
        (try? session(for: id))?.maximumWriteLength(withResponse: withResponse) ?? 20
    }

    func readRSSI(id: UUID) async throws -> Int {
        try await session(for: id).readRSSI()
    }
}

// MARK: - CBCentralManagerDelegate(主队列回调)

extension CentralManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = CentralState(central.state)
        logger.log(category: "状态", "蓝牙状态 → \(state.rawValue)")
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
        // poweredOff/resetting 时系统已隐式断开所有连接且不回调 didDisconnect,
        // 这里手动清理,避免上层还以为连着。
        if state != .poweredOn {
            for (id, session) in sessions {
                session.failAll(BLEError.poweredOff)
                broadcast(.disconnected(error: state.asError), for: id)
            }
            sessions.removeAll()
            scanContinuation?.finish()
            scanContinuation = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        knownPeripherals[peripheral.identifier] = peripheral

        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: peripheral.name
                ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            advertisedServices: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [],
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? true,
            lastSeen: .now
        )
        scanContinuation?.yield(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        logger.log(category: "连接", "已连接 \(peripheral.name ?? id.uuidString)")
        connectContinuations.removeValue(forKey: id)?.resume()
        broadcast(.connected, for: id)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        failConnect(
            id: peripheral.identifier,
            error: error.map { BLEError.wrap($0) } ?? BLEError.timeout(operation: "连接")
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier
        let intentional = intentionalDisconnects.remove(id) != nil

        // 会话内所有挂起操作立即失败(异常处理关键点)
        sessions.removeValue(forKey: id)?.failAll(BLEError.disconnected(underlying: error))

        if intentional {
            logger.log(category: "连接", "已主动断开 \(peripheral.name ?? id.uuidString)")
            broadcast(.disconnected(error: nil), for: id)
        } else {
            logger.log(.warning, category: "连接",
                       "意外断连 \(peripheral.name ?? id.uuidString):\(error?.localizedDescription ?? "无原因")")
            broadcast(.disconnected(error: error ?? BLEError.disconnected(underlying: nil)), for: id)
        }
    }
}

extension CentralState {
    init(_ state: CBManagerState) {
        switch state {
        case .poweredOn: self = .poweredOn
        case .poweredOff: self = .poweredOff
        case .unauthorized: self = .unauthorized
        case .unsupported: self = .unsupported
        case .resetting: self = .resetting
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
