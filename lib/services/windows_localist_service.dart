import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';

class WindowsLocalistService {
  WindowsLocalistService._();

  static final WindowsLocalistService instance = WindowsLocalistService._();
  static const MethodChannel _channel = MethodChannel('com.prs.localist.vpn');

  WindowsProxyServer? _proxyServer;
  WindowsLocalProxyForwarder? _localForwarder;
  bool _proxyRunning = false;
  bool _receivingRunning = false;
  bool _localProxyRunning = false;
  bool _windowsProxyApplied = false;
  Set<ProxyProtocol> _protocols = const {ProxyProtocol.socks5};
  Map<ProxyProtocol, int> _protocolPorts = {
    ProxyProtocol.http: ProxyProtocol.http.defaultPort,
    ProxyProtocol.socks5: ProxyProtocol.socks5.defaultPort,
  };
  bool _shareAllRoutes = true;
  RemoteProxyConfig? _remoteProxy;
  int _localProxyPort = 3781;
  int _sessionRxBytes = 0;
  int _sessionTxBytes = 0;
  int _totalRxBytes = 0;
  int _totalTxBytes = 0;
  Future<void>? _totalsLoader;

  Future<bool> ensureVpnPermission() async => true;

  Future<bool> startProxyService({
    required Set<ProxyProtocol> protocols,
    required Map<ProxyProtocol, int> ports,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
  }) async {
    await _ensureTotalsLoaded();
    await stopProxyService();
    final activeProtocols = protocols.isEmpty
        ? {ProxyProtocol.socks5}
        : {...protocols};
    final addresses = shareAllRoutes ? <String>{} : selectedLocalIps;
    _validatePorts(activeProtocols, ports);
    final server = WindowsProxyServer(
      protocols: activeProtocols,
      ports: ports,
      bindAddresses: addresses,
      onTraffic: _recordTraffic,
    );
    await server.start();
    _proxyServer = server;
    _proxyRunning = true;
    _receivingRunning = false;
    _localProxyRunning = false;
    _windowsProxyApplied = false;
    _protocols = activeProtocols;
    _protocolPorts = _coercePorts(ports);
    _shareAllRoutes = shareAllRoutes;
    _remoteProxy = null;
    _sessionRxBytes = 0;
    _sessionTxBytes = 0;
    return true;
  }

  Future<bool> startReceivingVpn(RemoteProxyConfig config) async {
    await _ensureTotalsLoaded();
    await _startLocalForwarder(config, localPort: _localProxyPort);
    await _applyWindowsSystemProxy(_localProxyPort);
    _proxyRunning = false;
    _receivingRunning = true;
    _localProxyRunning = false;
    _windowsProxyApplied = true;
    _remoteProxy = config;
    _protocols = {config.protocol};
    _protocolPorts = _coercePorts({
      ProxyProtocol.http: ProxyProtocol.http.defaultPort,
      ProxyProtocol.socks5: ProxyProtocol.socks5.defaultPort,
      config.protocol: config.port,
    });
    _sessionRxBytes = 0;
    _sessionTxBytes = 0;
    return true;
  }

  Future<bool> startLocalProxy(
    RemoteProxyConfig config, {
    int localPort = 3781,
  }) async {
    await _ensureTotalsLoaded();
    if (!await _isLocalPortAvailable(localPort)) {
      throw PlatformException(
        code: 'local_proxy_port_unavailable',
        message: 'Local port $localPort is busy.',
      );
    }
    await _restoreWindowsSystemProxyIfNeeded();
    await _startLocalForwarder(config, localPort: localPort);
    _proxyRunning = false;
    _receivingRunning = false;
    _localProxyRunning = true;
    _windowsProxyApplied = false;
    _remoteProxy = config;
    _protocols = {config.protocol};
    _protocolPorts = _coercePorts({
      ProxyProtocol.http: ProxyProtocol.http.defaultPort,
      ProxyProtocol.socks5: ProxyProtocol.socks5.defaultPort,
      config.protocol: config.port,
    });
    _localProxyPort = localPort;
    _sessionRxBytes = 0;
    _sessionTxBytes = 0;
    return true;
  }

