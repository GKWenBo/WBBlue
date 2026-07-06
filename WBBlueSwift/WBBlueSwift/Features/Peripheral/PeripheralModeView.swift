//
//  PeripheralModeView.swift
//  WBBlueSwift
//
//  外设(Peripheral)角色:用 CBPeripheralManager 把本机广播成一台心率带。
//  用途:两台 iPhone 互测(一台跑本页,另一台跑扫描页),不依赖第三方外设。
//
//  知识点:
//  - GATT Server 搭建:CBMutableService/CBMutableCharacteristic;
//  - 订阅者管理与 updateValue 发送队列满(peripheralManagerIsReady)背压处理;
//  - iOS 后台广播降级:退后台后 LocalName 丢失、服务 UUID 进 overflow 区,
//    其他 iOS 设备还能扫到,多数安卓扫不到——真机演示这一坑。
//

import CoreBluetooth
import Foundation
import SwiftUI

@Observable
final class PeripheralModeViewModel: NSObject {

    var state: CentralState = .unknown
    var isAdvertising = false
    var subscriberCount = 0
    var sentCount = 0
    var lastBPM: Int = 0

    private var manager: CBPeripheralManager?
    private var heartRateCharacteristic: CBMutableCharacteristic?
    private var notifyTask: Task<Void, Never>?
    private var phase = 0.0
    /// updateValue 队列满时置位,等 peripheralManagerIsReady 再发。
    private var waitingForQueue = false
    private let logger = BLELogger.shared

    /// 懒启动:进入本页才创建 manager(创建即触发权限弹窗)。
    func start() {
        guard manager == nil else { return }
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        notifyTask?.cancel()
        notifyTask = nil
        if isAdvertising {
            manager?.stopAdvertising()
            isAdvertising = false
        }
        manager?.removeAllServices()
        subscriberCount = 0
    }

    private func setupServiceAndAdvertise() {
        guard let manager else { return }

        let heartRate = CBMutableCharacteristic(
            type: BLEConstants.heartRateMeasurement,
            properties: [.notify],
            value: nil,  // notify 特征的值必须动态提供
            permissions: []
        )
        let location = CBMutableCharacteristic(
            type: BLEConstants.bodySensorLocation,
            properties: [.read],
            value: Data([0x02]),  // 手腕
            permissions: [.readable]
        )
        let service = CBMutableService(type: BLEConstants.heartRateService, primary: true)
        service.characteristics = [heartRate, location]
        heartRateCharacteristic = heartRate

        manager.removeAllServices()
        manager.add(service)
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "WB-iPhone 心率带",
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.heartRateService],
        ])
    }

    /// 每秒生成一帧心率并推给订阅者。
    private func startNotifyLoopIfNeeded() {
        guard notifyTask == nil else { return }
        notifyTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pushHeartRate()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func pushHeartRate() {
        guard let manager, let characteristic = heartRateCharacteristic,
              subscriberCount > 0, !waitingForQueue else { return }
        phase += 0.15
        let bpm = UInt8(78 + 18 * sin(phase) + Double.random(in: -2...2))
        lastBPM = Int(bpm)
        let ok = manager.updateValue(
            Data([0x06, bpm]), for: characteristic, onSubscribedCentrals: nil
        )
        if ok {
            sentCount += 1
        } else {
            // 发送队列满:典型背压场景,等 isReady 回调再继续。
            waitingForQueue = true
            logger.log(.warning, category: "外设", "updateValue 队列满,暂停推送")
        }
    }
}

extension PeripheralModeViewModel: @preconcurrency CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        state = CentralState(peripheral.state)
        logger.log(category: "外设", "PeripheralManager 状态 → \(state.rawValue)")
        if peripheral.state == .poweredOn {
            setupServiceAndAdvertise()
        } else {
            isAdvertising = false
            subscriberCount = 0
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            logger.log(.error, category: "外设", "广播失败:\(error.localizedDescription)")
            return
        }
        isAdvertising = true
        logger.log(category: "外设", "开始广播心率服务")
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscriberCount += 1
        logger.log(category: "外设", "新订阅者(MTU \(central.maximumUpdateValueLength)B)")
        startNotifyLoopIfNeeded()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscriberCount = max(0, subscriberCount - 1)
        logger.log(category: "外设", "订阅者离开,剩 \(subscriberCount)")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        waitingForQueue = false
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        // 只读特征已带静态值,系统自动应答;这里兜底其余读请求。
        request.value = Data([0x02])
        peripheral.respond(to: request, withResult: .success)
    }
}

struct PeripheralModeView: View {

    @State private var model = PeripheralModeViewModel()

    var body: some View {
        List {
            Section {
                LabeledContent("蓝牙状态", value: model.state.rawValue)
                LabeledContent("广播", value: model.isAdvertising ? "进行中" : "未开始")
                LabeledContent("订阅者", value: "\(model.subscriberCount)")
                if model.subscriberCount > 0 {
                    LabeledContent("已推送", value: "\(model.sentCount) 帧(最近 \(model.lastBPM) bpm)")
                }
            } header: {
                Text("本机作为心率带")
            } footer: {
                if model.state == .unsupported {
                    Text("模拟器不支持外设角色,请用真机体验;Mock 数据源下可直接在扫描页连接虚拟设备。")
                } else {
                    Text("用另一台 iPhone 打开本 App 扫描页(或 nRF Connect / LightBlue)即可发现并订阅本机。注意:App 退后台后广播降级,LocalName 丢失、服务 UUID 进 overflow 区,多数安卓设备将扫不到。")
                }
            }
        }
        .navigationTitle("外设模式")
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
