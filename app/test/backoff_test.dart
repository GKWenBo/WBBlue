import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wb_ble_app/core/backoff.dart';

/// 固定返回值的随机源，让退避结果确定可断言。
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  group('backoffDelay', () {
    test('无抖动时指数增长：1,2,4,8…', () {
      Duration d(int a) =>
          backoffDelay(a, jitterRatio: 0, base: const Duration(seconds: 1));
      expect(d(1).inSeconds, 1);
      expect(d(2).inSeconds, 2);
      expect(d(3).inSeconds, 4);
      expect(d(4).inSeconds, 8);
    });

    test('封顶 cap 生效', () {
      final d = backoffDelay(10,
          jitterRatio: 0,
          base: const Duration(seconds: 1),
          cap: const Duration(seconds: 30));
      expect(d.inSeconds, 30);
    });

    test('attempt < 1 按 1 处理', () {
      expect(backoffDelay(0, jitterRatio: 0).inSeconds, 1);
    });

    test('抖动落在 [base, base*(1+jitter)] 区间', () {
      // random=0 → 无额外抖动；random=1 → 最大抖动
      final lo = backoffDelay(1,
          base: const Duration(seconds: 2),
          jitterRatio: 0.5,
          random: _FixedRandom(0));
      final hi = backoffDelay(1,
          base: const Duration(seconds: 2),
          jitterRatio: 0.5,
          random: _FixedRandom(1));
      expect(lo.inMilliseconds, 2000); // 2s * 1.0
      expect(hi.inMilliseconds, 3000); // 2s * 1.5
    });
  });
}
