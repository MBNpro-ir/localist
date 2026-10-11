import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' as engine;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/localist/connection_info.dart';

import '../services/feature_permission_service.dart';
import '../services/log_service.dart';
import 'embedded_remote_app.dart';

/// Stays mounted above every Localist page. Polling reconciles requests after
/// another Android Flutter engine temporarily owns the native event stream.
class AndroidRemoteHost extends StatefulWidget {
  const AndroidRemoteHost({super.key, required this.child});
  final Widget child;
  @override
  State<AndroidRemoteHost> createState() => _AndroidRemoteHostState();
}

class _AndroidRemoteHostState extends State<AndroidRemoteHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _polling = false;
  bool _dialogOpen = false;
  final _shown = <int>{};
  DialogRoute<bool>? _approvalRoute;
  int? _activeId;
  bool _checkingDialog = false;
  DateTime? _lastError;
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    localistLoginRequest = (_) => unawaited(_poll());
    _timer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(_poll());
      unawaited(_reconcileDialog());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (Platform.isAndroid) {
      localistLoginRequest = null;
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_polling ||
        _dialogOpen ||
        !mounted ||
        (_lifecycle != null && _lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _polling = true;
    try {
      await LocalistRemoteRuntime.ensureStarted();
      final clients = (jsonDecode(await bind.cmGetClientsState()) as List)
          .map((value) => Client.fromJson(value))
          .toList();
      _shown.retainAll(clients.map((c) => c.id));
      final capture = await FeaturePermissionService.instance.granted(
        FeatureAccess.screenCapture,
      );
      final pending = clients.where(
        (c) =>
            !c.disconnected &&
            !_shown.contains(c.id) &&
            (!c.authorized ||
                (!capture &&
                    !c.isFileTransfer &&
                    !c.isTerminal &&
                    !c.isViewCamera)),
      );
      final context =
          FeaturePermissionService.instance.navigatorKey.currentContext;
      if (pending.isEmpty || context == null || !context.mounted || !mounted) {
        return;
      }
      final client = pending.first;
      _activeId = client.id;
      _shown.add(client.id);
      _dialogOpen = true;
      final route = DialogRoute<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RemoteIncomingConsent(
          name: client.name,
          peerId: client.peerId,
          fileTransfer: client.isFileTransfer,
          camera: client.isViewCamera,
          onSharePassword: () async {
            final id = await bind.mainGetMyId();
            final password = await bind.mainGetTemporaryPassword();
            await const MethodChannel(
              'localist/remote',
            ).invokeMethod<bool>('shareConnection', {
              'text': RemoteConnectionInfo(
                id: id,
                password: password,
              ).toClipboardText(),
            });
          },
        ),
      );
      _approvalRoute = route;
      final accepted = await Navigator.of(context).push(route);
      _approvalRoute = null;
      // Do not authorize until Android has granted the required capability.
      var allow = accepted == true;
      if (allow && !client.isFileTransfer && !client.isTerminal) {
        allow = await FeaturePermissionService.instance.ensure([
          if (client.isViewCamera)
            FeatureAccess.camera
          else
            FeatureAccess.screenCapture,
        ]);
      }
      final current = (jsonDecode(await bind.cmGetClientsState()) as List)
          .map((v) => Client.fromJson(v))
          .where((c) => c.id == client.id);
      if (current.isNotEmpty && !current.first.authorized) {
        await bind.cmLoginRes(connId: client.id, res: allow);
      } else if (current.isNotEmpty && !allow) {
        await bind.cmCloseConnection(connId: client.id);
      }
      if (allow &&
          current.isNotEmpty &&
          !client.isFileTransfer &&
          !client.isTerminal &&
          !client.isViewCamera) {
        await engine.gFFI.invokeMethod('start_capture');
        // Viewing remains possible when the user declines optional input.
        // If control is needed, guide through restricted Android settings.
        await FeaturePermissionService.instance.ensure([
          FeatureAccess.remoteInput,
        ]);
      }
      await engine.gFFI.invokeMethod('cancel_notification', client.id);
    } catch (error) {
      // Startup/reconnection is transient. Retry, without dismissing consent
      // or accepting any request on a user's behalf.
      _shown.remove(_activeId);
      if (_lastError == null ||
          DateTime.now().difference(_lastError!).inSeconds > 30) {
        _lastError = DateTime.now();
        LogService.instance.warning(
          'Incoming remote request handling failed: $error',
        );
      }
    } finally {
      _activeId = null;
      _polling = false;
      _dialogOpen = false;
    }
  }

  Future<void> _reconcileDialog() async {
    final route = _approvalRoute;
    if (_checkingDialog || route == null || !route.isCurrent || !mounted) {
      return;
    }
    _checkingDialog = true;
    try {
      final clients = (jsonDecode(await bind.cmGetClientsState()) as List).map(
        (v) => Client.fromJson(v),
      );
      final current = clients.where(
        (c) => c.id == _activeId && !c.disconnected,
      );
      if (identical(_approvalRoute, route) &&
          route.isCurrent &&
          (current.isEmpty || current.first.authorized)) {
        route.navigator?.pop(current.isNotEmpty);
      }
    } catch (_) {
      /* Retry after a transient native reconnect. */
    } finally {
      _checkingDialog = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RemoteIncomingConsent extends StatelessWidget {
  const RemoteIncomingConsent({
    super.key,
    required this.name,
    required this.peerId,
    this.fileTransfer = false,
    this.camera = false,
    required this.onSharePassword,
  });
  final String name, peerId;
  final bool fileTransfer, camera;
  final Future<void> Function() onSharePassword;
  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.devices_rounded),
      title: Text(t('درخواست اتصال ورودی', 'Incoming connection request')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name · $peerId',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            fileTransfer
                ? t(
                    'این دستگاه می‌خواهد فایل منتقل کند.',
                    'This device wants to transfer files.',
                  )
                : camera
                ? t(
                    'این دستگاه می‌خواهد دوربین شما را ببیند.',
                    'This device wants to view your camera.',
                  )
                : t(
                    'این دستگاه درخواست دیدن و کنترل گوشی شما را داده است. فقط اگر شخص مقابل را می‌شناسید قبول کنید.',
                    'This device wants to view and control your phone. Accept only if you trust the person.',
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              'می‌توانید درخواست را قبول کنید یا رمز یک‌بارمصرف را برای او بفرستید. اگر بعداً رمز ثابت لازم داشتید، آن را در تنظیمات ← کنترل از راه دور ← امنیت تنظیم کنید.',
              'Accept this request or share your one-time password. You can set a permanent password later in Settings → Remote Control → Security.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSharePassword,
            icon: const Icon(Icons.share_outlined),
            label: Text(t('ارسال رمز یک‌بارمصرف', 'Share one-time password')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t('رد درخواست', 'Decline')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t('قبول اتصال', 'Accept connection')),
        ),
      ],
    );
  }
}