  Future<RootRoutingInfo> checkAdminAccess() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'checkRootAccess',
    );
    final available = result?['available'] == true;
    return _adminInfo(available: available, enabled: available);
  }

  Future<RootRoutingInfo> setRootRoutingEnabled(bool enabled) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'setRootRoutingEnabled',
      {'enabled': enabled},
    );
    final available = result?['available'] == true;
    final launched = result?['launched'] == true;
    final message =
        (result?['lastError'] as String?) ??
        (launched
            ? 'Approve the Windows admin prompt to reopen Localist.'
            : '');
    return _adminInfo(
      available: available,
      enabled: enabled && available,
      lastError: message,
    );
  }

  Future<RootRoutingInfo> startRootSharing({
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
  }) {
    return setRootRoutingEnabled(true);
  }

  Future<RootRoutingInfo> stopRootSharing() async {
    final admin = await checkAdminAccess();
    return _adminInfo(available: admin.available, enabled: admin.available);
  }

  Future<bool> stopProxyService() async {
    await _proxyServer?.stop();
    _proxyServer = null;
    await _localForwarder?.stop();
    _localForwarder = null;
    await _restoreWindowsSystemProxyIfNeeded();
    _proxyRunning = false;
    _receivingRunning = false;
    _localProxyRunning = false;
    _windowsProxyApplied = false;
    _remoteProxy = null;
    return true;
  }

  Future<bool> openUri(String uri) async {
    return await _channel.invokeMethod<bool>('openUri', {'uri': uri}) ?? false;
  }

  Future<bool> shareText({required String text, required String title}) async {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  Future<UsageStats> getStats() async {
    await _ensureTotalsLoaded();
    return UsageStats(
      sessionRxBytes: _sessionRxBytes,
      sessionTxBytes: _sessionTxBytes,
      totalRxBytes: _totalRxBytes,
      totalTxBytes: _totalTxBytes,
    );
  }

  Future<ServiceSnapshot> getServiceState({
    required ProxyProtocol fallbackProtocol,
    required int fallbackPort,
    required Map<ProxyProtocol, int> fallbackPorts,
  }) async {
    await _ensureTotalsLoaded();
    final localIps = await WindowsNetworkInspector.localProxyIps();
    final admin = await checkAdminAccess();
    final protocols = _protocols.isEmpty ? {fallbackProtocol} : _protocols;
    final ports = _protocolPorts.isEmpty ? fallbackPorts : _protocolPorts;
    return ServiceSnapshot(
      vpnConnected: _receivingRunning,
      deviceVpnActive: _windowsProxyApplied,
      proxyRunning: _proxyRunning,
      receivingRunning: _receivingRunning,
      localProxyRunning: _localProxyRunning,
      localProxyPort: _localProxyPort,
      hotspot: HotspotInfo.inactive,
      protocols: protocols,
      protocolPorts: ports,
      port: _receivingRunning || _localProxyRunning
          ? _localProxyPort
          : ports[protocols.first] ?? fallbackPort,
      shareAllRoutes: _shareAllRoutes,
      localProxyIps: localIps,
      usage: await getStats(),
      remoteProxy: _remoteProxy,
      root: admin,
    );
  }

  Future<List<String>> getCameraDevices() async {
    final result = await _channel.invokeListMethod<String>(
      'getWindowsCameraDevices',
    );
    return result ?? const [];
  }

  Future<String?> getWindowsSettingsSignature() async {
    return await _channel.invokeMethod<String>('getWindowsSettingsSignature');
  }

  Future<void> _startLocalForwarder(
    RemoteProxyConfig config, {
    required int localPort,
  }) async {
    await _proxyServer?.stop();
    _proxyServer = null;
    await _localForwarder?.stop();
    final forwarder = WindowsLocalProxyForwarder(
      remoteProtocol: config.protocol,
      remoteHost: config.host,
      remotePort: config.port,
      localPort: localPort,
      onTraffic: _recordTraffic,
    );
    await forwarder.start();
    _localForwarder = forwarder;
    _localProxyPort = localPort;
  }

  Future<void> _applyWindowsSystemProxy(int localPort) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyStored = prefs.getBool(_restoreProxyStoredKey) ?? false;
    if (!alreadyStored) {
      final current = await _channel.invokeMapMethod<Object?, Object?>(
        'getWindowsSystemProxy',
      );
      await prefs.setBool(_restoreProxyStoredKey, true);
      await prefs.setBool(_restoreProxyEnabledKey, current?['enabled'] == true);
      await prefs.setString(
        _restoreProxyServerKey,
        (current?['server'] as String?) ?? '',
      );
      await prefs.setString(
        _restoreProxyBypassKey,
        (current?['bypass'] as String?) ?? '',
      );
    }
    await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
      'enabled': true,
      'server':
          'http=127.0.0.1:$localPort;https=127.0.0.1:$localPort;socks=127.0.0.1:$localPort',
      'bypass': '<local>',
    });
  }

  Future<void> _restoreWindowsSystemProxyIfNeeded() async {
    if (!_windowsProxyApplied) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_restoreProxyStoredKey) ?? false;
    if (stored) {
      await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
        'enabled': prefs.getBool(_restoreProxyEnabledKey) ?? false,
        'server': prefs.getString(_restoreProxyServerKey) ?? '',
        'bypass': prefs.getString(_restoreProxyBypassKey) ?? '',
      });
      await prefs.remove(_restoreProxyStoredKey);
      await prefs.remove(_restoreProxyEnabledKey);
      await prefs.remove(_restoreProxyServerKey);
      await prefs.remove(_restoreProxyBypassKey);
    } else {
      await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
        'enabled': false,
        'server': '',
        'bypass': '',
      });
    }
  }

  Future<void> _ensureTotalsLoaded() {
    return _totalsLoader ??= _loadTotals();
  }

  Future<void> _loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    _totalRxBytes = prefs.getInt(_statsRxKey) ?? 0;
    _totalTxBytes = prefs.getInt(_statsTxKey) ?? 0;
  }

  void _recordTraffic(int uploadedBytes, int downloadedBytes) {
    _sessionTxBytes += uploadedBytes;
    _sessionRxBytes += downloadedBytes;
    _totalTxBytes += uploadedBytes;
    _totalRxBytes += downloadedBytes;
    unawaited(_saveTotals());
  }

  Future<void> _saveTotals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_statsRxKey, _totalRxBytes);
    await prefs.setInt(_statsTxKey, _totalTxBytes);
  }

  RootRoutingInfo _adminInfo({
    required bool available,
    required bool enabled,
    String lastError = '',
  }) {
    return RootRoutingInfo(
      available: available,
      enabled: enabled,
      active: enabled,
      vpnInterface: available ? 'Windows administrator' : '',
      clientSubnets: const [],
      availableClientSubnets: const [],
      availableLocalIps: const [],
      lastError: lastError,
    );
  }

  Map<ProxyProtocol, int> _coercePorts(Map<ProxyProtocol, int> ports) {
    return {
      for (final protocol in ProxyProtocol.values)
        protocol: ports[protocol] ?? protocol.defaultPort,
    };
  }

  void _validatePorts(
    Set<ProxyProtocol> protocols,
    Map<ProxyProtocol, int> ports,
  ) {
    final seen = <int>{};
    for (final protocol in protocols) {
      final port = ports[protocol] ?? protocol.defaultPort;
      if (port < 1024 || port > 65535) {
        throw PlatformException(
          code: 'port_unavailable',
          message: '${protocol.label} port $port is outside 1024-65535.',
        );
      }
      if (!seen.add(port)) {
        throw PlatformException(
          code: 'port_unavailable',
          message: 'Port $port is assigned to more than one protocol.',
        );
      }
    }
  }

  Future<bool> _isLocalPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  static const _statsRxKey = 'windows.stats.rx';
  static const _statsTxKey = 'windows.stats.tx';
  static const _restoreProxyStoredKey = 'windows.proxy.restore.stored';
  static const _restoreProxyEnabledKey = 'windows.proxy.restore.enabled';
  static const _restoreProxyServerKey = 'windows.proxy.restore.server';
  static const _restoreProxyBypassKey = 'windows.proxy.restore.bypass';
}

