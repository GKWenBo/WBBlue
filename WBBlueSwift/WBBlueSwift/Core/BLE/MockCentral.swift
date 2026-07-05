//
//  MockCentral.swift
//  WBBlueSwift
//
//  BLECentral 的离线实现:模拟器(无蓝牙硬件)与单元测试用。
//  内置两台虚拟设备:
//  - "WB 心率带 (Mock)":标准心率服务(0x2A37 每秒通知一次正弦波心率)
//    + 私有服务 FFF0(FFF1 写入私有协议帧,按协议回响应帧)。
//  - "WB 温湿度计 (Mock)":只有电池服务,演示"无所需服务"的设备。
//
//  故障注入(演示异常处理):simulateConnectFailure 让连接一直超时;
//  randomDropInterval 定时强制断连,驱动 ReconnectOrchestrator 演示自动重连。
//

import CoreBluetooth
import Foundation

final class MockCentral: BLECentral {

    // MARK: - 虚拟设备定义

    private struct MockDevice {
        let id: UUID
        let name: String
        let services: [GATTService]
        let advertisedServices: [CBUUID]
    }

    private static let heartRateBandID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000180D")!
    private static let thermometerID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-00000000180F")!

    private let devices: [MockDevice] = [
        MockDevice(
            id: MockCentral.heartRateBandID,
            name: "WB 心率带 (Mock)",
            services: [
                GATTService(uuid: BLEConstants.heartRateService, isPrimary: true, characteristics: [
                    GATTCharacteristic(
                        uuid: BLEConstants.heartRateMeasurement,
                        properties: [.notify], isNotifying: false, value: nil
                    ),
                    GATTCharacteristic(
                        uuid: BLEConstants.bodySensorLocation,
                        properties: [.read], isNotifying: false, value: Data([0x01])
                    ),
                ]),
                GATTService(uuid: BLEConstants.batteryService, isPrimary: true, characteristics: [
                    GATTCharacteristic(
                        uuid: BLEConstants.batteryLevel,
                        properties: [.read, .notify], isNotifying: false, value: Data([88])
                    ),
                ]),
                GATTService(uuid: BLEConstants.customService, isPrimary: true, characteristics: [
                    GATTCharacteristic(
                        uuid: BLEConstants.customData,
                        properties: [.write, .writeWithoutResponse, .notify],
                        isNotifying: false, value: nil
                    ),
                    GATTCharacteristic(
                        uuid: BLEConstants.customInfo,
                        properties: [.read], isNotifying: false,
                        value: Data("WB-HRM-2000 fw1.2.3 sn20260706".utf8)
                    ),
                ]),
            ],
            advertisedServices: [BLEConstants.heartRateService, BLEConstants.customService]
        ),
        MockDevice(
            id: MockCentral.thermometerID,
            name: "WB 温湿度计 (Mock)",
            services: [
                GATTService(uuid: BLEConstants.batteryService, isPrimary: true, characteristics: [
                    GATTCharacteristic(
                        uuid: BLEConstants.batteryLevel,
                        properties: [.read], isNotifying: false, value: Data([64])
                    ),
                ]),
            ],
            advertisedServices: [BLEConstants.batteryService]
        ),
    ]

    // MARK: - 故障注入开关

    /// 打开后 connect 一直挂起直到超时(演示连接超时与重试放弃)。
    var simulateConnectFailure = false
    /// 非 nil 时,连接成功后每隔该秒数强制断连一次(演示自动重连)。
    var randomDropInterval: TimeInterval? = nil

    // MARK: - 运行时状态

