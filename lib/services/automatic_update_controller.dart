import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_update_service.dart';
import 'native_bridge_service.dart';
import 'feature_permission_service.dart';
import '../remote/embedded_remote_app.dart';

enum AutomaticUpdateState {
  idle,
  checking,
  current,
  downloading,
  preparing,
  ready,
  installing,
  failed,
}

/// One controller for startup notifications and Settings. No duplicate
/// downloads, and a prepared update survives closing the settings route.
class AutomaticUpdateController extends ChangeNotifier {
  AutomaticUpdateController({
    AppUpdateService? service,
    NativeBridgeService? bridge,
    bool? windows,
  }) : _service = service ?? AppUpdateService(),
       _bridge = bridge ?? NativeBridgeService.instance,
       windows = windows ?? Platform.isWindows;
  static final instance = AutomaticUpdateController();
  final AppUpdateService _service;
  final NativeBridgeService _bridge;
  final bool windows;
  AutomaticUpdateState state = AutomaticUpdateState.idle;
  AppUpdateCheck? check;
  File? package;
  String? bundle;
  String? error;
  int received = 0, total = 0;
  bool installPermissionNeeded = false;
  Future<void>? _running;
  String? _assetUrl;
  String? _automaticInstallUrl;
  bool get busy => {
    AutomaticUpdateState.checking,
    AutomaticUpdateState.downloading,
    AutomaticUpdateState.preparing,
    AutomaticUpdateState.installing,
  }.contains(state);
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
  void _state(AutomaticUpdateState value) {
    state = value;
    notifyListeners();
  }

  Future<void> checkAndPrepare() =>
      _running ??= _prepare().whenComplete(() => _running = null);
  Future<void> _prepare() async {
    if (state == AutomaticUpdateState.installing) return;
    error = null;
    _state(AutomaticUpdateState.checking);
    try {
      check = await _service.checkForUpdate();
      if (!check!.updateAvailable) {
        _state(AutomaticUpdateState.current);
        return;
      }
      final asset = windows ? check!.windowsAsset : check!.androidAsset;
      if (asset == null) {
        throw StateError('No update package supports this device.');
      }
      if (_assetUrl != asset.downloadUrl) {
        package = null;
        bundle = null;
        installPermissionNeeded = false;
        _automaticInstallUrl = null;
      }
      _assetUrl = asset.downloadUrl;
      // A completed download may already be prepared by the startup check.
      if (package != null && await package!.exists()) {
        try {
          await validateUpdateFile(package!, asset);
        } catch (_) {
          package = null;
          bundle = null;
        }
      }
      if (package == null) {
        received = 0;
        total = asset.size;
        _state(AutomaticUpdateState.downloading);
        void progress(int bytes, int size) {
          received = bytes;
          total = size;
          notifyListeners();
        }

        package = windows
            ? await _service.downloadWindowsUpdate(asset, onProgress: progress)
            : await _service.downloadAndroidUpdate(asset, onProgress: progress);
      }
      if (windows) {
        _state(AutomaticUpdateState.preparing);
        bundle = await _service.prepareWindowsUpdate(
          package!,
          check!.release.version,
        );
      }
      _state(AutomaticUpdateState.ready);
    } catch (e) {
      error = '$e';
      _state(AutomaticUpdateState.failed);
    }
  }

  Future<bool> installPreparedUpdate({bool automatic = false}) async {
    if (state != AutomaticUpdateState.ready || package == null) return false;
    if (automatic && _automaticInstallUrl == _assetUrl) return false;
    error = null;
    if (!windows && !await _bridge.canInstallAndroidPackages()) {
      installPermissionNeeded = true;
      notifyListeners();
      if (!Platform.isAndroid ||
          !await FeaturePermissionService.instance.ensure([
            FeatureAccess.installUpdates,
          ])) {
        return false;
      }
    }
    installPermissionNeeded = false;
    if (automatic) _automaticInstallUrl = _assetUrl;
    _state(AutomaticUpdateState.installing);
    try {
      bool started;
      if (windows) {
        await LocalistRemoteRuntime.stop();
        await _bridge.stopRootSharing();
        await _bridge.stopProxyService();
        started = await _bridge.startWindowsUpdate(
          archivePath: package!.path,
          version: check!.release.version.displayName,
          bundlePath: bundle,
        );
      } else {
        started = await _bridge.installAndroidApk(package!.path);
      }
      if (!started) {
        throw StateError(
          'The operating system could not start the update installer.',
        );
      }
      if (!windows) _state(AutomaticUpdateState.ready);
      return true;
    } catch (e) {
      error = '$e';
      _state(AutomaticUpdateState.ready);
      return false;
    }
  }
}
