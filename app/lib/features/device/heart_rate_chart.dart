import 'package:flutter/material.dart';

/// 实时心率曲线（第 5 课）：CustomPaint 自绘折线，零图表依赖。
/// Y 轴按数据 min/max 自适应留边，X 轴固定样本容量从右侧滚入。
class HeartRateChart extends StatelessWidget {
  const HeartRateChart({
    super.key,
    required this.samples,
    required this.currentBpm,
    this.capacity = 120,
  });

  final List<int> samples;
  final int? currentBpm;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Text('实时心率', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  currentBpm == null ? '--' : '$currentBpm BPM',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: scheme.error),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              width: double.infinity,
              child: CustomPaint(
                painter: _HrPainter(
                  samples: samples,
                  capacity: capacity,
                  lineColor: scheme.error,
                  gridColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HrPainter extends CustomPainter {
  _HrPainter({
    required this.samples,
    required this.capacity,
    required this.lineColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<int> samples;
  final int capacity;
  final Color lineColor;
  final Color gridColor;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    // Y 轴范围：数据 min/max 各留 10 边距，避免曲线贴边
    var lo = samples.reduce((a, b) => a < b ? a : b) - 10;
    var hi = samples.reduce((a, b) => a > b ? a : b) + 10;
    if (hi - lo < 20) hi = lo + 20;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), grid);
    canvas.drawLine(
        Offset(0, size.height), Offset(size.width, size.height), grid);

    double x(int i) => size.width * i / (capacity - 1);
    double y(int bpm) => size.height * (1 - (bpm - lo) / (hi - lo));

    final path = Path()..moveTo(x(0), y(samples[0]));
    for (var i = 1; i < samples.length; i++) {
      path.lineTo(x(i), y(samples[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // 最新样本点
    canvas.drawCircle(
      Offset(x(samples.length - 1), y(samples.last)),
      3,
      Paint()..color = lineColor,
    );

    _drawLabel(canvas, '$hi', Offset(4, 0));
    _drawLabel(canvas, '$lo', Offset(4, size.height - 14));
  }

  void _drawLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _HrPainter old) =>
      old.samples.length != samples.length ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last != samples.last);
}
