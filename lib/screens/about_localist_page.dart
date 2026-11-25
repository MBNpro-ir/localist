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
    final animate = !MediaQuery.disableAnimationsOf(context);
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
          title: Text(fa ? 'دربارهٔ لوکالیست' : 'About Localist'),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final artwork = RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: animate && !simple ? 0 : 1, end: 1),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutCubic,
                  builder: (_, progress, _) => CustomPaint(
                    size: const Size(240, 172),
                    painter: _LocalistMark(colors, progress),
                  ),
                ),
              );
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

class _LocalistMark extends CustomPainter {
  const _LocalistMark(this.colors, this.progress);

  final ColorScheme colors;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.primary.withValues(alpha: .35 * progress);
    for (final angle in [-.40, .40]) {
      canvas.save();
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 210, height: 83),
        orbit,
      );
      canvas.drawCircle(
        const Offset(96, -15),
        4,
        Paint()..color = colors.primary.withValues(alpha: progress),
      );
      canvas.restore();
    }

    // Project a rotating cube and draw the visible faces from back to front.
    final turn = -.95 + .37 * progress;
    Offset project(double x, double y, double z) {
      final horizontal = x * math.cos(turn) + z * math.sin(turn);
      final depth = z * math.cos(turn) - x * math.sin(turn);
      final scale = 1 / (1 + (depth + y * .22) / 260);
      return Offset(horizontal, y + depth * .44) * scale;
    }

    final vertices = [
      for (final z in [-35.0, 35.0])
        for (final y in [-32.0, 32.0])
          for (final x in [-35.0, 35.0]) project(x, y, z),
    ];
    for (final (face, color) in [
      ([0, 1, 5, 4], colors.tertiaryContainer),
      ([0, 2, 6, 4], colors.primaryContainer),
      ([0, 1, 3, 2], colors.primary),
    ]) {
      final shape = Path()
        ..addPolygon([for (final i in face) vertices[i]], true);
      canvas.drawPath(shape, Paint()..color = color);
      canvas.drawPath(shape, orbit);
    }
  }

  @override
  bool shouldRepaint(covariant _LocalistMark oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.colors != colors;
}
