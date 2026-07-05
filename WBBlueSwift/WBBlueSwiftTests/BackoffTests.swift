//
//  BackoffTests.swift
//  WBBlueSwiftTests
//
//  指数退避纯函数单元测试(注入固定随机源保证可复现)。
//

import Foundation
import Testing
@testable import WBBlueSwift

/// 返回固定值的随机源,便于断言 jitter。
private struct FixedGenerator: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}

struct BackoffTests {

    @Test("无抖动时按 base * 2^(attempt-1) 指数增长")
    func exponentialGrowth() {
        var rng = FixedGenerator(value: 0)
        #expect(Backoff.delay(attempt: 1, base: 1, cap: 30, jitterRatio: 0, using: &rng) == 1)
        #expect(Backoff.delay(attempt: 2, base: 1, cap: 30, jitterRatio: 0, using: &rng) == 2)
        #expect(Backoff.delay(attempt: 4, base: 1, cap: 30, jitterRatio: 0, using: &rng) == 8)
    }

    @Test("超过上限时封顶为 cap")
    func capped() {
        var rng = FixedGenerator(value: 0)
        #expect(Backoff.delay(attempt: 10, base: 1, cap: 30, jitterRatio: 0, using: &rng) == 30)
    }

    @Test("抖动结果落在 [delay, delay*(1+ratio)] 区间")
    func jitterRange() {
        for _ in 0..<50 {
            let d = Backoff.delay(attempt: 3, base: 1, cap: 30, jitterRatio: 0.5)
            #expect(d >= 4.0 && d <= 6.0)
        }
    }

    @Test("attempt 最小按 1 处理")
    func attemptFloor() {
        var rng = FixedGenerator(value: 0)
        #expect(Backoff.delay(attempt: 0, base: 2, cap: 30, jitterRatio: 0, using: &rng) == 2)
    }
}