class WindowsNetworkInspector {
  static Future<List<String>> localProxyIps() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final values = <String>{};
    for (final interface in interfaces) {
      final lower = interface.name.toLowerCase();
      if (lower.startsWith('lo') ||
          lower.startsWith('isatap') ||
          lower.startsWith('teredo') ||
          lower.startsWith('loopback') ||
          lower.contains('virtualbox') ||
          lower.contains('vmware')) {
        continue;
      }
      for (final address in interface.addresses) {
        final value = address.address;
        if (_isUsableIpv4(value) && await _canBind(value)) {
          values.add(value);
        }
      }
    }
    return values.toList()..sort((first, second) {
      final firstPrivate = _privateScore(first);
      final secondPrivate = _privateScore(second);
      if (firstPrivate != secondPrivate) {
        return secondPrivate.compareTo(firstPrivate);
      }
      return first.compareTo(second);
    });
  }

  static bool _isUsableIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return false;
    }
    final octets = parts.cast<int>();
    if (octets.any((part) => part < 0 || part > 255)) {
      return false;
    }
    return octets[0] != 0 &&
        octets[0] != 127 &&
        octets[0] < 224 &&
        value != '255.255.255.255';
  }

  static int _privateScore(String value) {
    final parts = value.split('.').map(int.parse).toList();
    if (parts[0] == 10) {
      return 3;
    }
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) {
      return 2;
    }
    if (parts[0] == 192 && parts[1] == 168) {
      return 1;
    }
    return 0;
  }

  static Future<bool> _canBind(String host) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress(host), 0);
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }
}