    private let logger = BLELogger.shared
    private var mockState: CentralState = .poweredOn
    private var connectedIDs: Set<UUID> = []
    private var scanTask: Task<Void, Never>?
    private var notifyTasks: [String: Task<Void, Never>] = [:]  // "deviceID/charUUID"
    private var dropTasks: [UUID: Task<Void, Never>] = [:]
    private var eventContinuations: [UUID: [UUID: AsyncStream<ConnectionEvent>.Continuation]] = [:]
    private var notifyStreams: [String: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    private var stateContinuations: [UUID: AsyncStream<CentralState>.Continuation] = [:]
    /// 私有协议回显的响应序号
    private var heartRatePhase = 0.0

    // MARK: - BLECentral

    var state: CentralState { mockState }

    /// 演示"蓝牙开关"场景:切换 Mock 的状态并广播。
    func setPowered(_ on: Bool) {
        mockState = on ? .poweredOn : .poweredOff
        for continuation in stateContinuations.values { continuation.yield(mockState) }
        if !on {
            for id in connectedIDs {
                broadcast(.disconnected(error: BLEError.poweredOff), for: id)
            }
            connectedIDs.removeAll()
            stopAllSideTasks()
        }
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
        continuation.yield(mockState)
        return stream
    }

    func startScan(services: [CBUUID]?) -> AsyncStream<DiscoveredDevice> {
        let (stream, continuation) = AsyncStream<DiscoveredDevice>.makeStream()
        guard mockState == .poweredOn else {
            continuation.finish()
            return stream
        }
        logger.log(category: "Mock", "开始扫描(虚拟设备 \(devices.count) 台)")
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            // 模拟广播:每 0.8s 每台设备各推一次发现,RSSI 随机抖动。
            while !Task.isCancelled {
                guard let self else { return }
                for device in devices {
                    if let filter = services,
                       !device.advertisedServices.contains(where: filter.contains) {
                        continue
                    }
                    continuation.yield(DiscoveredDevice(
                        id: device.id,
                        name: device.name,
                        rssi: -50 - Int.random(in: 0...30),
                        advertisedServices: device.advertisedServices,
                        manufacturerData: Data([0x57, 0x42, 0x01, 0x02]),  // "WB" + 自定义
                        isConnectable: true,
                        lastSeen: .now
                    ))
                }
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanTask?.cancel()
                self?.scanTask = nil
            }
        }
        return stream
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    func connect(id: UUID, timeout: TimeInterval) async throws {
        if let error = mockState.asError { throw error }
        guard let device = devices.first(where: { $0.id == id }) else {
            throw BLEError.deviceNotFound
        }
        if simulateConnectFailure {
            try await Task.sleep(for: .seconds(timeout))
            throw BLEError.timeout(operation: "连接")
        }
        try await Task.sleep(for: .milliseconds(400))  // 模拟建连耗时
        connectedIDs.insert(id)
        logger.log(category: "Mock", "已连接 \(device.name)")
        broadcast(.connected, for: id)
        startDropTimerIfNeeded(for: id)
    }

    func disconnect(id: UUID) {
        guard connectedIDs.remove(id) != nil else { return }
        stopSideTasks(for: id)
        logger.log(category: "Mock", "主动断开")
        broadcast(.disconnected(error: nil), for: id)
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

    func discoverServices(id: UUID) async throws -> [GATTService] {
        let device = try connectedDevice(id)
        try await Task.sleep(for: .milliseconds(300))
        return device.services
    }

    func readValue(id: UUID, characteristic: CBUUID) async throws -> Data {
        let (_, char) = try findCharacteristic(id, characteristic)
        guard char.properties.contains(.read) else {
            throw BLEError.operationNotSupported("特征不可读")
        }
        try await Task.sleep(for: .milliseconds(120))
        return char.value ?? Data()
    }

    func writeValue(id: UUID, characteristic: CBUUID, data: Data, withResponse: Bool) async throws {
        let (_, char) = try findCharacteristic(id, characteristic)
        let writable: CBCharacteristicProperties = withResponse ? .write : .writeWithoutResponse
        guard char.properties.contains(writable) else {
            throw BLEError.operationNotSupported(withResponse ? "特征不支持有响应写" : "特征不支持免响应写")
        }
        try await Task.sleep(for: .milliseconds(withResponse ? 120 : 15))
        logger.log(category: "Mock", "收到写入 \(data.hexString(separator: " "))")

        // 私有协议数据通道:解析帧并回响应帧(cmd | 0x80)。
        if characteristic == BLEConstants.customData {
            respondToProtocolWrite(id: id, data: data)
        }
    }

    func notifications(id: UUID, characteristic: CBUUID) async throws -> AsyncThrowingStream<Data, Error> {
        let (_, char) = try findCharacteristic(id, characteristic)
        guard char.properties.contains(.notify) || char.properties.contains(.indicate) else {
            throw BLEError.operationNotSupported("特征不支持通知")
        }
        try await Task.sleep(for: .milliseconds(100))  // 模拟 CCCD 写入往返

        let key = streamKey(id, characteristic)
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        notifyStreams[key]?.finish()
        notifyStreams[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.notifyTasks[key]?.cancel()
                self?.notifyTasks.removeValue(forKey: key)
                self?.notifyStreams.removeValue(forKey: key)
            }
        }

        // 心率特征:每秒推一帧正弦波心率(60-100 bpm)。
        if characteristic == BLEConstants.heartRateMeasurement {
            notifyTasks[key]?.cancel()
            notifyTasks[key] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    heartRatePhase += 0.15
                    let bpm = UInt8(80 + 20 * sin(heartRatePhase) + Double.random(in: -2...2))
                    // flags 0x06:uint8 + 传感器已接触
                    notifyStreams[key]?.yield(Data([0x06, bpm]))
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        logger.log(category: "Mock", "通知已开启 \(BLEConstants.displayName(for: characteristic))")
        return stream
    }

    func maximumWriteLength(id: UUID, withResponse: Bool) -> Int {
        withResponse ? 512 : 182  // 模拟 iPhone 常见协商结果(ATT_MTU 185 - 3)
    }

    func readRSSI(id: UUID) async throws -> Int {
        _ = try connectedDevice(id)
        try await Task.sleep(for: .milliseconds(80))
        return -55 - Int.random(in: 0...20)
    }

    // MARK: - 私有协议模拟外设固件

    /// 按私有协议规范回帧:回显命令 = cmd | 0x80,payload 依命令而定。
    private func respondToProtocolWrite(id: UUID, data: Data) {
        var assembler = PacketAssembler()
        for event in assembler.feed(data) {
            switch event {
            case .packet(let packet):
                let responsePayload: Data
                switch packet.cmd {
                case 0x01: responsePayload = Data("pong".utf8)                       // ping
                case 0x02: responsePayload = Data([88])                              // 查询电量
                case 0x03: responsePayload = Data("WB-HRM-2000 fw1.2.3".utf8)        // 查询版本
                default: responsePayload = packet.payload                            // 回显
                }
                let response = PacketCodec.encode(
                    Packet(cmd: packet.cmd | 0x80, seq: packet.seq, payload: responsePayload)
                )
                let key = streamKey(id, BLEConstants.customData)
                // 模拟固件处理延迟后经通知上行,按 20B 分包发送以演示组包。
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard let self else { return }
                    for chunk in PacketCodec.chunks(of: response, mtuPayload: 20) {
                        notifyStreams[key]?.yield(chunk)
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                }
            case .error(let error):
                logger.log(.warning, category: "Mock", "收到坏帧:\(error)")
            }
        }
    }

    // MARK: - 辅助

    private func connectedDevice(_ id: UUID) throws -> MockDevice {
        guard connectedIDs.contains(id) else { throw BLEError.notConnected }
        guard let device = devices.first(where: { $0.id == id }) else {
            throw BLEError.deviceNotFound
        }
        return device
    }

    private func findCharacteristic(
        _ id: UUID, _ uuid: CBUUID
    ) throws -> (GATTService, GATTCharacteristic) {
        let device = try connectedDevice(id)
        for service in device.services {
            if let char = service.characteristics.first(where: { $0.uuid == uuid }) {
                return (service, char)
            }
        }
        throw BLEError.characteristicNotFound(uuid)
    }

    private func streamKey(_ id: UUID, _ uuid: CBUUID) -> String {
        "\(id.uuidString)/\(uuid.uuidString)"
    }

    private func broadcast(_ event: ConnectionEvent, for id: UUID) {
        for continuation in (eventContinuations[id] ?? [:]).values {
            continuation.yield(event)
        }
    }

    private func startDropTimerIfNeeded(for id: UUID) {
        guard let interval = randomDropInterval else { return }
        dropTasks[id]?.cancel()
        dropTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, !Task.isCancelled, connectedIDs.remove(id) != nil else { return }
            logger.log(.warning, category: "Mock", "故障注入:强制断连")
            stopSideTasks(for: id)
            broadcast(.disconnected(error: BLEError.disconnected(underlying: nil)), for: id)
        }
    }

    private func stopSideTasks(for id: UUID) {
        dropTasks.removeValue(forKey: id)?.cancel()
        let prefix = id.uuidString
        for (key, task) in notifyTasks where key.hasPrefix(prefix) {
            task.cancel()
            notifyTasks.removeValue(forKey: key)
        }
        for (key, stream) in notifyStreams where key.hasPrefix(prefix) {
            stream.finish(throwing: BLEError.disconnected(underlying: nil))
            notifyStreams.removeValue(forKey: key)
        }
    }

    private func stopAllSideTasks() {
        for task in notifyTasks.values { task.cancel() }
        notifyTasks.removeAll()
        for stream in notifyStreams.values { stream.finish(throwing: BLEError.poweredOff) }
        notifyStreams.removeAll()
        for task in dropTasks.values { task.cancel() }
        dropTasks.removeAll()
    }
}
