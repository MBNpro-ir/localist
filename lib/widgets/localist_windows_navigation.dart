import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'glass.dart';
import 'localist_bottom_navigation.dart';

class LocalistWindowsNavigation extends StatefulWidget {
  const LocalistWindowsNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
    this.showActionButton = false,
    this.actionIcon = Icons.query_stats,
    this.actionTooltip,
    this.onActionPressed,
  });

  static const collapsedWidth = 76.0;
  static const expandedWidth = 220.0;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LocalistBottomNavigationItem> items;
  final bool showActionButton;
  final IconData actionIcon;
  final String? actionTooltip;
  final VoidCallback? onActionPressed;

  @override
  State<LocalistWindowsNavigation> createState() =>
      _LocalistWindowsNavigationState();
}

class _LocalistWindowsNavigationState extends State<LocalistWindowsNavigation> {
  int? _hoveredIndex;

  bool get _expanded => _hoveredIndex != null;

  void _setHovered(int index) {
    if (_hoveredIndex == index) {
      return;
    }
    setState(() => _hoveredIndex = index);
  }

  void _clearHovered(PointerExitEvent event) {
    if (_hoveredIndex == null) {
      return;
    }
    setState(() => _hoveredIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    return MouseRegion(
      onExit: _clearHovered,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeInOutCubicEmphasized,
        width: _expanded
            ? LocalistWindowsNavigation.expandedWidth
            : LocalistWindowsNavigation.collapsedWidth,
        padding: EdgeInsets.symmetric(
          horizontal: _expanded ? 12 : 10,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            right: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .32),
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: .16),
            ],
          ),
          boxShadow: _expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 18,
                    offset: const Offset(5, 0),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < widget.items.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MouseRegion(
                          onEnter: (_) => _setHovered(index),
                          child: _buildDestination(
                            context,
                            widget.items[index],
                            index,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.showActionButton && widget.onActionPressed != null)
              MouseRegion(
                onEnter: (_) => _setHovered(widget.items.length),
                child: _buildAction(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestination(
    BuildContext context,
    LocalistBottomNavigationItem item,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final selected = widget.currentIndex == index;
    final hovered = _hoveredIndex == index;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final button = Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => widget.onDestinationSelected(index),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeInOutCubicEmphasized,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : hovered
                  ? scheme.primary.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // During the width animation the container can briefly be
                // narrower than its expanded padding. Keep the icon centered
                // until there is enough room for both the icon and a label.
                final horizontalPadding =
                    _expanded && constraints.maxWidth >= 48 ? 12.0 : 0.0;
                final availableWidth =
                    constraints.maxWidth - horizontalPadding * 2;
                final showLabel = _expanded && availableWidth >= 88;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: showLabel
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      AnimatedNavIcon(
                        icon: selected ? item.selectedIcon : item.icon,
                        selected: selected,
                        selectedColor: foreground,
                        unselectedColor: foreground,
                      ),
                      if (showLabel)
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            tween: Tween(begin: 0, end: 1),
                            builder: (context, opacity, child) {
                              return Opacity(opacity: opacity, child: child);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: foreground,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return _expanded ? button : Tooltip(message: item.label, child: button);
  }

  Widget _buildAction(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final hovered = _hoveredIndex == widget.items.length;
    final label = widget.actionTooltip ?? 'Stats';
    final button = Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onActionPressed,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeInOutCubicEmphasized,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: hovered
                  ? scheme.primary.withValues(alpha: .10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    _expanded && constraints.maxWidth >= 48 ? 12.0 : 0.0;
                final availableWidth =
                    constraints.maxWidth - horizontalPadding * 2;
                final showLabel = _expanded && availableWidth >= 88;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Row(
                    mainAxisAlignment: showLabel
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      AnimatedNavIcon(
                        icon: widget.actionIcon,
                        selected: false,
                        selectedColor: scheme.primary,
                        unselectedColor: scheme.primary,
                      ),
                      if (showLabel)
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            tween: Tween(begin: 0, end: 1),
                            builder: (context, opacity, child) {
                              return Opacity(opacity: opacity, child: child);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return _expanded ? button : Tooltip(message: label, child: button);
  }
}
