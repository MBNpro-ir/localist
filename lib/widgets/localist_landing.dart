import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class LocalistLanding extends StatelessWidget {
  const LocalistLanding({super.key, required this.onChooseDirection});

  final ValueChanged<bool> onChooseDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fa = context.l10n.isPersian;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxWidth < 620;
        final inset = compact ? 16.0 : 28.0;
        return SingleChildScrollView(
          padding: EdgeInsets.all(inset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, bounds.maxHeight - inset * 2),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: TweenAnimationBuilder<double>(
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 480),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0, end: 1),
                  builder: (_, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _NetworkPattern(colors),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 18 : 40,
                                  vertical: compact ? 34 : 50,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: colors.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Icon(
                                            Icons.devices_rounded,
                                            size: 34,
                                            color: colors.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Text(
                                        fa
                                            ? 'دستگاه‌هایت را به هم وصل کن'
                                            : 'Connect your devices',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        fa
                                            ? 'ارسال و دریافت فایل، رسانه و اتصال در یک‌جا'
                                            : 'Send and receive files, media, and connections in one place.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flex(
                        direction: compact ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          for (final receiving in [false, true])
                            if (compact)
                              _action(context, receiving, fa)
                            else
                              Expanded(child: _action(context, receiving, fa)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _action(BuildContext context, bool receiving, bool fa) {
    final icon = receiving
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final label = receiving
        ? (fa ? 'دریافت' : 'Receive')
        : (fa ? 'ارسال' : 'Send');
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(68),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );
    void activate() => onChooseDirection(receiving);
    return receiving
        ? FilledButton.tonalIcon(
            onPressed: activate,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          )
        : FilledButton.icon(
            onPressed: activate,
            icon: Icon(icon),
            label: Text(label),
            style: style,
          );
  }
}

class _NetworkPattern extends CustomPainter {
  const _NetworkPattern(this.colors);

  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .28);
    final ring = Paint()
      ..color = colors.primary.withValues(alpha: .14)
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = colors.primary.withValues(alpha: .42);
    for (final radius in [52.0, 86.0, 125.0, 170.0, 222.0, 282.0, 350.0]) {
      canvas.drawCircle(center, radius, ring);
      final angle = radius.toInt().isEven
          ? 3.22 + radius / 320
          : -.2 - radius / 380;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        radius < 150 ? 3 : 4,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_NetworkPattern oldDelegate) =>
      oldDelegate.colors != colors;
}