class WindowsProxyServer {
  WindowsProxyServer({
    required this.protocols,
    required this.ports,
    required this.bindAddresses,
    required this.onTraffic,
  });

  final Set<ProxyProtocol> protocols;
  final Map<ProxyProtocol, int> ports;
  final Set<String> bindAddresses;
  final void Function(int uploadedBytes, int downloadedBytes) onTraffic;
  final List<ServerSocket> _servers = [];
  bool _running = false;

  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    final addresses = bindAddresses.isEmpty ? const ['0.0.0.0'] : bindAddresses;
    try {
      for (final protocol in protocols) {
        final port = ports[protocol] ?? protocol.defaultPort;
        for (final address in addresses) {
          final server = await ServerSocket.bind(
            InternetAddress(address),
            port,
          );
          _servers.add(server);
          server.listen(
            (client) => unawaited(_handleClient(protocol, client)),
            onError: (_) {},
            cancelOnError: false,
          );
        }
      }
    } catch (error) {
      await stop();
      throw PlatformException(
        code: 'port_unavailable',
        message: 'Unable to bind proxy listener: $error',
      );
    }
  }

  Future<void> stop() async {
    _running = false;
    for (final server in _servers) {
      await server.close();
    }
    _servers.clear();
  }

  Future<void> _handleClient(ProxyProtocol protocol, Socket client) async {
    final reader = _SocketReader(client);
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      if (protocol == ProxyProtocol.http) {
        await _handleHttp(client, reader);
      } else {
        await _handleSocks5(client, reader);
      }
    } catch (_) {
      client.destroy();
      await reader.cancel();
    }
  }

  Future<void> _handleSocks5(Socket client, _SocketReader reader) async {
    if (await reader.readByte() != 0x05) {
      throw StateError('Unsupported SOCKS version');
    }
    final methods = await reader.readByte();
    await reader.readExact(methods);
    client.add([0x05, 0x00]);
    await client.flush();

    final version = await reader.readByte();
    final command = await reader.readByte();
    await reader.readByte();
    final addressType = await reader.readByte();
    if (version != 0x05 || command != 0x01) {
      client.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await client.flush();
      return;
    }
    final host = await _readSocksHost(reader, addressType);
    final targetPort = await reader.readPort();
    final remote = await Socket.connect(
      host,
      targetPort,
      timeout: const Duration(seconds: 10),
    );
    remote.setOption(SocketOption.tcpNoDelay, true);
    client.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    await client.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: _SocketReader(remote),
      rightSocket: remote,
    );
  }

  Future<void> _handleHttp(Socket client, _SocketReader reader) async {
    final headerBytes = await reader.readHttpHeader();
    final header = latin1.decode(headerBytes);
    final lines = header
        .split('\r\n')
        .where((line) => line.isNotEmpty)
        .toList();
    final firstLine = lines.isEmpty ? '' : lines.first;
    final firstParts = firstLine.split(' ');
    if (firstParts.length < 3) {
      throw StateError('Malformed HTTP request');
    }

    if (firstParts[0].toUpperCase() == 'CONNECT') {
      final target = _parseHostPort(firstParts[1], 443);
      final remote = await Socket.connect(
        target.host,
        target.port,
        timeout: const Duration(seconds: 10),
      );
      remote.setOption(SocketOption.tcpNoDelay, true);
      client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      await client.flush();
      await _relay(
        leftReader: reader,
        leftSocket: client,
        rightReader: _SocketReader(remote),
        rightSocket: remote,
      );
      return;
    }

    final uri = Uri.parse(firstParts[1]);
    final hostHeader = lines
        .firstWhere(
          (line) => line.toLowerCase().startsWith('host:'),
          orElse: () => '',
        )
        .substringAfter(':')
        .trim();
    final host = uri.host.isNotEmpty
        ? uri.host
        : hostHeader.substringBefore(':').trim();
    if (host.isEmpty) {
      throw StateError('Missing HTTP host');
    }
    final targetPort = uri.hasPort
        ? uri.port
        : int.tryParse(hostHeader.substringAfter(':')) ?? 80;
    final path =
        '${uri.path.isEmpty ? '/' : uri.path}'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
    final rebuilt = StringBuffer()
      ..write(firstParts[0])
      ..write(' ')
      ..write(path)
      ..write(' ')
      ..write(firstParts[2])
      ..write('\r\n');
    for (final line in lines.skip(1)) {
      if (!line.toLowerCase().startsWith('proxy-connection:')) {
        rebuilt
          ..write(line)
          ..write('\r\n');
      }
    }
    rebuilt.write('\r\n');

    final remote = await Socket.connect(
      host,
      targetPort,
      timeout: const Duration(seconds: 10),
    );
    remote.setOption(SocketOption.tcpNoDelay, true);
    remote.add(ascii.encode(rebuilt.toString()));
    await remote.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: _SocketReader(remote),
      rightSocket: remote,
    );
  }

  Future<void> _relay({
    required _SocketReader leftReader,
    required Socket leftSocket,
    required _SocketReader rightReader,
    required Socket rightSocket,
  }) async {
    final upload = _copyPipe(
      input: leftReader,
      output: rightSocket,
      onBytes: (count) => onTraffic(count, 0),
    );
    final download = _copyPipe(
      input: rightReader,
      output: leftSocket,
      onBytes: (count) => onTraffic(0, count),
    );
    await Future.any([upload, download]);
    leftSocket.destroy();
    rightSocket.destroy();
    await leftReader.cancel();
    await rightReader.cancel();
  }
}

