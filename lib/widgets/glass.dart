import 'dart:ui';

import 'package:flutter/material.dart';

const localistDesktopNavigationBreakpoint = 840.0;
const localistExpandedNavigationBreakpoint = 1380.0;

class LocalistVisualStyle extends InheritedWidget {
  const LocalistVisualStyle({
    super.key,
    required this.simple,
    required super.child,
  });

  final bool simple;

  static bool simpleOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<LocalistVisualStyle>()
            ?.simple ??
        false;
  }

  @override
  bool updateShouldNotify(LocalistVisualStyle oldWidget) {
    return simple != oldWidget.simple;
  }
}

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child, this.simple = false});

  final Widget child;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LocalistVisualStyle(
      simple: simple,
      child: simple
          ? ColoredBox(color: scheme.surface, child: child)
          : AnimatedContainer(
              duration: const Duration(milliseconds: 460),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                color: scheme.surface,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface,
                    scheme.primaryContainer.withValues(alpha: .22),
                    scheme.tertiaryContainer.withValues(alpha: .18),
                    scheme.surface,
                  ],
                ),
              ),
              child: child,
            ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final simple = LocalistVisualStyle.simpleOf(context);
    if (simple) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }
    final brightness = Theme.of(context).brightness;
    final fill = brightness == Brightness.dark ? Colors.black : Colors.white;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              color: fill.withValues(
                alpha: brightness == Brightness.dark ? .20 : .36,
              ),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .35),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions});

  final Widget title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (LocalistVisualStyle.simpleOf(context)) {
      return AppBar(
        title: title,
        actions: actions,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      );
    }
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AppBar(
          title: title,
          actions: actions,
          elevation: 0,
          centerTitle: false,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: .55),
        ),
      ),
    );
  }
}

class PageSurface extends StatelessWidget {
  const PageSurface({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final desktopNavigation =
            windowWidth >= localistDesktopNavigationBreakpoint;
        final horizontalPadding = constraints.maxWidth < 420
            ? 12.0
            : constraints.maxWidth < 900
            ? 18.0
            : 24.0;
        final usableWidth = constraints.maxWidth - (horizontalPadding * 2);
        final useColumns = usableWidth >= 1000 && children.length > 2;
        final maxContentWidth = useColumns ? 1400.0 : 760.0;
        final bottomPadding = desktopNavigation ? 88.0 : 112.0;

        Widget item(Widget child) {
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: child,
            ),
          );
        }

        Widget content;
        if (!useColumns) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final child in children) item(child)],
          );
        } else {
          final left = <Widget>[];
          final right = <Widget>[];
          for (var index = 1; index < children.length; index++) {
            (index.isOdd ? left : right).add(item(children[index]));
          }
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item(children.first),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: left,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: right,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        final scrollView = ScrollConfiguration(
          behavior: const _StableScrollBehavior(),
          child: SingleChildScrollView(
            key: key,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              bottomPadding,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: content,
              ),
            ),
          ),
        );
        return LocalistVisualStyle.simpleOf(context)
            ? scrollView
            : BackdropGroup(child: scrollView);
      },
    );
  }
}

class _StableScrollBehavior extends MaterialScrollBehavior {
  const _StableScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.wrapValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool wrapValue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final simple = LocalistVisualStyle.simpleOf(context);
    final decoration = BoxDecoration(
      color: simple
          ? scheme.surfaceContainerHighest
          : scheme.surface.withValues(alpha: .34),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: simple
            ? scheme.outlineVariant
            : scheme.outlineVariant.withValues(alpha: .26),
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: textTheme.titleMedium,
                  maxLines: wrapValue ? null : 1,
                  overflow: wrapValue
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: wrapValue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (simple) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      decoration: decoration,
      child: content,
    );
  }
}

class ServiceLockNotice extends StatelessWidget {
  const ServiceLockNotice({
    super.key,
    required this.message,
    this.icon = Icons.lock_outline,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnimatedNavIcon extends StatelessWidget {
  const AnimatedNavIcon({
    super.key,
    required this.icon,
    required this.selected,
  });

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 1 + value * .14,
          child: Transform.rotate(
            angle: value * .08,
            child: Icon(
              icon,
              color: Color.lerp(scheme.onSurfaceVariant, scheme.primary, value),
            ),
          ),
        );
      },
    );
  }
}

