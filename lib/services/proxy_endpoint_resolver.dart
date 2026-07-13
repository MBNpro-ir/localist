import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/service_state.dart';
import 'log_service.dart';

/// Resolves a Localist proxy identity to an endpoint that is reachable from
/// the receiver's current network. Discovery source addresses are preferred
/// because they describe the route that actually delivered the packet.
class ProxyEndpointResolver {
  ProxyEndpointResolver({LogService? logs})
    : _logs = logs ?? LogService.instance;

  final LogService _logs;

  Future<RemoteProxyConfig?> resolve({
    required Iterable<SmartProxyEndpoint> advertisedEndpoints,
    required Iterable<LocalistDiscoveredDevice> discoveredDevices,
    String deviceId = '',
    String sourceAddress = '',
    ProxyProtocol? preferredProtocol,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final phases = buildCandidatePhases(
      advertisedEndpoints: advertisedEndpoints,
      discoveredDevices: discoveredDevices,
      deviceId: deviceId,
      sourceAddress: sourceAddress,
      preferredProtocol: preferredProtocol,
    );
    for (final phase in phases) {
      if (phase.isEmpty) {
        continue;
      }
      _logs.debug(
        'Smart endpoint probe phase: ${phase.map((value) => value.url).join(', ')}',
      );
      final result = await _firstReachable(phase, timeout);
      if (result != null) {
        _logs.info('Smart endpoint selected ${result.url}');
        return result;
      }
    }
    _logs.warning('No reachable smart proxy endpoint was found.');
    return null;
  }

  List<List<RemoteProxyConfig>> buildCandidatePhases({
    required Iterable<SmartProxyEndpoint> advertisedEndpoints,
    required Iterable<LocalistDiscoveredDevice> discoveredDevices,
    String deviceId = '',
    String sourceAddress = '',
    ProxyProtocol? preferredProtocol,
  }) {
    final advertised = advertisedEndpoints.toList(growable: false);
    final discovered = discoveredDevices.toList(growable: false);
    final exactDevices = deviceId.isEmpty
        ? const <LocalistDiscoveredDevice>[]
        : discovered.where((device) => device.id == deviceId).toList();
    // Never substitute another nearby device just because it happens to use
    // the same protocol and port. Identity-free legacy/manual configs are
    // probed exactly as advertised; identity-aware configs may only borrow a
    // route from the matching device.
    final compatibleDevices = deviceId.isEmpty
        ? const <LocalistDiscoveredDevice>[]
        : exactDevices;

    final routed = <RemoteProxyConfig>[];
    if (sourceAddress.isNotEmpty) {
      routed.addAll(_rewriteHost(advertised, sourceAddress));
    }
    for (final device in compatibleDevices) {
      routed.addAll(_rewriteHost(device.endpoints, device.sourceAddress));
    }

    final liveAdvertised = <RemoteProxyConfig>[
      for (final device in compatibleDevices)
        for (final endpoint in device.endpoints) endpoint.config,
    ];
    final original = advertised.map((endpoint) => endpoint.config).toList();

    return [
      _orderedUnique(routed, preferredProtocol),
      _orderedUnique(liveAdvertised, preferredProtocol),
      _orderedUnique(original, preferredProtocol),
    ];
  }

  Iterable<RemoteProxyConfig> _rewriteHost(
    Iterable<SmartProxyEndpoint> endpoints,
    String host,
  ) sync* {
    if (host.isEmpty) {
      return;
    }
    for (final endpoint in endpoints) {
      yield RemoteProxyConfig(
        protocol: endpoint.protocol,
        host: host,
        port: endpoint.port,
      );
    }
  }

  List<RemoteProxyConfig> _orderedUnique(
    Iterable<RemoteProxyConfig> values,
    ProxyProtocol? preferred,
  ) {
    final unique = <String, RemoteProxyConfig>{};
    for (final value in values) {
      unique.putIfAbsent(value.url, () => value);
    }
    final result = unique.values.toList();
    result.sort((first, second) {
      final firstPreferred = first.protocol == preferred ? 0 : 1;
      final secondPreferred = second.protocol == preferred ? 0 : 1;
      return firstPreferred.compareTo(secondPreferred);
    });
    return result;
  }

  Future<RemoteProxyConfig?> _firstReachable(
    List<RemoteProxyConfig> candidates,
    Duration timeout,
  ) async {
    final completer = Completer<RemoteProxyConfig?>();
    var pending = candidates.length;
    for (final candidate in candidates) {
      unawaited(() async {
        final reachable = await probe(candidate, timeout: timeout);
        if (reachable && !completer.isCompleted) {
          completer.complete(candidate);
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }());
    }
    return completer.future;
  }

  Future<bool> probe(
    RemoteProxyConfig config, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(config.host, config.port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      if (config.protocol == ProxyProtocol.socks5) {
        socket.add(const [0x05, 0x01, 0x00]);
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .expand((bytes) => bytes)
            .take(2)
            .toList()
            .timeout(timeout);
        return response.length == 2 &&
            response[0] == 0x05 &&
            response[1] == 0x00;
      }

      socket.add(
        ascii.encode(
          'CONNECT 127.0.0.1:1 HTTP/1.1\r\n'
          'Host: 127.0.0.1:1\r\n'
          'Connection: close\r\n\r\n',
        ),
      );
      await socket.flush();
      final response = await socket
          .cast<List<int>>()
          .expand((bytes) => bytes)
          .take(5)
          .toList()
          .timeout(timeout);
      return ascii.decode(response, allowInvalid: true) == 'HTTP/';
    } catch (error) {
      _logs.debug('Smart endpoint probe failed ${config.url}: $error');
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
