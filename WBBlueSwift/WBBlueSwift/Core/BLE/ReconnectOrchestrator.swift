//
//  ReconnectOrchestrator.swift
//  WBBlueSwift
//
//  自动重连状态机(稳定性工程核心)。
//
//  规则:
//  - 意外断连(disconnected 事件带 error)→ 指数退避 + 抖动重试,封顶后放弃;
//  - 主动断开(error == nil)→ 停在 idle,绝不重连;
//  - 连接成功 → 重置重试计数,并执行 onReconnected 回调(重新发现服务、重新订阅——
//    重连后旧的 GATT 句柄与 CCCD 订阅全部失效,必须重建,这是最常被漏掉的坑)。
//

import Foundation

@Observable
final class ReconnectOrchestrator {

    enum Phase: Equatable {
        case idle
        case connecting(attempt: Int)
        case connected
        /// 正在等待第 attempt 次重试
        case waitingRetry(attempt: Int, delay: TimeInterval)
        case failed(String)

        var text: String {
            switch self {
            case .idle: "未连接"
            case .connecting(let attempt): attempt <= 1 ? "连接中…" : "重连中(第 \(attempt) 次)…"
            case .connected: "已连接"
            case .waitingRetry(let attempt, let delay):
                String(format: "断线,%.1fs 后第 %d 次重连", delay, attempt)
            case .failed(let reason): "已放弃:\(reason)"
            }
        }
    }

    private(set) var phase: Phase = .idle

    private let central: any BLECentral
    private let logger = BLELogger.shared

    /// 单次连接超时
    var connectTimeout: TimeInterval = 8
    /// 退避参数
    var backoffBase: TimeInterval = 1
    var backoffCap: TimeInterval = 30
    /// 最大重试次数,超过进入 failed
    var maxAttempts = 6

    private var watchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(central: any BLECentral) {
        self.central = central
    }

    /// 建立连接并保持:断了自动重连,直到 stop()/放弃。
    /// - Parameter onReconnected: 每次(重)连成功后执行,用于重新发现服务、重新订阅。
    func start(deviceID: UUID, onReconnected: @escaping () async -> Void) {
        stop()

        // 先起监听再连接,避免竞态漏掉事件。
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in central.connectionEvents(for: deviceID) {
                guard !Task.isCancelled else { return }
                switch event {
                case .connected:
                    phase = .connected
                case .disconnected(let error):
                    guard error != nil else {
                        // 主动断开:收工,不重连。
                        phase = .idle
                        return
                    }
                    logger.log(.warning, category: "重连", "意外断连,启动自动重连")
                    scheduleReconnect(deviceID: deviceID, attempt: 1, onReconnected: onReconnected)
                }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            phase = .connecting(attempt: 1)
            do {
                try await central.connect(id: deviceID, timeout: connectTimeout)
                await onReconnected()
            } catch {
                // 首连失败也走重试(设备可能刚好不在广播窗口)。
                scheduleReconnect(deviceID: deviceID, attempt: 1, onReconnected: onReconnected)
            }
        }
    }

    private func scheduleReconnect(
        deviceID: UUID,
        attempt: Int,
        onReconnected: @escaping () async -> Void
    ) {
        guard attempt <= maxAttempts else {
            phase = .failed("重试 \(maxAttempts) 次未恢复")
            logger.log(.error, category: "重连", "放弃:连续 \(maxAttempts) 次重连失败")
            return
        }
        let delay = Backoff.delay(attempt: attempt, base: backoffBase, cap: backoffCap)
        phase = .waitingRetry(attempt: attempt, delay: delay)
        logger.log(category: "重连", String(format: "第 %d 次重连将在 %.1fs 后发起", attempt, delay))

        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            phase = .connecting(attempt: attempt)
            do {
                try await central.connect(id: deviceID, timeout: connectTimeout)
                logger.log(category: "重连", "第 \(attempt) 次重连成功")
                await onReconnected()
            } catch {
                guard !Task.isCancelled else { return }
                scheduleReconnect(deviceID: deviceID, attempt: attempt + 1, onReconnected: onReconnected)
            }
        }
    }

    /// 停止保持(不断开现有连接);之后的断连不再自动重连。
    func stop() {
        watchTask?.cancel()
        watchTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    /// 用户主动断开:停止保持并断开连接。
    func stopAndDisconnect(deviceID: UUID) {
        stop()
        central.disconnect(id: deviceID)
        phase = .idle
    }
}
