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
    _logs.debug(
      'Smart endpoint resolution requested preferredProtocol=${preferredProtocol?.name ?? 'any'} timeoutMs=${timeout.inMilliseconds} hasDeviceIdentity=${deviceId.isNotEmpty} hasSourceRoute=${sourceAddress.isNotEmpty}',
    );
    final phases = buildCandidatePhases(
      advertisedEndpoints: advertisedEndpoints,
      discoveredDevices: discoveredDevices,
      deviceId: deviceId,
      sourceAddress: sourceAddress,
      preferredProtocol: preferredProtocol,
    );
    for (var index = 0; index < phases.length; index++) {
      final phase = phases[index];
      if (phase.isEmpty) {
        _logs.debug('Smart endpoint phase=${index + 1} skipped empty');
        continue;
      }
      _logs.debug(
        'Smart endpoint phase=${index + 1} candidates=${phase.length}',
      );
      final result = await _firstReachable(phase, timeout);
      if (result != null) {
        _logs.debug(
          'Smart endpoint phase=${index + 1} succeeded protocol=${result.protocol.name}',
        );
        _logs.info('Smart proxy endpoint selected.');
        return result;
      }
      _logs.debug('Smart endpoint phase=${index + 1} exhausted');
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
    _logs.debug('Smart endpoint probes started parallelCount=$pending');
    for (final candidate in candidates) {
      unawaited(() async {
        final reachable = await probe(candidate, timeout: timeout);
        if (reachable && !completer.isCompleted) {
          _logs.debug('Smart endpoint first reachable candidate selected');
          completer.complete(candidate);
        }
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          _logs.debug('Smart endpoint all probes finished unreachable');
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
    _logs.debug(
      'Smart endpoint TCP probe started protocol=${config.protocol.name} timeoutMs=${timeout.inMilliseconds}',
    );
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
        final accepted =
            response.length == 2 && response[0] == 0x05 && response[1] == 0x00;
        _logs.debug('Smart SOCKS handshake finished accepted=$accepted');
        return accepted;
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
      final accepted = ascii.decode(response, allowInvalid: true) == 'HTTP/';
      _logs.debug('Smart HTTP CONNECT handshake finished accepted=$accepted');
      return accepted;
    } catch (error) {
      _logs.debug('Smart endpoint probe failed type=${error.runtimeType}');
      return false;
    } finally {
      socket?.destroy();
      _logs.debug('Smart endpoint probe socket released');
    }
  }
}