class WindowsLocalProxyForwarder {
  WindowsLocalProxyForwarder({
    required this.remoteProtocol,
    required this.remoteHost,
    required this.remotePort,
    required this.localPort,
    required this.onTraffic,
  });

  final ProxyProtocol remoteProtocol;
  final String remoteHost;
  final int remotePort;
  final int localPort;
  final void Function(int uploadedBytes, int downloadedBytes) onTraffic;
  ServerSocket? _server;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    _server!.listen(
      (client) => unawaited(_handleClient(client)),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handleClient(Socket client) async {
    final reader = _SocketReader(client);
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      final first = await reader.readByte();
      reader.unreadByte(first);
      if (first == 0x05) {
        await _handleSocks5Client(client, reader);
      } else {
        await _handleHttpClient(client, reader);
      }
    } catch (_) {
      client.destroy();
      await reader.cancel();
    }
  }

  Future<void> _handleSocks5Client(Socket client, _SocketReader reader) async {
    if (await reader.readByte() != 0x05) {
      throw StateError('Unsupported SOCKS version');
    }
    final methods = await reader.readByte();
    await reader.readExact(methods);
    client.add([0x05, 0x00]);
    await client.flush();

    final version = await reader.readByte();
    final command = await reader.readByte();
    await reader.readByte();
    final addressType = await reader.readByte();
    if (version != 0x05 || command != 0x01) {
      client.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await client.flush();
      return;
    }
    final targetHost = await _readSocksHost(reader, addressType);
    final targetPort = await reader.readPort();
    final remote = await _connectRemoteProxy(targetHost, targetPort);
    client.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    await client.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: remote.reader,
      rightSocket: remote.socket,
    );
  }

  Future<void> _handleHttpClient(Socket client, _SocketReader reader) async {
    final headerBytes = await reader.readHttpHeader();
    final header = latin1.decode(headerBytes);
    final lines = header
        .split('\r\n')
        .where((line) => line.isNotEmpty)
        .toList();
    final firstLine = lines.isEmpty ? '' : lines.first;
    final firstParts = firstLine.split(' ');
    if (firstParts.length < 3) {
      throw StateError('Malformed HTTP request');
    }

    if (firstParts[0].toUpperCase() == 'CONNECT') {
      final target = _parseHostPort(firstParts[1], 443);
      final remote = await _connectRemoteProxy(target.host, target.port);
      client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      await client.flush();
      await _relay(
        leftReader: reader,
        leftSocket: client,
        rightReader: remote.reader,
        rightSocket: remote.socket,
      );
      return;
    }

    final uri = Uri.parse(firstParts[1]);
    final hostHeader = lines
        .firstWhere(
          (line) => line.toLowerCase().startsWith('host:'),
          orElse: () => '',
        )
        .substringAfter(':')
        .trim();
    final host = uri.host.isNotEmpty
        ? uri.host
        : hostHeader.substringBefore(':').trim();
    if (host.isEmpty) {
      throw StateError('Missing HTTP host');
    }
    final targetPort = uri.hasPort
        ? uri.port
        : int.tryParse(hostHeader.substringAfter(':')) ?? 80;
    final path =
        '${uri.path.isEmpty ? '/' : uri.path}'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
    final rebuilt = StringBuffer()
      ..write(firstParts[0])
      ..write(' ')
      ..write(path)
      ..write(' ')
      ..write(firstParts[2])
      ..write('\r\n');
    for (final line in lines.skip(1)) {
      if (!line.toLowerCase().startsWith('proxy-connection:')) {
        rebuilt
          ..write(line)
          ..write('\r\n');
      }
    }
    rebuilt.write('\r\n');

    final remote = await _connectRemoteProxy(host, targetPort);
    remote.socket.add(ascii.encode(rebuilt.toString()));
    await remote.socket.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: remote.reader,
      rightSocket: remote.socket,
    );
  }

  Future<_ProxyConnection> _connectRemoteProxy(
    String targetHost,
    int targetPort,
  ) async {
    final socket = await Socket.connect(
      remoteHost,
      remotePort,
      timeout: const Duration(seconds: 10),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = _SocketReader(socket);
    if (remoteProtocol == ProxyProtocol.http) {
      socket.add(
        ascii.encode(
          'CONNECT $targetHost:$targetPort HTTP/1.1\r\n'
          'Host: $targetHost:$targetPort\r\n'
          'Proxy-Connection: keep-alive\r\n\r\n',
        ),
      );
      await socket.flush();
      final response = latin1.decode(await reader.readHttpHeader());
      if (!RegExp(r'^HTTP/1\.[01] 200\b').hasMatch(response)) {
        socket.destroy();
        await reader.cancel();
        throw StateError('Remote HTTP proxy refused $targetHost:$targetPort');
      }
    } else {
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();
      final version = await reader.readByte();
      final method = await reader.readByte();
      if (version != 0x05 || method != 0x00) {
        socket.destroy();
        await reader.cancel();
        throw StateError('Remote SOCKS5 auth refused');
      }
      final hostBytes = utf8.encode(targetHost);
      socket.add([
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        (targetPort >> 8) & 0xff,
        targetPort & 0xff,
      ]);
      await socket.flush();
      final reply = await reader.readExact(10);
      if (reply.length < 2 || reply[1] != 0x00) {
        socket.destroy();
        await reader.cancel();
        throw StateError('Remote SOCKS5 refused $targetHost:$targetPort');
      }
    }
    return _ProxyConnection(socket: socket, reader: reader);
  }

  Future<void> _relay({
    required _SocketReader leftReader,
    required Socket leftSocket,
    required _SocketReader rightReader,
    required Socket rightSocket,
  }) async {
    final upload = _copyPipe(
      input: leftReader,
      output: rightSocket,
      onBytes: (count) => onTraffic(count, 0),
    );
    final download = _copyPipe(
      input: rightReader,
      output: leftSocket,
      onBytes: (count) => onTraffic(0, count),
    );
    await Future.any([upload, download]);
    leftSocket.destroy();
    rightSocket.destroy();
    await leftReader.cancel();
    await rightReader.cancel();
  }
}

