import 'dart:math' as math;
import 'package:flutter/material.dart';

class CaptureLatencyChart extends StatelessWidget {
  const CaptureLatencyChart({
    super.key,
    required this.values,
    required this.video,
  });
  final List<double> values;
  final bool video;
  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(video ? Icons.videocam_outlined : Icons.mic_none, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  video
                      ? (fa ? 'تأخیر تخمینی تصویر' : 'Estimated video delay')
                      : (fa ? 'تأخیر تخمینی صدا' : 'Estimated audio delay'),
                ),
              ),
              Text(
                values.isEmpty
                    ? (fa ? '— میلی‌ثانیه' : '— ms')
                    : (fa
                          ? '${values.last.round()} میلی‌ثانیه'
                          : '${values.last.round()} ms'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _LatencyPainter(
                List.of(values),
                color,
                Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          if (values.isEmpty)
            Text(
              fa ? 'در انتظار اتصال گیرنده' : 'Waiting for a receiver',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _LatencyPainter extends CustomPainter {
  _LatencyPainter(this.values, this.color, this.grid);
  final List<double> values;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = grid
      ..strokeWidth = .5;
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }
    if (values.isEmpty) return;
    final maximum = math.max(10.0, values.reduce(math.max) * 1.2);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / 59;
      final y = size.height * (1 - values[i] / maximum);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LatencyPainter old) =>
      old.values != values || old.color != color;
}
