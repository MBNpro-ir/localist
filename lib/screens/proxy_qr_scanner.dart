import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_localizations.dart';
import '../models/service_state.dart';
import '../services/log_service.dart';

/// A mounted, bounded camera view also works on short Android 8/9 screens.
class ProxyQrScanner extends StatefulWidget {
  const ProxyQrScanner({super.key});
  @override
  State<ProxyQrScanner> createState() => _ProxyQrScannerState();
}

class _ProxyQrScannerState extends State<ProxyQrScanner>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    if (!mounted || _handled) return;
    LogService.instance.debug(
      'Proxy QR camera start requested handled=$_handled',
    );
    try {
      await _controller.start();
      LogService.instance.debug('Proxy QR camera started');
    } catch (error, stack) {
      LogService.instance.debug(
        'Proxy QR camera start failed type=${error.runtimeType}',
        stack: stack,
      );
      if (mounted) {
        setState(
          () => _error = context.l10n.isPersian
              ? 'دوربین باز نشد. دسترسی دوربین را بررسی کنید و دوباره تلاش کنید.'
              : 'Camera unavailable. Check camera permission and retry.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogService.instance.debug('Proxy QR lifecycle state=${state.name}');
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    LogService.instance.debug('Proxy QR scanner disposed handled=$_handled');
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.scanProxyQr),
    content: SizedBox(
      width: 360,
      height: MediaQuery.sizeOf(context).height.clamp(220, 640) * .48,
      child: MobileScanner(
        controller: _controller,
        errorBuilder: (context, error) => Center(
          child: Text(
            _error ??
                (context.l10n.isPersian
                    ? 'دوربین در دسترس نیست؛ دسترسی دوربین را بررسی کنید.'
                    : 'Camera unavailable. Check permission.'),
          ),
        ),
        onDetect: (capture) {
          if (_handled) return;
          if (LogService.instance.debugModeEnabled) {
            LogService.instance.debug(
              'Proxy QR scan callback barcodes=${capture.barcodes.length}',
            );
          }
          for (final code in capture.barcodes) {
            final value = code.rawValue;
            final smart = value == null
                ? null
                : SmartProxyPayload.tryParse(value);
            final remote = value == null
                ? null
                : RemoteProxyConfig.tryParse(value);
            if (smart == null && remote == null) {
              LogService.instance.debug(
                'Proxy QR scan ignored unrecognized code',
              );
              continue;
            }
            LogService.instance.debug(
              'Proxy QR scan accepted format=${smart != null ? 'smart' : 'remote'}',
            );
            _handled = true;
            Navigator.pop(context, value);
            break;
          }
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      TextButton(
        onPressed: () => unawaited(_start()),
        child: Text(context.l10n.isPersian ? 'تلاش مجدد' : 'Retry'),
      ),
    ],
  );
}
