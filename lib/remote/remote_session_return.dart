import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RemoteSessionReturnPage extends StatefulWidget {
  const RemoteSessionReturnPage({
    super.key,
    required this.navigatorKey,
    this.onClose,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<void> Function()? onClose;
  @override
  State<RemoteSessionReturnPage> createState() =>
      _RemoteSessionReturnPageState();
}

class _RemoteSessionReturnPageState extends State<RemoteSessionReturnPage> {
  Timer? _timer;
  bool _hadSession = false;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return;
      if (navigator.canPop()) {
        _hadSession = true;
      } else if (_hadSession) {
        unawaited(_close());
      }
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (widget.onClose != null) {
      await widget.onClose!();
    } else {
      await const MethodChannel('localist/remote').invokeMethod<bool>('close');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _close,
            child: Text(
              Localizations.localeOf(context).languageCode == 'fa'
                  ? 'برگشت به Localist'
                  : 'Return to Localist',
            ),
          ),
        ],
      ),
    ),
  );
}
