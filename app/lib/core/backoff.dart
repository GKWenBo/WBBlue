// 指数退避纯函数（第 7 课）。
//
// 自动重连必须退避：立即重试会加剧射频拥塞；多设备同时掉线时还会互相踩踏。
// 抖动（jitter）避免同批设备在同一时刻齐发重连（惊群效应）。
// 纯函数、随机源可注入——便于单元测试断言确定性区间。
import 'dart:math';

/// 计算第 [attempt] 次重试（从 1 起）前应等待的时长。
///
/// - 基础值：`base * 2^(attempt-1)`，封顶 `cap`；
/// - 抖动：在基础值上再乘 `1 + random(0..jitterRatio)`；
/// - [random] 可注入（0..1 的随机源），默认系统随机。
Duration backoffDelay(
  int attempt, {
  Duration base = const Duration(seconds: 1),
  Duration cap = const Duration(seconds: 30),
  double jitterRatio = 0.5,
  Random? random,
}) {
  final a = attempt < 1 ? 1 : attempt;
  // 指数用移位计算，先钳制指数防溢出
  final exponent = (a - 1).clamp(0, 30);
  final rawMs = base.inMilliseconds * (1 << exponent);
  final cappedMs = rawMs < cap.inMilliseconds ? rawMs : cap.inMilliseconds;
  if (jitterRatio <= 0) return Duration(milliseconds: cappedMs);
  final r = (random ?? Random()).nextDouble(); // 0..1
  final factor = 1 + r * jitterRatio;
  return Duration(milliseconds: (cappedMs * factor).round());
}
