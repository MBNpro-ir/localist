import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_localizations.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/feature_permission_service.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';
import '../services/log_service.dart';

/// A mounted, bounded camera view also works on short Android 8/9 screens.
class LocalistQrScanner extends StatefulWidget {
  const LocalistQrScanner({
    super.key,
    required this.title,
    required this.accepts,
  });
  final String title;
  final bool Function(String) accepts;
  @override
  State<LocalistQrScanner> createState() => _LocalistQrScannerState();
}

class _LocalistQrScannerState extends State<LocalistQrScanner>
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
      'Localist QR camera start requested handled=$_handled',
    );
    try {
      await _controller.start();
      LogService.instance.debug('Localist QR camera started');
    } catch (error, stack) {
      LogService.instance.debug(
        'Localist QR camera start failed type=${error.runtimeType}',
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
    LogService.instance.debug('Localist QR lifecycle state=${state.name}');
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    LogService.instance.debug('Localist QR scanner disposed handled=$_handled');
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
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
              'Localist QR scan callback barcodes=${capture.barcodes.length}',
            );
          }
          for (final code in capture.barcodes) {
            final value = code.rawValue;
            if (value == null || !widget.accepts(value.trim())) continue;
            _handled = true;
            Navigator.pop(context, value.trim());
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

Future<String?> scanLocalistQr(
  BuildContext context, {
  required String title,
  required bool Function(String) accepts,
}) async {
  if (Platform.isWindows) {
    try {
      final device = await _chooseWindowsCameraDevice(context);
      if (device == null || !context.mounted) return null;
      return await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => _WindowsQrScannerPage(
            deviceName: device,
            title: title,
            accepts: accepts,
          ),
        ),
      );
    } catch (error) {
      LogService.instance.debug(
        'Windows QR scanner failed type=${error.runtimeType}',
      );
      if (context.mounted) {
        showLocalistNotice(
          context,
          message: context.l10n.scannerCouldNotStart,
          tone: InAppNoticeTone.warning,
        );
      }
      return null;
    }
  }
  if (!await FeaturePermissionService.instance.ensure([FeatureAccess.camera]) ||
      !context.mounted) {
    return null;
  }
  return showDialog<String>(
    context: context,
    builder: (_) => LocalistQrScanner(title: title, accepts: accepts),
  );
}

Future<String?> _chooseWindowsCameraDevice(BuildContext context) async {
  final devices = await NativeBridgeService.instance.getWindowsCameraDevices();
  LogService.instance.debug(
    'Windows camera devices loaded count=${devices.length}',
  );
  if (!context.mounted) {
    return null;
  }
  if (devices.isEmpty) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.scannerDevice),
        content: Text(context.l10n.useDefaultWindowsCamera),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('default'),
            child: Text(context.l10n.defaultCamera),
          ),
        ],
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.scannerDevice),
      children: [
        for (final device in devices)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(device),
            child: Text(device),
          ),
      ],
    ),
  );
}

class _WindowsQrScannerPage extends StatefulWidget {
  const _WindowsQrScannerPage({
    required this.deviceName,
    required this.title,
    required this.accepts,
  });

  final String deviceName;
  final String title;
  final bool Function(String) accepts;

  @override
  State<_WindowsQrScannerPage> createState() => _WindowsQrScannerPageState();
}

class _WindowsQrScannerPageState extends State<_WindowsQrScannerPage> {
  late final WebviewController _controller;
  late final Future<void> _initialized;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebviewController();
    _initialized = _initWebview();
  }

  @override
  void dispose() {
    _postClose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initWebview() async {
    await _controller.initialize();
    _controller.webMessage.listen(_handleWebMessage);
    await _controller.loadUrl(_scannerAssetUrl());
  }

  void _handleWebMessage(dynamic event) {
    if (_completed || !mounted || event is! Map) {
      return;
    }
    if (event['methodName'] != 'successCallback') {
      return;
    }
    final data = event['data'];
    if (data is! String || !widget.accepts(data.trim())) {
      return;
    }
    _completed = true;
    Navigator.of(context).pop(data.trim());
  }

  String _scannerAssetUrl() {
    final assetsDirectory =
        '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\packages\\simple_barcode_scanner\\assets\\barcode.html';
    return Uri.file(assetsDirectory).toString();
  }

  Future<WebviewPermissionDecision> _handlePermissionRequest(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async {
    if (kind == WebviewPermissionKind.camera) {
      return WebviewPermissionDecision.allow;
    }
    return WebviewPermissionDecision.none;
  }

  void _closeScanner() {
    _completed = true;
    _postClose();
    Navigator.of(context).pop();
  }

  void _postClose() {
    try {
      _controller.postWebMessage(json.encode({'event': 'close'}));
    } catch (_) {
      // The webview may not have finished initializing yet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        leading: IconButton(
          tooltip: context.l10n.closeScanner,
          onPressed: _closeScanner,
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 318,
                    width: double.infinity,
                    child: FutureBuilder<void>(
                      future: _initialized,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                context.l10n.scannerCouldNotStart,
                                style: TextStyle(color: scheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Webview(
                          _controller,
                          permissionRequested: _handlePermissionRequest,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.videocam_outlined),
                title: Text(context.l10n.scannerDevice),
                subtitle: Text(widget.deviceName),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _closeScanner,
                  icon: const Icon(Icons.close),
                  label: Text(context.l10n.closeScanner),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
