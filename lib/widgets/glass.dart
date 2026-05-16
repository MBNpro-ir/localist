import 'dart:ui';

import 'package:flutter/material.dart';

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
          child: Padding(padding: padding, child: child),
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
            child: Padding(padding: padding, child: child),
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
    final list = ScrollConfiguration(
      behavior: const _StableScrollBehavior(),
      child: ListView(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
        children: [
          for (final child in children)
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: child,
              ),
            ),
        ],
      ),
    );
    return LocalistVisualStyle.simpleOf(context)
        ? list
        : BackdropGroup(child: list);
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
