import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';
import 'windows_localist_service.dart';

class NativeBridgeService {
  NativeBridgeService._();

  static final NativeBridgeService instance = NativeBridgeService._();
  static const MethodChannel _channel = MethodChannel('com.prs.localist.vpn');

  Future<bool> ensureVpnPermission() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.ensureVpnPermission();
    }
    return await _channel.invokeMethod<bool>('ensureVpnPermission') ?? false;
  }

  Future<bool> startProxyService({
    required Set<ProxyProtocol> protocols,
    required Map<ProxyProtocol, int> ports,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
  }) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startProxyService(
        protocols: protocols,
        ports: ports,
        shareAllRoutes: shareAllRoutes,
        selectedLocalIps: selectedLocalIps,
      );
    }
    return await _channel.invokeMethod<bool>('startProxyService', {
          'protocols': protocols.map((protocol) => protocol.name).toList(),
          'ports': {
            for (final entry in ports.entries) entry.key.name: entry.value,
          },
          'shareAllRoutes': shareAllRoutes,
          'selectedLocalIps': selectedLocalIps.toList(),
        }) ??
        false;
  }

  Future<bool> startReceivingVpn(RemoteProxyConfig config) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.startReceivingVpn(config);
    }
    return await _channel.invokeMethod<bool>(
          'startReceivingVpn',
          config.toMap(),
        ) ??
        false;
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
    return await _channel.invokeMethod<bool>('startLocalProxy', {
          ...config.toMap(),
          'localPort': localPort,
        }) ??
        false;
  }

  Future<bool> checkRootAccess() async {
    if (Platform.isWindows) {
      final result = await WindowsLocalistService.instance.checkAdminAccess();
      return result.available;
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'checkRootAccess',
    );
    return result?['available'] == true;
  }

  Future<RootRoutingInfo> setRootRoutingEnabled(bool enabled) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.setRootRoutingEnabled(enabled);
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'setRootRoutingEnabled',
      {'enabled': enabled},
    );
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
    final result = await _channel
        .invokeMapMethod<Object?, Object?>('startRootSharing', {
          'shareAllRoutes': shareAllRoutes,
          'selectedLocalIps': selectedLocalIps.toList(),
        });
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<RootRoutingInfo> stopRootSharing() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.stopRootSharing();
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'stopRootSharing',
    );
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<bool> stopProxyService() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.stopProxyService();
    }
    return await _channel.invokeMethod<bool>('stopProxyService') ?? false;
  }

  Future<bool> shareApk() async {
    if (Platform.isWindows) {
      return false;
    }
    return await _channel.invokeMethod<bool>('shareApk') ?? false;
  }

  Future<bool> shareText({required String text, required String title}) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.shareText(
        text: text,
        title: title,
      );
    }
    return await _channel.invokeMethod<bool>('shareText', {
          'text': text,
          'title': title,
        }) ??
        false;
  }

  Future<bool> openUri(String uri) async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.openUri(uri);
    }
    return await _channel.invokeMethod<bool>('openUri', {'uri': uri}) ?? false;
  }

  Future<bool> openHotspotSettings() async {
    if (Platform.isWindows) {
      return false;
    }
    return await _channel.invokeMethod<bool>('openHotspotSettings') ?? false;
  }

  Future<UsageStats> getStats() async {
    if (Platform.isWindows) {
      return WindowsLocalistService.instance.getStats();
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>('getStats');
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
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getServiceState',
    );
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
}