class _ProxyConnection {
  const _ProxyConnection({required this.socket, required this.reader});

  final Socket socket;
  final _SocketReader reader;
}

class _HostPort {
  const _HostPort(this.host, this.port);

  final String host;
  final int port;
}

Future<void> _copyPipe({
  required _SocketReader input,
  required Socket output,
  required void Function(int count) onBytes,
}) async {
  while (true) {
    final chunk = await input.readChunk();
    if (chunk == null || chunk.isEmpty) {
      break;
    }
    output.add(chunk);
    await output.flush();
    onBytes(chunk.length);
  }
}

Future<String> _readSocksHost(_SocketReader reader, int addressType) async {
  return switch (addressType) {
    0x01 => InternetAddress.fromRawAddress(
      Uint8List.fromList(await reader.readExact(4)),
    ).address,
    0x03 => utf8.decode(await reader.readExact(await reader.readByte())),
    0x04 => InternetAddress.fromRawAddress(
      Uint8List.fromList(await reader.readExact(16)),
    ).address,
    _ => throw StateError('Unknown SOCKS address type'),
  };
}

_HostPort _parseHostPort(String value, int defaultPort) {
  final bracketEnd = value.startsWith('[') ? value.indexOf(']') : -1;
  if (bracketEnd > 0) {
    final host = value.substring(1, bracketEnd);
    final port = value.substring(bracketEnd + 1).substringAfter(':');
    return _HostPort(host, int.tryParse(port) ?? defaultPort);
  }
  final split = value.lastIndexOf(':');
  if (split <= 0) {
    return _HostPort(value, defaultPort);
  }
  return _HostPort(
    value.substring(0, split),
    int.tryParse(value.substring(split + 1)) ?? defaultPort,
  );
}

