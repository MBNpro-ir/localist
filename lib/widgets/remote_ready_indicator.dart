import 'package:flutter/material.dart';

class RemoteReadyIndicator extends StatefulWidget {
  const RemoteReadyIndicator({
    super.key,
    required this.ready,
    required this.online,
    required this.hosting,
    required this.server,
  });
  final bool ready, online, hosting;
  final String server;
  @override
  State<RemoteReadyIndicator> createState() => _RemoteReadyIndicatorState();
}

class _RemoteReadyIndicatorState extends State<RemoteReadyIndicator>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(RemoteReadyIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animate();
  }

  void _animate() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    final scheme = Theme.of(context).colorScheme;
    final available = widget.ready && widget.online && widget.hosting;
    final color = available ? scheme.primary : scheme.onSurfaceVariant;
    final text = !widget.ready
        ? (fa ? 'در حال آماده‌سازی' : 'Starting')
        : !widget.hosting
        ? (fa ? 'میزبانی متوقف است' : 'Hosting stopped')
        : !widget.online
        ? (fa ? 'در حال اتصال به سرور' : 'Connecting to server')
        : (fa ? 'آمادهٔ اتصال · Ready' : 'Ready');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: .08 + .14 * _pulse.value),
              ),
              child: child,
            ),
            child: Icon(
              available ? Icons.check_circle : Icons.sync,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  widget.server,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
