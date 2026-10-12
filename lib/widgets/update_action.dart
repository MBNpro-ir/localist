import 'dart:async';
import 'package:flutter/material.dart';
import '../services/automatic_update_controller.dart';

Future<void> confirmLocalistUpdate(
  BuildContext context,
  AutomaticUpdateController updates, {
  bool refresh = true,
}) async {
  if (updates.promptOpen || updates.state == AutomaticUpdateState.installing) {
    return;
  }
  updates.promptOpen = true;
  try {
    if (refresh && !updates.busy) await updates.checkAndPrepare();
    if (!context.mounted || updates.state != AutomaticUpdateState.ready) return;
    updates.promptHandled = true;
    final fa = Localizations.maybeLocaleOf(context)?.languageCode == 'fa';
    final install = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(fa ? 'به‌روزرسانی آماده است' : 'Update ready'),
          content: Text(
            updates.windows
                ? (fa
                      ? 'نسخهٔ ${updates.check?.release.version} دانلود شده است. برای اعمال آن برنامه و جلسه‌ها بسته می‌شوند. اکنون نصب و ری‌استارت شود؟'
                      : 'Version ${updates.check?.release.version} is downloaded. Installing closes Localist and its sessions. Install and restart now?')
                : (fa
                      ? 'نسخهٔ ${updates.check?.release.version} دانلود شده است. می‌خواهید نصب شود؟'
                      : 'Version ${updates.check?.release.version} is downloaded. Install now?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(fa ? 'خیر، بعداً' : 'No, later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(fa ? 'بله' : 'Yes'),
            ),
          ],
        ),
      ),
    );
    if (install != true) {
      await updates.defer();
      return;
    }
    await updates.accept();
    await updates.installPreparedUpdate();
  } finally {
    updates.promptOpen = false;
  }
}

class LocalistUpdateAction extends StatefulWidget {
  const LocalistUpdateAction({
    super.key,
    required this.updates,
    required this.onPressed,
  });
  final AutomaticUpdateController updates;
  final VoidCallback onPressed;
  @override
  State<LocalistUpdateAction> createState() => _LocalistUpdateActionState();
}

class _LocalistUpdateActionState extends State<LocalistUpdateAction>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.updates,
    builder: (context, _) {
      final updates = widget.updates;
      final pulsing =
          updates.deferred &&
          updates.state == AutomaticUpdateState.ready &&
          !MediaQuery.disableAnimationsOf(context);
      if (pulsing && !_pulse.isAnimating) _pulse.repeat(reverse: true);
      if (!pulsing) {
        _pulse.stop();
        _pulse.value = 1;
      }
      if (!updates.visible) return const SizedBox.shrink();
      final ready = updates.state == AutomaticUpdateState.ready;
      final color = ready
          ? Colors.green
          : Theme.of(context).colorScheme.primary;
      return FadeTransition(
        opacity: Tween<double>(begin: .5, end: 1).animate(_pulse),
        child: IconButton(
          tooltip: Localizations.maybeLocaleOf(context)?.languageCode == 'fa'
              ? 'به‌روزرسانی'
              : 'Updates',
          onPressed: widget.onPressed,
          icon: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (updates.busy)
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    value: updates.state == AutomaticUpdateState.downloading
                        ? updates.progress
                        : null,
                    color: color,
                  ),
                Icon(
                  ready ? Icons.install_mobile : Icons.system_update_alt,
                  size: 21,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