extension _StringParts on String {
  String substringBefore(String pattern) {
    final index = indexOf(pattern);
    return index < 0 ? this : substring(0, index);
  }

  String substringAfter(String pattern) {
    final index = indexOf(pattern);
    return index < 0 ? '' : substring(index + pattern.length);
  }
}

class _SocketReader {
  _SocketReader(this.socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        _completeWaiter();
      },
      onError: (Object error) {
        _error = error;
        _closed = true;
        _completeWaiter();
      },
      onDone: () {
        _closed = true;
        _completeWaiter();
      },
      cancelOnError: false,
    );
  }

  final Socket socket;
  final Queue<int> _buffer = Queue<int>();
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  void unreadByte(int value) {
    _buffer.addFirst(value);
  }

  Future<int> readByte() async {
    await _ensureAvailable(1);
    return _buffer.removeFirst();
  }

  Future<List<int>> readExact(int count) async {
    await _ensureAvailable(count);
    return [for (var i = 0; i < count; i++) _buffer.removeFirst()];
  }

  Future<int> readPort() async {
    return ((await readByte()) << 8) | await readByte();
  }

  Future<List<int>> readHttpHeader() async {
    final output = <int>[];
    var matched = 0;
    while (output.length < 64 * 1024) {
      final next = await readByte();
      output.add(next);
      matched = switch ((matched, next)) {
        (0, 13) => 1,
        (1, 10) => 2,
        (2, 13) => 3,
        (3, 10) => 4,
        (_, 13) => 1,
        _ => 0,
      };
      if (matched == 4) {
        return output;
      }
    }
    throw StateError('HTTP header too large');
  }

  Future<List<int>?> readChunk() async {
    while (_buffer.isEmpty) {
      if (_error != null) {
        throw StateError('Socket read failed: $_error');
      }
      if (_closed) {
        return null;
      }
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }
    final chunk = List<int>.from(_buffer);
    _buffer.clear();
    return chunk;
  }

  Future<void> cancel() {
    return _subscription.cancel();
  }

  Future<void> _ensureAvailable(int count) async {
    while (_buffer.length < count) {
      if (_error != null) {
        throw StateError('Socket read failed: $_error');
      }
      if (_closed) {
        throw StateError('Unexpected end of socket stream');
      }
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }
  }

  void _completeWaiter() {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    _waiter = null;
  }
}
