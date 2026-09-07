import 'package:flutter/material.dart';

import 'glass.dart';

class LocalistBottomNavigationItem {
  const LocalistBottomNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class LocalistBottomNavigationBar extends StatelessWidget {
  const LocalistBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
    this.showActionButton = false,
    this.actionIcon = Icons.query_stats,
    this.actionTooltip,
    this.onActionPressed,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LocalistBottomNavigationItem> items;
  final bool showActionButton;
  final IconData actionIcon;
  final String? actionTooltip;
  final VoidCallback? onActionPressed;

  static const double _gradientHeight = 144;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _gradientHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .42, .74, 1],
                  colors: [
                    Colors.transparent,
                    scheme.primary.withValues(alpha: .02),
                    scheme.primaryContainer.withValues(alpha: .07),
                    scheme.tertiary.withValues(alpha: .14),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showAction =
                      showActionButton && onActionPressed != null;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _LocalistNavigationPill(
                          currentIndex: currentIndex,
                          onDestinationSelected: onDestinationSelected,
                          items: items,
                        ),
                      ),
                      if (showAction) ...[
                        const SizedBox(width: 10),
                        _LocalistActionButton(
                          icon: actionIcon,
                          tooltip: actionTooltip,
                          onPressed: onActionPressed!,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalistNavigationPill extends StatelessWidget {
  const _LocalistNavigationPill({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LocalistBottomNavigationItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedIndex = currentIndex.clamp(0, items.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < items.length; index++)
                  _LocalistNavigationDestination(
                    item: items[index],
                    selected: index == selectedIndex,
                    onTap: () => onDestinationSelected(index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalistNavigationDestination extends StatelessWidget {
  const _LocalistNavigationDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LocalistBottomNavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 420);
    final content = AnimatedSize(
      duration: duration,
      curve: Curves.easeInOutCubicEmphasized,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .92, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: selected
            ? Row(
                key: ValueKey(item.label),
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedNavIcon(
                    icon: item.selectedIcon,
                    selected: true,
                    selectedColor: scheme.onPrimaryContainer,
                    unselectedColor: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : Text(
                item.label,
                key: const ValueKey('unselected'),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
    return Tooltip(
      message: item.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: onTap,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeInOutCubicEmphasized,
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 10 : 16,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalistActionButton extends StatelessWidget {
  const _LocalistActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: .22),
        shape: CircleBorder(
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 60,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .86, end: 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Icon(icon, color: scheme.onSurface, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
