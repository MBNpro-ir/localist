import 'dart:async';
import '../services/feature_activity_service.dart';
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
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.remoteControl,
      false,
    );
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
      FeatureActivityService.instance.setActive(
        this,
        LocalistFeature.remoteControl,
        clients.any((c) => !c.disconnected),
      );
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
                    !c.isPortForward &&
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
          networkTunnel: client.isPortForward,
          tunnelTarget: client.portForward,
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
      if (allow &&
          !client.isFileTransfer &&
          !client.isTerminal &&
          !client.isPortForward) {
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
          !client.isPortForward &&
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
    this.networkTunnel = false,
    this.tunnelTarget = '',
    required this.onSharePassword,
  });
  final String name, peerId;
  final bool fileTransfer, camera, networkTunnel;
  final String tunnelTarget;
  final Future<void> Function() onSharePassword;
  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    return AlertDialog(
      scrollable: true,
      icon: c