enum InAppNoticeTone { info, success, warning, error }

void showLocalistNotice(
  BuildContext context, {
  required String message,
  InAppNoticeTone tone = InAppNoticeTone.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onTap,
  String? actionLabel,
  IconData? actionIcon,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      buildLocalistNoticeSnackBar(
        context,
        message: message,
        tone: tone,
        icon: icon,
        duration: duration,
        onTap: onTap,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
      ),
    );
}

SnackBar buildLocalistNoticeSnackBar(
  BuildContext context, {
  required String message,
  InAppNoticeTone tone = InAppNoticeTone.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onTap,
  String? actionLabel,
  IconData? actionIcon,
}) {
  final simple = LocalistVisualStyle.simpleOf(context);
  final resolvedIcon = icon ?? _noticeIconForTone(tone);
  return SnackBar(
    duration: duration,
    behavior: SnackBarBehavior.floating,
    elevation: 0,
    backgroundColor: Colors.transparent,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
    padding: EdgeInsets.zero,
    content: _NoticeCard(
      message: message,
      tone: tone,
      icon: resolvedIcon,
      simple: simple,
      onTap: onTap,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.tone,
    required this.icon,
    required this.simple,
    this.onTap,
    this.actionLabel,
    this.actionIcon,
  });

  final String message;
  final InAppNoticeTone tone;
  final IconData icon;
  final bool simple;
  final VoidCallback? onTap;
  final String? actionLabel;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: _noticeFillColor(scheme, tone, simple: simple),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _noticeBorderColor(scheme, tone)),
        boxShadow: simple
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .16),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                _NoticeIconBox(icon: icon, tone: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                  ),
                ),
                if (actionLabel != null || actionIcon != null) ...[
                  const SizedBox(width: 10),
                  _NoticeAction(
                    label: actionLabel,
                    icon: actionIcon ?? Icons.arrow_forward,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: simple
          ? card
          : BackdropFilter.grouped(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: card,
            ),
    );
  }
}

class _NoticeIconBox extends StatelessWidget {
  const _NoticeIconBox({required this.icon, required this.tone});

  final IconData icon;
  final InAppNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _noticeAccentColor(scheme, tone).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _noticeAccentColor(scheme, tone)),
    );
  }
}

class _NoticeAction extends StatelessWidget {
  const _NoticeAction({required this.label, required this.icon});

  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .60),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          label == null ? 8 : 10,
          7,
          8,
          7,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(icon, size: 16, color: scheme.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}

IconData _noticeIconForTone(InAppNoticeTone tone) {
  return switch (tone) {
    InAppNoticeTone.info => Icons.info_outline,
    InAppNoticeTone.success => Icons.check_circle_outline,
    InAppNoticeTone.warning => Icons.warning_amber_outlined,
    InAppNoticeTone.error => Icons.error_outline,
  };
}

Color _noticeAccentColor(ColorScheme scheme, InAppNoticeTone tone) {
  return switch (tone) {
    InAppNoticeTone.info => scheme.primary,
    InAppNoticeTone.success => const Color(0xFF2E7D32),
    InAppNoticeTone.warning => const Color(0xFFB26A00),
    InAppNoticeTone.error => scheme.error,
  };
}

Color _noticeFillColor(
  ColorScheme scheme,
  InAppNoticeTone tone, {
  required bool simple,
}) {
  if (simple) {
    return scheme.surfaceContainerHighest;
  }
  return switch (tone) {
    InAppNoticeTone.info => scheme.surface.withValues(alpha: .78),
    InAppNoticeTone.success => scheme.surface.withValues(alpha: .78),
    InAppNoticeTone.warning => scheme.surface.withValues(alpha: .82),
    InAppNoticeTone.error => scheme.surface.withValues(alpha: .84),
  };
}

Color _noticeBorderColor(ColorScheme scheme, InAppNoticeTone tone) {
  return _noticeAccentColor(scheme, tone).withValues(alpha: .28);
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) {
    return '${value.round()} ${units[unit]}';
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}
