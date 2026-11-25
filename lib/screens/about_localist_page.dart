import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

class AboutLocalistPage extends StatelessWidget {
  const AboutLocalistPage({super.key, required this.simple});

  final bool simple;

  @override
  Widget build(BuildContext context) {
    final fa = context.l10n.isPersian;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final links = [
      (
        Icons.language_rounded,
        fa ? 'سایت لوکالیست' : 'Localist website',
        fa ? 'راهنما و اطلاعات پروژه' : 'Project information and guides',
        'https://localist.mbnpro.ir/',
      ),
      (
        Icons.code_rounded,
        'GitHub',
        fa ? 'سورس لوکالیست و گزارش مشکلات' : 'Localist source code and issues',
        'https://github.com/MBNpro-ir/localist',
      ),
      (
        Icons.hub_outlined,
        'PRS Hub',
        fa ? 'وب‌سایت تیم PRS' : 'The PRS team website',
        'https://prshub.ir/',
      ),
      (
        Icons.apps_rounded,
        'MBN Pro',
        fa
            ? 'مجموعهٔ محصولات و پروژه‌های MBN Pro'
            : 'Products and projects from MBN Pro',
        'https://mbnpro.ir/',
      ),
      (
        Icons.privacy_tip_outlined,
        fa ? 'حریم خصوصی' : 'Privacy policy',
        fa ? 'دسترسی‌ها و داده‌های برنامه' : 'App permissions and data use',
        'https://github.com/MBNpro-ir/localist/blob/master/PRIVACY.md',
      ),
    ];
    return GlassBackground(
      simple: simple,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          leading: ModalRoute.canPopOf(context) == true
              ? const BackButton()
              : null,
          title: Text(fa ? 'دربارهٔ لوکالیست' : 'About Localist'),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              const artwork = _TransferArrows();
              final introduction = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Localist',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fa
                        ? 'انتقال فایل و رسانه، کنترل از راه دور و اشتراک دوربین و میکروفون بین دستگاه‌ها.'
                        : 'Transfer files and media, connect remotely, and share your camera and microphone across devices.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    fa ? 'توسعهٔ PRS' : 'Developed by PRS',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ],
              );
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 28 : 14,
                  18,
                  wide ? 28 : 14,
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              colors: [
                                colors.surfaceContainerHigh,
                                colors.primaryContainer.withValues(alpha: .55),
                              ],
                            ),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(wide ? 32 : 20),
                            child: wide
                                ? Row(
                                    children: [
                                      Expanded(child: introduction),
                                      const SizedBox(width: 24),
                                      artwork,
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(child: artwork),
                                      introduction,
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final (icon, name, description, url) in links)
                              SizedBox(
                                width: wide
                                    ? (math.min(
                                                constraints.maxWidth - 56,
                                                1000,
                                              ) -
                                              12) /
                                          2
                                    : double.infinity,
                                child: Card.outlined(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    leading: Icon(icon, color: colors.primary),
                                    title: Text(name),
                                    subtitle: Text(description),
                                    trailing: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                    ),
                                    onTap: () async {
                                      final opened = await NativeBridgeService
                                          .instance
                                          .openUri(url);
                                      if (opened || !context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            fa
                                                ? 'مرورگر باز نشد.'
                                                : 'Could not open the browser.',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TransferArrows extends StatefulWidget {
  const _TransferArrows();

  @override
  State<_TransferArrows> createState() => _TransferArrowsState();
}

class _TransferArrowsState extends State<_TransferArrows>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(240, 172),
      painter: _TransferArrowsPainter(
        Theme.of(context).colorScheme,
        MediaQuery.disableAnimationsOf(context) ? null : _motion,
      ),
    ),
  );
}

class _TransferArrowsPainter extends CustomPainter {
  _TransferArrowsPainter(this.colors, this.motion) : super(repaint: motion);

  final ColorScheme colors;
  final Animation<double>? motion;

  static const _outline = [
    Offset(-55, -11),
    Offset(11, -11),
    Offset(11, -25),
    Offset(55, 0),
    Offset(11, 25),
    Offset(11, 11),
    Offset(-55, 11),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final scale = math.min(size.width / 240, size.height / 172);
    canvas.scale(scale);
    final phase = (motion?.value ?? 0) * 2 * math.pi;
    final slide = 6 * math.sin(phase);
    final float = 3 * math.cos(phase);
    _paintArrow(
      canvas,
      center: Offset(-31 + slide, -30 + float),
      heading: 1,
      yaw: .38 + .13 * math.sin(phase),
      pitch: .41 + .07 * math.cos(phase),
      color: colors.primary,
    );
    _paintArrow(
      canvas,
      center: Offset(31 - slide, 29 - float),
      heading: -1,
      yaw: .38 - .13 * math.sin(phase),
      pitch: .41 - .07 * math.cos(phase),
      color: colors.tertiary,
    );
  }

  void _paintArrow(
    Canvas canvas, {
    required Offset center,
    required double heading,
    required double yaw,
    required double pitch,
    required Color color,
  }) {
    final cosYaw = math.cos(yaw);
    final sinYaw = math.sin(yaw);
    final cosPitch = math.cos(pitch);
    final sinPitch = math.sin(pitch);

    (Offset, double) project(Offset point, double z) {
      final x = point.dx * heading;
      final y = point.dy;
      final rotatedX = x * cosYaw + z * sinYaw;
      final yawDepth = -x * sinYaw + z * cosYaw;
      final rotatedY = y * cosPitch - yawDepth * sinPitch;
      final depth = y * sinPitch + yawDepth * cosPitch;
      return (
        center + Offset(rotatedX, rotatedY) * (320 / (320 - depth)),
        depth,
      );
    }

    final front = [for (final point in _outline) project(point, 8)];
    final back = [for (final point in _outline) project(point, -8)];
    final frontShape = Path()
      ..addPolygon([for (final (point, _) in front) point], true);
    canvas.drawPath(
      frontShape.shift(const Offset(-4, 10)),
      Paint()
        ..color = colors.shadow.withValues(alpha: .38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Draw the extruded edges by depth before painting the lit front surface.
    final edges = List.generate(_outline.length, (index) {
      final next = (index + 1) % _outline.length;
      final vertices = [front[index], front[next], back[next], back[index]];
      final depth = vertices.fold(0.0, (value, vertex) => value + vertex.$2);
      final edge = _outline[next] - _outline[index];
      final shade = .30 + .20 * math.max(0, edge.dx / edge.distance);
      return (
        Path()..addPolygon([for (final (point, _) in vertices) point], true),
        depth,
        Color.lerp(color, colors.surface, shade)!,
      );
    })..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (shape, _, edgeColor) in edges) {
      canvas.drawPath(shape, Paint()..color = edgeColor);
    }

    canvas.drawPath(
      frontShape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .34)!,
            color,
            Color.lerp(color, colors.surface, .14)!,
          ],
        ).createShader(frontShape.getBounds()),
    );
    canvas.drawPath(
      frontShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..color = Colors.white.withValues(alpha: .36),
    );
  }

  @override
  bool shouldRepaint(covariant _TransferArrowsPainter oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.colors != colors;
}
