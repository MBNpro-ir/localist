import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';
import 'log_service.dart';
import 'localist_discovery_protocol.dart';
import 'windows_localist_service.dart';

class NativeBridgeService {
  NativeBridgeService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final NativeBridgeService instance = NativeBridgeService._();
  static const MethodChannel _channel = MethodChannel('com.prs.localist.vpn');
  final LogService _logs = LogService.instance;
  final StreamController<List<QuickSendSharedFile>> _sharedFilesController =
      StreamController<List<QuickSendSharedFile>>.broadcast();
  final StreamController<void> _localOnlyHotspotStoppedController =
      StreamController<void>.broadcast();

  Stream<List<QuickSendSharedFile>> get sharedQuickSendFiles =>
      _sharedFilesController.stream;
  Stream<void> get localOnlyHotspotStopped =>
      _localOnlyHotspotStoppedController.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'quickSendSharedFiles') {
      final files = _sharedFilesFromNative(call.arguments);
      if (files.isNotEmpty) {
        _logs.debug(
          'Received ${files.length} externally shared Quick Send files.',
        );
        _sharedFilesController.add(files);
      }
      return;
    }
    if (call.method == 'localOnlyHotspotStopped') {
      _logs.info('Android local-only hotspot stopped.');
      _localOnlyHotspotStoppedController.add(null);
      return;
    }
    if (call.method != 'nativeLog') {
      _logs.debug('Unknown native callback method=${call.method}');
      return;
    }
    final arguments = call.arguments;
    final message = arguments is Map
        ? arguments['message']?.toString() ?? ''
        : arguments.toString();
    final source = arguments is Map
        ? arguments['source']?.toString() ?? 'android'
        : 'android';
    if (message.isEmpty) {
      return;
    }
    _logs.debug('Android native [$source]: $message');
  }

  Future<bool> ensureVpnPermission() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.ensureVpnPermission();
    }
    return await _invoke<bool>('ensureVpnPermission') ?? false;
  }

  Future<int?> getAndroidSdkInt() async {
    if (!Platform.isAndroid) {
      return null;
    }
    return _invoke<int>('getAndroidSdkInt');
  }

  Future<List<String>> getAndroidSupportedAbis() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    return await _invokeList<String>('getAndroidSupportedAbis') ?? const [];
  }

  Future<String?> getAndroidUpdateDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }
    return _invoke<String>('getUpdateDirectory');
  }

  Future<bool> canInstallAndroidPackages() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('canInstallPackages') ?? false;
  }

  Future<bool> openAndroidInstallPermissionSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('openInstallPermissionSettings') ?? false;
  }

  Future<bool> installAndroidApk(String path) async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('installApk', {'path': path}) ?? false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return await _invoke<bool>('requestIgnoreBatteryOptimizations') ?? false;
  }

  Future<bool> startProxyService({
    required Set<ProxyProtocol> protocols,
    required Map<ProxyProtocol, int> ports,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
    RemoteProxyConfig? upstreamProxy,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startProxyService(
        protocols: protocols,
        ports: ports,
        shareAllRoutes: shareAllRoutes,
        selectedLocalIps: selectedLocalIps,
        upstreamProxy: upstreamProxy,
      );
    }
    final discoveryDeviceId = await localistDiscoveryDeviceId();
    return await _invoke<bool>('startProxyService', {
          'protocols': protocols.map((protocol) => protocol.name).toList(),
          'ports': {
            for (final entry in ports.entries) entry.key.name: entry.value,
          },
          'shareAllRoutes': shareAllRoutes,
          'selectedLocalIps': selectedLocalIps.toList(),
          'discoveryDeviceId': discoveryDeviceId,
        }) ??
        false;
  }

  Future<bool> startReceivingVpn(RemoteProxyConfig config) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startReceivingVpn(config);
    }
    return await _invoke<bool>('startReceivingVpn', config.toMap()) ?? false;
  }

  Future<bool> startLocalProxy(
    RemoteProxyConfig config, {
    int localPort = 3781,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startLocalProxy(
        config,
        localPort: localPort,
      );
    }
    return await _invoke<bool>('startLocalProxy', {
          ...config.toMap(),
          'localPort': localPort,
        }) ??
        false;
  }

  Future<bool> startSystemProxy(
    RemoteProxyConfig config, {
    int localPort = 3781,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startSystemProxy(
        config,
        localPort: localPort,
      );
    }
    return false;
  }

  Future<bool> checkRootAccess() async {
    if (Platform.isWindows) {
      final result = await WindowsLocalistService.instance.checkAdminAccess();
      return result.available;
    }
    final result = await _invokeMap<Object?, Object?>('checkRootAccess');
    return result?['available'] == true;
  }

  Future<RootRoutingInfo> setRootRoutingEnabled(bool enabled) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.setRootRoutingEnabled(enabled);
    }
    final result = await _invokeMap<Object?, Object?>('setRootRoutingEnabled', {
      'enabled': enabled,
    });
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<RootRoutingInfo> startRootSharing({
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startRootSharing(
        shareAllRoutes: shareAllRoutes,
        selectedLocalIps: selectedLocalIps,
      );
    }
    final result = await _invokeMap<Object?, Object?>('startRootSharing', {
      'shareAllRoutes': shareAllRoutes,
      'selectedLocalIps': selectedLocalIps.toList(),
    });
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<RootRoutingInfo> stopRootSharing() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.stopRootSharing();
    }
    final result = await _invokeMap<Object?, Object?>('stopRootSharing');
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<bool> stopProxyService() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.stopProxyService();
    }
    return await _invoke<bool>('stopProxyService') ?? false;
  }

  Future<bool> shareApk() async {
    if (Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('shareApk') ?? false;
  }

  Future<bool> shareText({required String text, required String title}) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.shareText(
        text: text,
        title: title,
      );
    }
    return await _invoke<bool>('shareText', {'text': text, 'title': title}) ??
        false;
  }

  Future<bool> openUri(String uri) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.openUri(uri);
    }
    return await _invoke<bool>('openUri', {'uri': uri}) ?? false;
  }

  Future<bool> openFile(String path) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('openFile', {'path': path}) ?? false;
  }

  Future<bool> shareFileExternally(String path) async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('shareFileExternally', {'path': path}) ?? false;
  }

  Future<bool> openContainingFolder(String path) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('openContainingFolder', {'path': path}) ?? false;
  }

  Future<bool> openLocalistFolder() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('openLocalistFolder') ?? false;
  }

  Future<List<QuickSendSharedFile>> takeQuickSendSharedFiles() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    final raw =
        await _invoke<List<Object?>>('takeQuickSendSharedFiles') ??
        const <Object?>[];
    return _sharedFilesFromNative(raw);
  }

  Future<bool> hasQuickSendSharedFiles() async {
    if (!Platform.isAndroid) {
      return false;
    }
    return await _invoke<bool>('hasQuickSendSharedFiles') ?? false;
  }

  Future<bool> startWindowsUpdate({
    required String archivePath,
    required String version,
  }) async {
    if (!Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('startWindowsUpdate', {
          'archivePath': archivePath,
          'version': version,
        }) ??
        false;
  }

  Future<bool> openHotspotSettings() async {
    if (Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('openHotspotSettings') ?? false;
  }

  Future<LocalOnlyHotspotInfo> startLocalOnlyHotspot() async {
    if (!Platform.isAndroid) {
      return const LocalOnlyHotspotInfo.unsupported();
    }
    final result = await _invokeMap<Object?, Object?>('startLocalOnlyHotspot');
    return LocalOnlyHotspotInfo.fromMap(result ?? const {});
  }

  Future<bool> stopLocalOnlyHotspot() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return await _invoke<bool>('stopLocalOnlyHotspot') ?? false;
  }

  Future<bool> showWindowsMessage({
    required String title,
    required String message,
    bool warning = true,
  }) async {
    if (!Platform.isWindows) {
      return false;
    }
    return await _invoke<bool>('showWindowsMessage', {
          'title': title,
          'message': message,
          'warning': warning,
        }) ??
        false;
  }

  Future<SavedTextFileResult> saveTextFile({
    required String text,
    required String suggestedName,
    String mimeType = 'text/plain',
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const SavedTextFileResult(saved: false);
    }
    final result = await _invokeMap<Object?, Object?>('saveTextFile', {
      'text': text,
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
    return SavedTextFileResult.fromMap(result ?? const {});
  }

  Future<Map<String, Object?>> getDeviceDetails() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const {};
    }
    final result = await _invokeMap<Object?, Object?>('getDeviceDetails');
    return {
      for (final entry in (result ?? const {}).entries)
        entry.key.toString(): entry.value,
    };
  }

  Future<bool> setQuickSendMulticastLock(bool enabled) async {
    if (!Platform.isAndroid) {
      return true;
    }
    return await _invoke<bool>('setQuickSendMulticastLock', {
          'enabled': enabled,
        }) ??
        false;
  }

  Future<String> getPublicStorageRoot() async {
    if (!Platform.isAndroid) {
      return '';
    }
    return await _invoke<String>('getPublicStorageRoot') ?? '';
  }

  Future<UsageStats> getStats() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.getStats();
    }
    final result = await _invokeMap<Object?, Object?>('getStats');
    return UsageStats.fromMap(result ?? const {});
  }

  Future<ServiceSnapshot> getServiceState({
    required ProxyProtocol fallbackProtocol,
    required int fallbackPort,
    required Map<ProxyProtocol, int> fallbackPorts,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.getServiceState(
        fallbackProtocol: fallbackProtocol,
        fallbackPort: fallbackPort,
        fallbackPorts: fallbackPorts,
      );
    }
    final result = await _invokeMap<Object?, Object?>('getServiceState');
    return ServiceSnapshot.fromMap(
      result ?? const {},
      fallbackProtocol: fallbackProtocol,
      fallbackPort: fallbackPort,
      fallbackPorts: fallbackPorts,
    );
  }

  Future<List<String>> getWindowsCameraDevices() async {
    if (!Platform.isWindows) {
      return const [];
    }
    return WindowsLocalistService.instance.getCameraDevices();
  }

  Future<String?> getWindowsSettingsSignature() async {
    if (!Platform.isWindows) {
      return null;
    }
    return WindowsLocalistService.instance.getWindowsSettingsSignature();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    final started = DateTime.now();
    _logs.debug(
      'NativeBridge -> $method platform=${Platform.operatingSystem} args=${_short(arguments)}',
    );
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      _logs.debug(
        'NativeBridge <- $method result=${_short(result)} elapsedMs=${DateTime.now().difference(started).inMilliseconds}',
      );
      return result;
    } catch (error, stack) {
      _logs.debug('NativeBridge !! $method failed', error: error, stack: stack);
      rethrow;
    }
  }

  Future<List<T>?> _invokeList<T>(String method, [Object? arguments]) async {
    final started = DateTime.now();
    _logs.debug(
      'NativeBridge -> $method platform=${Platform.operatingSystem} args=${_short(arguments)}',
    );
    try {
      final result = await _channel.invokeListMethod<T>(method, arguments);
      _logs.debug(
        'NativeBridge <- $method result=${_short(result)} elapsedMs=${DateTime.now().difference(started).inMilliseconds}',
      );
      return result;
    } catch (error, stack) {
      _logs.debug('NativeBridge !! $method failed', error: error, stack: stack);
      rethrow;
    }
  }

  Future<Map<K, V>?> _invokeMap<K, V>(
    String method, [
    Object? arguments,
  ]) async {
    final started = DateTime.now();
    _logs.debug(
      'NativeBridge -> $method platform=${Platform.operatingSystem} args=${_short(arguments)}',
    );
    try {
      final result = await _channel.invokeMapMethod<K, V>(method, arguments);
      _logs.debug(
        'NativeBridge <- $method result=${_short(result)} elapsedMs=${DateTime.now().difference(started).inMilliseconds}',
      );
      return result;
    } catch (error, stack) {
      _logs.debug('NativeBridge !! $method failed', error: error, stack: stack);
      rethrow;
    }
  }

  String _short(Object? value) {
    final text = value.toString();
    return text.length <= 360 ? text : '${text.substring(0, 360)}...';
  }

  List<QuickSendSharedFile> _sharedFilesFromNative(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map(QuickSendSharedFile.fromMap)
        .where((file) => file.path.isNotEmpty)
        .toList(growable: false);
  }
}

