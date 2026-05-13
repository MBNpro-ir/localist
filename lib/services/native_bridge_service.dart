import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';

class NativeBridgeService {
  NativeBridgeService._();

  static final NativeBridgeService instance = NativeBridgeService._();
  static const MethodChannel _channel = MethodChannel('com.prs.localist.vpn');

  Future<bool> ensureVpnPermission() async {
    return await _channel.invokeMethod<bool>('ensureVpnPermission') ?? false;
  }

  Future<bool> startProxyService({
    required Set<ProxyProtocol> protocols,
    required Map<ProxyProtocol, int> ports,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
  }) async {
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
    return await _channel.invokeMethod<bool>('startLocalProxy', {
          ...config.toMap(),
          'localPort': localPort,
        }) ??
        false;
  }

  Future<bool> checkRootAccess() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'checkRootAccess',
    );
    return result?['available'] == true;
  }

  Future<RootRoutingInfo> setRootRoutingEnabled(bool enabled) async {
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
    final result = await _channel
        .invokeMapMethod<Object?, Object?>('startRootSharing', {
          'shareAllRoutes': shareAllRoutes,
          'selectedLocalIps': selectedLocalIps.toList(),
        });
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<RootRoutingInfo> stopRootSharing() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'stopRootSharing',
    );
    return RootRoutingInfo.fromMap(result ?? const {});
  }

  Future<bool> stopProxyService() async {
    return await _channel.invokeMethod<bool>('stopProxyService') ?? false;
  }

  Future<bool> shareApk() async {
    return await _channel.invokeMethod<bool>('shareApk') ?? false;
  }

  Future<bool> shareText({required String text, required String title}) async {
    return await _channel.invokeMethod<bool>('shareText', {
          'text': text,
          'title': title,
        }) ??
        false;
  }

  Future<bool> openUri(String uri) async {
    return await _channel.invokeMethod<bool>('openUri', {'uri': uri}) ?? false;
  }

  Future<bool> openHotspotSettings() async {
    return await _channel.invokeMethod<bool>('openHotspotSettings') ?? false;
  }

  Future<UsageStats> getStats() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('getStats');
    return UsageStats.fromMap(result ?? const {});
  }

  Future<ServiceSnapshot> getServiceState({
    required ProxyProtocol fallbackProtocol,
    required int fallbackPort,
    required Map<ProxyProtocol, int> fallbackPorts,
  }) async {
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
}
