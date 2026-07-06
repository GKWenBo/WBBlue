//
//  AppModel.swift
//  WBBlueSwift
//
//  应用级依赖容器:持有 BLECentral 的当前实现并支持运行时切换。
//  模拟器默认 Mock(无蓝牙硬件),真机默认 CoreBluetooth;
//  真实 CentralManager 懒创建——首次创建即触发系统蓝牙权限弹窗,
//  不用就不要碰(企业 App 的权限最佳实践)。
//

import Foundation

@Observable
final class AppModel {

    static func defaultUseMock() -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// 数据源开关(切换后视图树以 generation 为 id 整体重建,避免旧流残留)。
    var useMock: Bool = AppModel.defaultUseMock() {
        didSet { generation += 1 }
    }
    private(set) var generation = 0

    let mockCentral = MockCentral()
    @ObservationIgnored private lazy var realCentral = CentralManager()

    var central: any BLECentral {
        useMock ? mockCentral : realCentral
    }

    // MARK: - Mock 故障注入(演示异常处理)

    var simulateConnectFailure = false {
        didSet { mockCentral.simulateConnectFailure = simulateConnectFailure }
    }
    /// 打开后 Mock 设备连上 15 秒即强制断连,演示自动重连。
    var simulateRandomDrop = false {
        didSet { mockCentral.randomDropInterval = simulateRandomDrop ? 15 : nil }
    }
}
