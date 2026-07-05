//
//  Backoff.swift
//  WBBlueSwift
//
//  指数退避纯函数。自动重连必须退避:立即重试会加剧射频拥塞,
//  多设备同时掉线时还会互相踩踏;抖动(jitter)避免同批设备同一时刻齐发重连。
//

import Foundation

enum Backoff {

    /// 计算第 `attempt` 次重试(从 1 起)前应等待的秒数。
    ///
    /// - 基础值:`base * 2^(attempt-1)`,封顶 `cap`。
    /// - 抖动:在基础值上再乘 `1 + random(0...jitterRatio)`。
    /// - `generator` 可注入以便单元测试;默认使用系统随机源。
    static func delay(
        attempt: Int,
        base: TimeInterval,
        cap: TimeInterval,
        jitterRatio: Double,
        using generator: inout some RandomNumberGenerator
    ) -> TimeInterval {
        let attempt = max(attempt, 1)
        // 指数用移位计算,先钳制指数防溢出。
        let exponent = min(attempt - 1, 62)
        let raw = base * TimeInterval(1 << exponent)
        let capped = min(raw, cap)
        guard jitterRatio > 0 else { return capped }
        let jitter = Double.random(in: 0...jitterRatio, using: &generator)
        return capped * (1 + jitter)
    }

    /// 使用系统随机源的便捷版本。
    static func delay(
        attempt: Int,
        base: TimeInterval = 1,
        cap: TimeInterval = 30,
        jitterRatio: Double = 0.5
    ) -> TimeInterval {
        var rng = SystemRandomNumberGenerator()
        return delay(attempt: attempt, base: base, cap: cap, jitterRatio: jitterRatio, using: &rng)
    }
}
