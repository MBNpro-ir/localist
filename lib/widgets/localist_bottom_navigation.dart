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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final showAction = showActionButton && onActionPressed != null;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _LocalistNavigationPill(
                  currentIndex: currentIndex,
                  onDestinationSelected: onDestinationSelected,
                  items: items,
                  compact: compact,
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
    );
  }
}

class _LocalistNavigationPill extends StatelessWidget {
  const _LocalistNavigationPill({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.items,
    required this.compact,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LocalistBottomNavigationItem> items;
  final bool compact;

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
                    compact: compact,
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
    required this.compact,
    required this.onTap,
  });

  final LocalistBottomNavigationItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconOnly = !selected && compact;
    final representation = selected
        ? 'selected'
        : iconOnly
        ? 'icon'
        : 'label';
    final content = Row(
      key: ValueKey(representation),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected)
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.onPrimaryContainer.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: AnimatedNavIcon(
                icon: item.selectedIcon,
                selected: true,
                selectedColor: scheme.onPrimaryContainer,
                unselectedColor: scheme.onPrimaryContainer,
              ),
            ),
          )
        else if (iconOnly)
          AnimatedNavIcon(
            icon: item.icon,
            selected: false,
            selectedColor: scheme.onPrimaryContainer,
            unselectedColor: scheme.onSurfaceVariant,
          ),
        if (selected || !compact) ...[
          if (selected) const SizedBox(width: 8),
          Text(
            item.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ],
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
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              padding: EdgeInsets.symmetric(
                horizontal: selected
                    ? 10
                    : iconOnly
                    ? 13
                    : 15,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .88,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: content,
              ),
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
                duration: const Duration(milliseconds: 360),
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
