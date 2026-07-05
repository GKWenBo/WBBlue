//
//  BLECentral.swift
//  WBBlueSwift
//
//  Central 能力的抽象接口:真实实现 CentralManager(CoreBluetooth)
//  与 MockCentral(模拟器离线演示/单元测试)共同遵循。
//  这是企业架构的关键一层——业务与 UI 只依赖此协议,硬件可替换、可测试。
//

import CoreBluetooth
import Foundation

protocol BLECentral: AnyObject {

    /// 当前蓝牙状态(快照)。
    var state: CentralState { get }

    /// 状态变化流。每次调用返回独立订阅,订阅时先补发当前状态。
    func stateStream() -> AsyncStream<CentralState>

    /// 开始扫描并返回发现流。services 非空时按服务 UUID 过滤(企业标配,
    /// 省电且避免海量无关广播)。同一时刻只支持一路扫描,再次调用会替换前一路。
    func startScan(services: [CBUUID]?) -> AsyncStream<DiscoveredDevice>

    func stopScan()

    /// 连接设备,超时抛 `BLEError.timeout` 并主动取消系统层连接请求
    /// (CoreBluetooth 的 connect 永不超时,必须自己实现)。
    func connect(id: UUID, timeout: TimeInterval) async throws

    /// 主动断开。产生的 disconnected 事件 error 为 nil,重连编排层据此不再重连。
    func disconnect(id: UUID)

    /// 指定设备的连接事件流(可多路订阅)。
    func connectionEvents(for id: UUID) -> AsyncStream<ConnectionEvent>

    /// 发现全部服务与特征(连接后必须先做,GATT 句柄才可用)。
    func discoverServices(id: UUID) async throws -> [GATTService]

    func readValue(id: UUID, characteristic: CBUUID) async throws -> Data

    /// withResponse=true 走 ATT Write Request(有确认、可靠);
    /// false 走 Write Command(无确认、吞吐高,需自查发送窗口)。
    func writeValue(id: UUID, characteristic: CBUUID, data: Data, withResponse: Bool) async throws

    /// 订阅通知:内部写 CCCD 开启,流结束(消费方取消)时自动关闭。
    func notifications(id: UUID, characteristic: CBUUID) async throws -> AsyncThrowingStream<Data, Error>

    /// 连接态单帧最大写负载(ATT_MTU - 3),分包依据。
    func maximumWriteLength(id: UUID, withResponse: Bool) -> Int

    func readRSSI(id: UUID) async throws -> Int
}