class LocalOnlyHotspotInfo {
  const LocalOnlyHotspotInfo({
    required this.supported,
    required this.active,
    required this.managed,
    required this.ssid,
    required this.password,
    required this.addresses,
    required this.primaryAddress,
    required this.errorCode,
    required this.message,
    required this.permissionRequired,
  });

  const LocalOnlyHotspotInfo.unsupported()
    : supported = false,
      active = false,
      managed = false,
      ssid = '',
      password = '',
      addresses = const [],
      primaryAddress = '',
      errorCode = 'unsupported',
      message = 'Local-only hotspot is unavailable on this platform.',
      permissionRequired = false;

  final bool supported;
  final bool active;
  final bool managed;
  final String ssid;
  final String password;
  final List<String> addresses;
  final String primaryAddress;
  final String errorCode;
  final String message;
  final bool permissionRequired;

  factory LocalOnlyHotspotInfo.fromMap(Map<Object?, Object?> map) {
    final rawAddresses = map['addresses'];
    return LocalOnlyHotspotInfo(
      supported: map['supported'] == true,
      active: map['active'] == true,
      managed: map['managed'] == true,
      ssid: map['ssid']?.toString().trim() ?? '',
      password: map['password']?.toString() ?? '',
      addresses: rawAddresses is Iterable
          ? rawAddresses
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false)
          : const [],
      primaryAddress: map['primaryAddress']?.toString().trim() ?? '',
      errorCode: map['errorCode']?.toString().trim() ?? '',
      message: map['message']?.toString().trim() ?? '',
      permissionRequired: map['permissionRequired'] == true,
    );
  }
}

class QuickSendSharedFile {
  const QuickSendSharedFile({required this.path, required this.name});

  final String path;
  final String name;

  factory QuickSendSharedFile.fromMap(Map value) {
    return QuickSendSharedFile(
      path: value['path']?.toString().trim() ?? '',
      name: value['name']?.toString().trim() ?? '',
    );
  }
}

class SavedTextFileResult {
  const SavedTextFileResult({
    required this.saved,
    this.canceled = false,
    this.path,
  });

  final bool saved;
  final bool canceled;
  final String? path;

  factory SavedTextFileResult.fromMap(Map<Object?, Object?> map) {
    return SavedTextFileResult(
      saved: map['saved'] == true,
      canceled: map['canceled'] == true,
      path: map['path']?.toString(),
    );
  }
}
