import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';
import 'log_service.dart';
import 'localist_discovery_protocol.dart';

class WindowsLocalistService {
  WindowsLocalistService._();

  static final WindowsLocalistService instance = WindowsLocalistService._();
  static const MethodChannel _channel = MethodChannel('com.prs.localist.vpn');

  final LogService _logs = LogService.instance;
  WindowsProxyServer? _proxyServer;
  WindowsLocalProxyForwarder? _localForwarder;
  final WindowsWintunController _wintun = WindowsWintunController();
  final WindowsLocalistDiscoveryResponder _discoveryResponder =
      WindowsLocalistDiscoveryResponder();
  bool _proxyRunning = false;
  bool _receivingRunning = false;
  bool _localProxyRunning = false;
  bool _windowsProxyApplied = false;
  bool _clearWindowsProxyOnStop = false;
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
  Timer? _statsSaveTimer;
  bool _statsSaveInFlight = false;
  bool _statsSavePending = false;

  Future<bool> ensureVpnPermission() async {
    _logs.debug('Windows VPN permission check started');
    final admin = await checkAdminAccess();
    if (admin.available) {
      _logs.debug('Windows VPN permission already available');
      return true;
    }
    final requested = await setRootRoutingEnabled(true);
    if (requested.available) {
      _logs.debug('Windows VPN permission granted after admin request');
      return true;
    }
    _logs.debug('Windows VPN permission denied: ${requested.lastError}');
    throw PlatformException(
      code: 'windows_admin_required',
      message: requested.lastError.isEmpty
          ? 'Run Localist as administrator to start Windows VPN mode.'
          : requested.lastError,
    );
  }

  Future<bool> startProxyService({
    required Set<ProxyProtocol> protocols,
    required Map<ProxyProtocol, int> ports,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
    RemoteProxyConfig? upstreamProxy,
  }) async {
    _logs.debug(
      'Windows sharing start requested protocols=${protocols.map((value) => value.name).join(',')} ports=$ports shareAllRoutes=$shareAllRoutes selectedLocalIps=$selectedLocalIps upstream=${upstreamProxy?.url}',
    );
    await _ensureTotalsLoaded();
    final activeProtocols = protocols.isEmpty
        ? {ProxyProtocol.socks5}
        : {...protocols};
    final addresses = shareAllRoutes ? <String>{} : selectedLocalIps;
    _validatePorts(activeProtocols, ports);
    final effectiveUpstreamProxy = await _resolveUpstreamProxy(
      activeProtocols,
      ports,
      upstreamProxy,
    );
    await stopProxyService();
    final server = WindowsProxyServer(
      protocols: activeProtocols,
      ports: ports,
      bindAddresses: addresses,
      upstreamProxy: effectiveUpstreamProxy,
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
    await _discoveryResponder.start(_buildDiscoveryEndpoints);
    _logs.debug(
      'Windows sharing started bindAddresses=$addresses protocols=${activeProtocols.map((value) => value.name).join(',')} ports=$_protocolPorts upstream=${effectiveUpstreamProxy?.url}',
    );
    return true;
  }

  Future<bool> startReceivingVpn(RemoteProxyConfig config) async {
    _logs.debug('Windows receiving VPN start requested config=${config.url}');
    await _ensureTotalsLoaded();
    await _discoveryResponder.stop();
    await _startLocalForwarder(config, localPort: _localProxyPort);
    await _restoreWindowsSystemProxyIfNeeded();
    late final bool wintunStarted;
    try {
      wintunStarted = await _wintun.start(config);
      if (!wintunStarted) {
        _logs.warning(
          'Wintun tools were not found; using Windows system proxy fallback on 127.0.0.1:$_localProxyPort.',
        );
        _clearWindowsProxyOnStop = false;
        await _applyWindowsSystemProxy(_localProxyPort);
      }
    } catch (_) {
      await _localForwarder?.stop();
      _localForwarder = null;
      rethrow;
    }
    _proxyRunning = false;
    _receivingRunning = true;
    _localProxyRunning = true;
    _windowsProxyApplied = !wintunStarted;
    _remoteProxy = config;
    _protocols = {config.protocol};
    _protocolPorts = _coercePorts({
      ProxyProtocol.http: ProxyProtocol.http.defaultPort,
      ProxyProtocol.socks5: ProxyProtocol.socks5.defaultPort,
      config.protocol: config.port,
    });
    _sessionRxBytes = 0;
    _sessionTxBytes = 0;
    _logs.debug(
      'Windows receiving VPN started wintun=$wintunStarted localProxyPort=$_localProxyPort windowsProxyApplied=$_windowsProxyApplied',
    );
    return true;
  }

  Future<bool> startLocalProxy(
    RemoteProxyConfig config, {
    int localPort = 3781,
  }) async {
    _logs.debug(
      'Windows local proxy start requested config=${config.url} localPort=$localPort',
    );
    await _ensureTotalsLoaded();
    await _discoveryResponder.stop();
    if (!await _isLocalPortAvailable(localPort)) {
      throw PlatformException(
        code: 'local_proxy_port_unavailable',
        message: 'Local port $localPort is busy.',
      );
    }
    await _wintun.stop();
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
    _logs.debug('Windows local proxy started localPort=$_localProxyPort');
    return true;
  }

  Future<bool> startSystemProxy(
    RemoteProxyConfig config, {
    int localPort = 3781,
  }) async {
    _logs.debug(
      'Windows system proxy start requested config=${config.url} localPort=$localPort',
    );
    await _ensureTotalsLoaded();
    await _discoveryResponder.stop();
    if (!await _isLocalPortAvailable(localPort)) {
      throw PlatformException(
        code: 'local_proxy_port_unavailable',
        message: 'Local port $localPort is busy.',
      );
    }
    await _wintun.stop();
    await _restoreWindowsSystemProxyIfNeeded();
    await _startLocalForwarder(config, localPort: localPort);
    try {
      _clearWindowsProxyOnStop = true;
      await _applyWindowsSystemProxy(localPort);
    } catch (_) {
      _clearWindowsProxyOnStop = false;
      await _localForwarder?.stop();
      _localForwarder = null;
      rethrow;
    }
    _proxyRunning = false;
    _receivingRunning = false;
    _localProxyRunning = true;
    _windowsProxyApplied = true;
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
    _logs.debug('Windows system proxy started localPort=$_localProxyPort');
    return true;
  }

  Future<RootRoutingInfo> checkAdminAccess() async {
    _logs.debug('Windows admin access check requested');
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'checkRootAccess',
    );
    final available = result?['available'] == true;
    _logs.debug('Windows admin access result available=$available raw=$result');
    return _adminInfo(available: available, enabled: available);
  }

  Future<RootRoutingInfo> setRootRoutingEnabled(bool enabled) async {
    _logs.debug('Windows admin escalation requested enabled=$enabled');
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
    _logs.debug(
      'Windows stop requested proxy=$_proxyRunning receiving=$_receivingRunning localProxy=$_localProxyRunning windowsProxy=$_windowsProxyApplied',
    );
    await _discoveryResponder.stop();
    await _wintun.stop();
    await _proxyServer?.stop();
    _proxyServer = null;
    await _localForwarder?.stop();
    _localForwarder = null;
    await _restoreWindowsSystemProxyIfNeeded();
    _proxyRunning = false;
    _receivingRunning = false;
    _localProxyRunning = false;
    _windowsProxyApplied = false;
    _clearWindowsProxyOnStop = false;
    _remoteProxy = null;
    await _flushTotals();
    _logs.debug('Windows stop completed');
    return true;
  }

  Future<bool> openUri(String uri) async {
    final parsed = Uri.tryParse(uri);
    _logs.debug(
      'Windows open URI requested scheme=${parsed?.scheme ?? 'unknown'} '
      'characters=${uri.length}',
    );
    return await _channel.invokeMethod<bool>('openUri', {'uri': uri}) ?? false;
  }

  Future<bool> shareText({required String text, required String title}) async {
    _logs.debug(
      'Windows share text requested title=$title bytes=${text.length}',
    );
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  Future<UsageStats> getStats() async {
    await _ensureTotalsLoaded();
    _logs.debug(
      'Windows stats requested sessionRx=$_sessionRxBytes sessionTx=$_sessionTxBytes totalRx=$_totalRxBytes totalTx=$_totalTxBytes',
    );
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
    _logs.debug('Windows service snapshot requested');
    await _ensureTotalsLoaded();
    final localIps = await WindowsNetworkInspector.localProxyIps();
    final admin = await checkAdminAccess();
    final protocols = _protocols.isEmpty ? {fallbackProtocol} : _protocols;
    final ports = _protocolPorts.isEmpty ? fallbackPorts : _protocolPorts;
    final snapshot = ServiceSnapshot(
      vpnConnected: _receivingRunning,
      deviceVpnActive: _wintun.running || _windowsProxyApplied,
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
    _logs.debug(
      'Windows service snapshot loaded proxy=${snapshot.proxyRunning} receiving=${snapshot.receivingRunning} localProxy=${snapshot.localProxyRunning} vpn=${snapshot.deviceVpnActive}',
    );
    return snapshot;
  }

  Future<List<String>> getCameraDevices() async {
    _logs.debug('Windows camera device list requested');
    final result = await _channel.invokeListMethod<String>(
      'getWindowsCameraDevices',
    );
    _logs.debug('Windows camera devices: ${result ?? const []}');
    return result ?? const [];
  }

  Future<String?> getWindowsSettingsSignature() async {
    _logs.debug('Windows settings signature requested');
    return await _channel.invokeMethod<String>('getWindowsSettingsSignature');
  }

  Future<void> _startLocalForwarder(
    RemoteProxyConfig config, {
    required int localPort,
  }) async {
    _logs.debug(
      'Windows local forwarder setup remote=${config.url} localPort=$localPort',
    );
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
    try {
      await forwarder.start();
    } catch (error) {
      throw PlatformException(
        code: 'local_proxy_port_unavailable',
        message: 'Unable to bind local proxy on 127.0.0.1:$localPort: $error',
      );
    }
    _localForwarder = forwarder;
    _localProxyPort = localPort;
    _logs.debug('Windows local forwarder ready on 127.0.0.1:$localPort');
  }

  Future<List<SmartProxyEndpoint>> _buildDiscoveryEndpoints() async {
    if (!_proxyRunning) {
      _logs.debug('Windows discovery endpoints skipped: proxy not running');
      return const [];
    }
    final selectedAddresses = _proxyServer?.bindAddresses ?? const <String>{};
    final hosts = selectedAddresses.isEmpty
        ? await WindowsNetworkInspector.localProxyIps()
        : selectedAddresses.toList(growable: false);
    if (hosts.isEmpty) {
      _logs.debug('Windows discovery endpoints empty: no hosts');
      return const [];
    }
    final endpoints = [
      for (final protocol in _protocols)
        for (final host in hosts)
          SmartProxyEndpoint(
            protocol: protocol,
            host: host,
            port: _protocolPorts[protocol] ?? protocol.defaultPort,
          ),
    ];
    _logs.debug(
      'Windows discovery endpoints built: ${endpoints.map((endpoint) => endpoint.config.url).join(', ')}',
    );
    return endpoints;
  }

  Future<void> _applyWindowsSystemProxy(int localPort) async {
    _logs.debug('Applying Windows system proxy localPort=$localPort');
    final prefs = await SharedPreferences.getInstance();
    final alreadyStored = prefs.getBool(_restoreProxyStoredKey) ?? false;
    if (!alreadyStored) {
      final current = await _channel.invokeMapMethod<Object?, Object?>(
        'getWindowsSystemProxy',
      );
      _logs.debug('Stored current Windows system proxy: $current');
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
    final applied = await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
      'enabled': true,
      'server':
          'http=127.0.0.1:$localPort;https=127.0.0.1:$localPort;socks=127.0.0.1:$localPort',
      'bypass': '<local>',
    });
    if (applied != true) {
      throw PlatformException(
        code: 'windows_proxy_failed',
        message: 'Windows system proxy could not be enabled.',
      );
    }
    _logs.debug('Windows system proxy applied');
  }

  Future<void> _restoreWindowsSystemProxyIfNeeded() async {
    if (!_windowsProxyApplied) {
      _logs.debug('Windows system proxy restore skipped: nothing applied');
      return;
    }
    _logs.debug(
      'Restoring Windows system proxy clearOnStop=$_clearWindowsProxyOnStop',
    );
    if (_clearWindowsProxyOnStop) {
      await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
        'enabled': false,
        'server': '',
        'bypass': '',
      });
      await _clearStoredWindowsProxy();
      _clearWindowsProxyOnStop = false;
      _logs.debug('Windows system proxy cleared');
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
      _logs.debug('Windows system proxy restored from stored state');
    } else {
      await _channel.invokeMethod<bool>('setWindowsSystemProxy', {
        'enabled': false,
        'server': '',
        'bypass': '',
      });
      _logs.debug('Windows system proxy disabled without stored state');
    }
  }

  Future<void> _clearStoredWindowsProxy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_restoreProxyStoredKey);
    await prefs.remove(_restoreProxyEnabledKey);
    await prefs.remove(_restoreProxyServerKey);
    await prefs.remove(_restoreProxyBypassKey);
  }

  Future<void> _ensureTotalsLoaded() {
    return _totalsLoader ??= _loadTotals();
  }

  Future<void> _loadTotals() async {
    final prefs = await SharedPreferences.getInstance();
    _totalRxBytes = prefs.getInt(_statsRxKey) ?? 0;
    _totalTxBytes = prefs.getInt(_statsTxKey) ?? 0;
    _logs.debug('Windows totals loaded rx=$_totalRxBytes tx=$_totalTxBytes');
  }

  void _recordTraffic(int uploadedBytes, int downloadedBytes) {
    _sessionTxBytes += uploadedBytes;
    _sessionRxBytes += downloadedBytes;
    _totalTxBytes += uploadedBytes;
    _totalRxBytes += downloadedBytes;
    _scheduleSaveTotals();
  }

  void _scheduleSaveTotals() {
    _statsSavePending = true;
    _statsSaveTimer ??= Timer(const Duration(seconds: 2), () {
      _statsSaveTimer = null;
      unawaited(_flushTotals());
    });
  }

  Future<void> _flushTotals() async {
    _statsSaveTimer?.cancel();
    _statsSaveTimer = null;
    if (!_statsSavePending || _statsSaveInFlight) {
      return;
    }
    _statsSavePending = false;
    _statsSaveInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_statsRxKey, _totalRxBytes);
      await prefs.setInt(_statsTxKey, _totalTxBytes);
      _logs.debug('Windows totals flushed rx=$_totalRxBytes tx=$_totalTxBytes');
    } finally {
      _statsSaveInFlight = false;
    }
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
    _logs.debug('Windows port validation protocols=$protocols ports=$ports');
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

  Future<RemoteProxyConfig?> _resolveUpstreamProxy(
    Set<ProxyProtocol> protocols,
    Map<ProxyProtocol, int> ports,
    RemoteProxyConfig? upstreamProxy,
  ) async {
    if (upstreamProxy == null) {
      _logs.debug('Windows upstream proxy validation skipped');
      return null;
    }
    _logs.debug(
      'Windows upstream proxy validation started ${upstreamProxy.url}',
    );
    if (upstreamProxy.port < 1024 || upstreamProxy.port > 65535) {
      _logs.warning(
        'Internal VPN proxy was ignored: port ${upstreamProxy.port} is outside 1024-65535.',
      );
      return null;
    }
    final activeListenPorts = {
      for (final protocol in protocols) ports[protocol] ?? protocol.defaultPort,
    };
    final upstreamIsLoopback =
        upstreamProxy.host == InternetAddress.loopbackIPv4.address ||
        upstreamProxy.host == InternetAddress.loopbackIPv6.address ||
        upstreamProxy.host.toLowerCase() == 'localhost';
    if (upstreamIsLoopback && activeListenPorts.contains(upstreamProxy.port)) {
      _logs.warning(
        'Internal VPN proxy was ignored: port ${upstreamProxy.port} conflicts with a sharing port.',
      );
      return null;
    }
    if (!await _isTcpConnectable(upstreamProxy.host, upstreamProxy.port)) {
      _logs.warning(
        'Internal VPN proxy is not reachable on ${upstreamProxy.host}:${upstreamProxy.port}; Sharing will continue without VPN upstream.',
      );
      return null;
    }
    _logs.debug('Windows upstream proxy is reachable ${upstreamProxy.url}');
    return upstreamProxy;
  }

  Future<bool> _isLocalPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _logs.debug('Windows local port available port=$port');
      return true;
    } catch (error, stack) {
      _logs.debug(
        'Windows local port unavailable port=$port',
        error: error,
        stack: stack,
      );
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<bool> _isTcpConnectable(String host, int port) async {
    Socket? socket;
    try {
      _logs.debug('Windows TCP probe started $host:$port');
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      _logs.debug('Windows TCP probe succeeded $host:$port');
      return true;
    } catch (error, stack) {
      _logs.debug(
        'Windows TCP probe failed $host:$port',
        error: error,
        stack: stack,
      );
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static const _statsRxKey = 'windows.stats.rx';
  static const _statsTxKey = 'windows.stats.tx';
  static const _restoreProxyStoredKey = 'windows.proxy.restore.stored';
  static const _restoreProxyEnabledKey = 'windows.proxy.restore.enabled';
  static const _restoreProxyServerKey = 'windows.proxy.restore.server';
  static const _restoreProxyBypassKey = 'windows.proxy.restore.bypass';
}

class WindowsWintunController {
  Process? _process;
  String? _remoteRouteIp;
  String? _remoteRouteInterface;
  String? _remoteRouteNextHop;
  bool _running = false;

  static const _tunInterface = 'wintun';
  static const _tunAddress = '198.18.0.1';
  static const _tunMask = '255.254.0.0';

  bool get running => _running;

  Future<bool> start(RemoteProxyConfig config) async {
    LogService.instance.debug('Wintun start requested proxy=${config.url}');
    await stop();
    final tools = await _findTools();
    if (tools == null) {
      LogService.instance.warning(
        'Wintun is unavailable: tun2socks.exe and wintun.dll must be beside Localist.exe or in windows\\runner\\resources.',
      );
      LogService.instance.debug('Wintun tools unavailable');
      return false;
    }
    final route = await _findRouteForHost(config.host);
    LogService.instance.debug(
      'Wintun route for ${config.host}: interface=${route?.interfaceAlias} nextHop=${route?.nextHop} ip=${route?.ip}',
    );
    final args = <String>[
      '-device',
      _tunInterface,
      '-proxy',
      config.url,
      '-loglevel',
      'warn',
    ];
    if (route != null) {
      args.addAll(['-interface', route.interfaceAlias]);
    }

    try {
      final stdoutBuffer = BytesBuilder(copy: false);
      final stderrBuffer = BytesBuilder(copy: false);
      final process = await Process.start(
        tools.tun2socksPath,
        args,
        workingDirectory: tools.directory,
        mode: ProcessStartMode.normal,
      );
      LogService.instance.debug(
        'tun2socks started pid=${process.pid} args=${args.join(' ')} directory=${tools.directory}',
      );
      _process = process;
      unawaited(
        process.stdout.listen((data) {
          _appendProcessOutput(stdoutBuffer, data);
        }).asFuture<void>(),
      );
      unawaited(
        process.stderr.listen((data) {
          _appendProcessOutput(stderrBuffer, data);
        }).asFuture<void>(),
      );
      unawaited(
        process.exitCode.then((_) async {
          if (!identical(_process, process)) {
            return;
          }
          _process = null;
          _running = false;
          LogService.instance.debug('tun2socks process exited');
          await _deleteDefaultRoutes();
          await _deleteRemoteBypassRoute();
        }),
      );
      final earlyExit = await Future.any<int?>([
        process.exitCode,
        Future<int?>.delayed(const Duration(milliseconds: 850), () => null),
      ]);
      if (earlyExit != null) {
        final stdoutText = _decodeProcessOutput(stdoutBuffer);
        final stderrText = _decodeProcessOutput(stderrBuffer);
        final details = [
          if (stderrText.isNotEmpty) 'stderr: $stderrText',
          if (stdoutText.isNotEmpty) 'stdout: $stdoutText',
        ].join(' | ');
        throw PlatformException(
          code: 'wintun_start_failed',
          message:
              'tun2socks exited with code $earlyExit.${details.isEmpty ? '' : ' $details'}',
        );
      }
      await _waitForInterface();
      await _configureInterface();
      if (route != null) {
        await _addRemoteBypassRoute(route);
      }
      await _addDefaultRoutes();
      _running = true;
      LogService.instance.debug('Wintun start completed');
      return true;
    } catch (error) {
      LogService.instance.debug('Wintun start failed', error: error);
      await stop();
      if (error is PlatformException) {
        rethrow;
      }
      throw PlatformException(
        code: 'wintun_start_failed',
        message: 'Unable to start Wintun VPN: $error',
      );
    }
  }

  void _appendProcessOutput(BytesBuilder buffer, List<int> data) {
    const maxLogBytes = 16 * 1024;
    buffer.add(data);
    if (buffer.length <= maxLogBytes) {
      return;
    }
    final bytes = buffer.takeBytes();
    buffer.add(bytes.sublist(bytes.length - maxLogBytes));
  }

  String _decodeProcessOutput(BytesBuilder buffer) {
    return utf8.decode(buffer.takeBytes(), allowMalformed: true).trim();
  }

  Future<void> stop() async {
    LogService.instance.debug('Wintun stop requested running=$_running');
    await _deleteDefaultRoutes();
    await _deleteRemoteBypassRoute();
    _process?.kill();
    _process = null;
    _running = false;
    LogService.instance.debug('Wintun stop completed');
  }

  Future<_WindowsWintunTools?> _findTools() async {
    LogService.instance.debug('Searching for Wintun tools');
    final bundledTun2socks = _fileNearExecutable('tun2socks.exe');
    final bundledWintun = _fileNearExecutable('wintun.dll');
    if (await bundledTun2socks.exists() && await bundledWintun.exists()) {
      LogService.instance.debug(
        'Wintun tools found beside executable: ${bundledTun2socks.path}',
      );
      return _WindowsWintunTools(
        tun2socksPath: bundledTun2socks.path,
        directory: bundledTun2socks.parent.path,
      );
    }

    final resourceTun2socks = File(
      '${Directory.current.path}\\windows\\runner\\resources\\tun2socks.exe',
    );
    final resourceWintun = File(
      '${Directory.current.path}\\windows\\runner\\resources\\wintun.dll',
    );
    if (await resourceTun2socks.exists() && await resourceWintun.exists()) {
      LogService.instance.debug(
        'Wintun tools found in resources: ${resourceTun2socks.path}',
      );
      return _WindowsWintunTools(
        tun2socksPath: resourceTun2socks.path,
        directory: resourceTun2socks.parent.path,
      );
    }

    final pathTun2socks = await _where('tun2socks.exe');
    if (pathTun2socks == null) {
      LogService.instance.debug('tun2socks.exe not found on PATH');
      return null;
    }
    final pathWintun = File('${File(pathTun2socks).parent.path}\\wintun.dll');
    if (!await pathWintun.exists()) {
      LogService.instance.debug(
        'wintun.dll not found beside PATH tun2socks: $pathTun2socks',
      );
      return null;
    }
    LogService.instance.debug('Wintun tools found on PATH: $pathTun2socks');
    return _WindowsWintunTools(
      tun2socksPath: pathTun2socks,
      directory: File(pathTun2socks).parent.path,
    );
  }

  File _fileNearExecutable(String name) {
    return File('${File(Platform.resolvedExecutable).parent.path}\\$name');
  }

  Future<String?> _where(String executable) async {
    LogService.instance.debug('Running where.exe $executable');
    final result = await Process.run('where.exe', [executable]);
    if (result.exitCode != 0) {
      LogService.instance.debug('where.exe did not find $executable');
      return null;
    }
    final output = result.stdout.toString().trim().split(RegExp(r'\r?\n'));
    return output.where((line) => line.trim().isNotEmpty).firstOrNull?.trim();
  }

  Future<_WindowsRoute?> _findRouteForHost(String host) async {
    LogService.instance.debug('Finding Windows route for host=$host');
    final ip = await _resolveIpv4(host);
    if (ip == null) {
      LogService.instance.debug('Could not resolve IPv4 route host=$host');
      return null;
    }
    final script =
        "\$route = Find-NetRoute -RemoteIPAddress '$ip' | "
        'Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1; '
        r"if ($route) { "
        r"$route.InterfaceAlias + '|' + $route.NextHop "
        r"}";
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      LogService.instance.debug(
        'Find-NetRoute failed exit=${result.exitCode} stderr=${result.stderr}',
      );
      return null;
    }
    final output = result.stdout.toString().trim();
    final parts = output.split('|');
    if (parts.length != 2 || parts.first.trim().isEmpty) {
      return null;
    }
    return _WindowsRoute(
      ip: ip,
      interfaceAlias: parts[0].trim(),
      nextHop: parts[1].trim().isEmpty ? '0.0.0.0' : parts[1].trim(),
    );
  }

  Future<String?> _resolveIpv4(String host) async {
    if (InternetAddress.tryParse(host)?.type == InternetAddressType.IPv4) {
      return host;
    }
    try {
      LogService.instance.debug('Resolving IPv4 host=$host');
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      final resolved = addresses.firstOrNull?.address;
      LogService.instance.debug('Resolved host=$host ipv4=$resolved');
      return resolved;
    } catch (error, stack) {
      LogService.instance.debug(
        'IPv4 resolve failed host=$host',
        error: error,
        stack: stack,
      );
      return null;
    }
  }

  Future<void> _waitForInterface() async {
    LogService.instance.debug('Waiting for Wintun interface');
    for (var attempt = 0; attempt < 20; attempt++) {
      final result = await Process.run('netsh.exe', [
        'interface',
        'show',
        'interface',
        'name=$_tunInterface',
      ]);
      if (result.exitCode == 0) {
        LogService.instance.debug('Wintun interface appeared attempt=$attempt');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw PlatformException(
      code: 'wintun_interface_missing',
      message: 'The Wintun interface did not appear after tun2socks started.',
    );
  }

  Future<void> _configureInterface() async {
    await _runNetsh([
      'interface',
      'ipv4',
      'set',
      'address',
      'name=$_tunInterface',
      'source=static',
      'addr=$_tunAddress',
      'mask=$_tunMask',
    ]);
    await _runNetsh([
      'interface',
      'ipv4',
      'set',
      'dnsservers',
      'name=$_tunInterface',
      'static',
      'address=1.1.1.1',
      'register=none',
      'validate=no',
    ], allowFailure: true);
    await _runNetsh([
      'interface',
      'ipv4',
      'add',
      'dnsservers',
      'name=$_tunInterface',
      'address=8.8.8.8',
      'index=2',
      'validate=no',
    ], allowFailure: true);
  }

  Future<void> _addDefaultRoutes() async {
    await _runNetsh([
      'interface',
      'ipv4',
      'add',
      'route',
      '0.0.0.0/1',
      _tunInterface,
      _tunAddress,
      'metric=1',
    ], allowFailure: true);
    await _runNetsh([
      'interface',
      'ipv4',
      'add',
      'route',
      '128.0.0.0/1',
      _tunInterface,
      _tunAddress,
      'metric=1',
    ], allowFailure: true);
  }

  Future<void> _deleteDefaultRoutes() async {
    await _runNetsh([
      'interface',
      'ipv4',
      'delete',
      'route',
      '0.0.0.0/1',
      _tunInterface,
      _tunAddress,
    ], allowFailure: true);
    await _runNetsh([
      'interface',
      'ipv4',
      'delete',
      'route',
      '128.0.0.0/1',
      _tunInterface,
      _tunAddress,
    ], allowFailure: true);
  }

  Future<void> _addRemoteBypassRoute(_WindowsRoute route) async {
    await _runNetsh([
      'interface',
      'ipv4',
      'add',
      'route',
      '${route.ip}/32',
      route.interfaceAlias,
      route.nextHop,
      'metric=1',
    ], allowFailure: true);
    _remoteRouteIp = route.ip;
    _remoteRouteInterface = route.interfaceAlias;
    _remoteRouteNextHop = route.nextHop;
  }

  Future<void> _deleteRemoteBypassRoute() async {
    final ip = _remoteRouteIp;
    final interfaceAlias = _remoteRouteInterface;
    final nextHop = _remoteRouteNextHop;
    _remoteRouteIp = null;
    _remoteRouteInterface = null;
    _remoteRouteNextHop = null;
    if (ip == null || interfaceAlias == null || nextHop == null) {
      return;
    }
    await _runNetsh([
      'interface',
      'ipv4',
      'delete',
      'route',
      '$ip/32',
      interfaceAlias,
      nextHop,
    ], allowFailure: true);
  }

  Future<void> _runNetsh(List<String> args, {bool allowFailure = false}) async {
    LogService.instance.debug('netsh ${args.join(' ')}');
    final result = await Process.run('netsh.exe', args);
    if (allowFailure || result.exitCode == 0) {
      LogService.instance.debug(
        'netsh completed exit=${result.exitCode} allowFailure=$allowFailure',
      );
      return;
    }
    throw PlatformException(
      code: 'netsh_failed',
      message:
          'netsh ${args.join(' ')} failed: ${result.stderr}${result.stdout}',
    );
  }
}

class _WindowsWintunTools {
  const _WindowsWintunTools({
    required this.tun2socksPath,
    required this.directory,
  });

  final String tun2socksPath;
  final String directory;
}

class _WindowsRoute {
  const _WindowsRoute({
    required this.ip,
    required this.interfaceAlias,
    required this.nextHop,
  });

  final String ip;
  final String interfaceAlias;
  final String nextHop;
}

class WindowsNetworkInspector {
  static Future<List<String>> localProxyIps() async {
    LogService.instance.debug('Windows local proxy IP inspection started');
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
          LogService.instance.debug(
            'Windows local proxy IP accepted interface=${interface.name} address=$value',
          );
        }
      }
    }
    final sorted = values.toList()
      ..sort((first, second) {
        final firstPrivate = _privateScore(first);
        final secondPrivate = _privateScore(second);
        if (firstPrivate != secondPrivate) {
          return secondPrivate.compareTo(firstPrivate);
        }
        return first.compareTo(second);
      });
    LogService.instance.debug('Windows local proxy IPs: $sorted');
    return sorted;
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
    } catch (error, stack) {
      LogService.instance.debug(
        'Windows local proxy IP bind probe failed host=$host',
        error: error,
        stack: stack,
      );
      return false;
    } finally {
      await socket?.close();
    }
  }
}

class WindowsLocalistDiscoveryResponder {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Future<List<SmartProxyEndpoint>> Function()? _endpointsProvider;
  Future<List<SmartProxyEndpoint>>? _endpointsLoader;
  List<SmartProxyEndpoint> _cachedEndpoints = const [];
  DateTime? _cachedEndpointsAt;
  final Map<String, DateTime> _lastResponseByPeer = {};
  String? _deviceId;
  String? _deviceName;

  Future<void> start(
    Future<List<SmartProxyEndpoint>> Function() endpointsProvider,
  ) async {
    LogService.instance.debug('Windows discovery responder starting');
    await stop();
    _endpointsProvider = endpointsProvider;
    _deviceId = await localistDiscoveryDeviceId();
    _deviceName = await localistDiscoveryDeviceName();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      localistDiscoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    socket
      ..broadcastEnabled = true
      ..multicastLoopback = false;
    await _joinMulticast(socket);
    _subscription = socket.listen(_handleSocketEvent, onError: (_) {});
    LogService.instance.debug(
      'Windows discovery responder listening port=$localistDiscoveryPort deviceId=$_deviceId',
    );
  }

  Future<void> stop() async {
    LogService.instance.debug('Windows discovery responder stopping');
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _endpointsProvider = null;
    _endpointsLoader = null;
    _cachedEndpoints = const [];
    _cachedEndpointsAt = null;
    _lastResponseByPeer.clear();
    LogService.instance.debug('Windows discovery responder stopped');
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    final group = InternetAddress(localistDiscoveryMulticastAddress);
    try {
      socket.joinMulticast(group);
      LogService.instance.debug('Windows discovery joined multicast default');
    } catch (error, stack) {
      LogService.instance.debug(
        'Windows discovery default multicast join failed',
        error: error,
        stack: stack,
      );
    }
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(group, interface);
        LogService.instance.debug(
          'Windows discovery joined multicast interface=${interface.name}',
        );
      } catch (error, stack) {
        LogService.instance.debug(
          'Windows discovery multicast join failed interface=${interface.name}',
          error: error,
          stack: stack,
        );
      }
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      unawaited(_handleDatagram(datagram!));
    }
  }

  Future<void> _handleDatagram(Datagram datagram) async {
    LogService.instance.debug(
      'Windows discovery query datagram from ${datagram.address.address}:${datagram.port} bytes=${datagram.data.length}',
    );
    final map = decodeLocalistDiscoveryPacket(datagram.data);
    if (map == null || !isLocalistDiscoveryQuery(map)) {
      LogService.instance.debug('Windows discovery ignored non-query packet');
      return;
    }
    if (map['deviceId'] == _deviceId) {
      LogService.instance.debug('Windows discovery ignored own query');
      return;
    }
    final now = DateTime.now();
    final peerKey = '${datagram.address.address}:${datagram.port}';
    if (_isPeerRateLimited(peerKey, now)) {
      LogService.instance.debug('Windows discovery rate limited peer=$peerKey');
      return;
    }
    final endpointsProvider = _endpointsProvider;
    final deviceId = _deviceId;
    final deviceName = _deviceName;
    final socket = _socket;
    if (endpointsProvider == null ||
        deviceId == null ||
        deviceName == null ||
        socket == null) {
      LogService.instance.debug('Windows discovery responder not ready');
      return;
    }
    final endpoints = await _loadEndpoints(endpointsProvider);
    if (endpoints.isEmpty) {
      LogService.instance.debug(
        'Windows discovery has no endpoints to announce',
      );
      return;
    }
    final response = utf8.encode(
      encodeLocalistDiscoveryAnnouncement(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: localistDiscoveryPlatformName(),
        endpoints: endpoints,
      ),
    );
    try {
      socket.send(response, datagram.address, datagram.port);
      LogService.instance.debug(
        'Windows discovery announcement sent to ${datagram.address.address}:${datagram.port} endpoints=${endpoints.length}',
      );
    } catch (error, stack) {
      LogService.instance.debug(
        'Windows discovery announcement send failed',
        error: error,
        stack: stack,
      );
    }
  }

  Future<List<SmartProxyEndpoint>> _loadEndpoints(
    Future<List<SmartProxyEndpoint>> Function() endpointsProvider,
  ) {
    final cachedAt = _cachedEndpointsAt;
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _endpointCacheTtl) {
      return Future.value(_cachedEndpoints);
    }
    final activeLoader = _endpointsLoader;
    if (activeLoader != null) {
      return activeLoader;
    }
    final loader = endpointsProvider()
        .timeout(_endpointLoadTimeout)
        .then((endpoints) {
          _cachedEndpoints = endpoints;
          _cachedEndpointsAt = DateTime.now();
          LogService.instance.debug(
            'Windows discovery loaded ${endpoints.length} endpoint(s)',
          );
          return endpoints;
        })
        .catchError((Object error) {
          LogService.instance.warning(
            'Local discovery responder could not build endpoints: $error',
          );
          return _cachedEndpoints;
        });
    _endpointsLoader = loader.whenComplete(() => _endpointsLoader = null);
    return _endpointsLoader!;
  }

  bool _isPeerRateLimited(String peerKey, DateTime now) {
    final last = _lastResponseByPeer[peerKey];
    _lastResponseByPeer.removeWhere(
      (_, value) => now.difference(value) > _peerResponseMemory,
    );
    if (last != null && now.difference(last) < _peerResponseInterval) {
      return true;
    }
    _lastResponseByPeer[peerKey] = now;
    return false;
  }

  static const _endpointCacheTtl = Duration(seconds: 2);
  static const _endpointLoadTimeout = Duration(seconds: 2);
  static const _peerResponseInterval = Duration(milliseconds: 750);
  static const _peerResponseMemory = Duration(minutes: 1);
}

class WindowsProxyServer {
  WindowsProxyServer({
    required this.protocols,
    required this.ports,
    required this.bindAddresses,
    required this.upstreamProxy,
    required this.onTraffic,
  });

  final Set<ProxyProtocol> protocols;
  final Map<ProxyProtocol, int> ports;
  final Set<String> bindAddresses;
  final RemoteProxyConfig? upstreamProxy;
  final void Function(int uploadedBytes, int downloadedBytes) onTraffic;
  final List<ServerSocket> _servers = [];
  bool _running = false;

  Future<void> start() async {
    if (_running) {
      LogService.instance.debug('Windows proxy server start skipped: running');
      return;
    }
    _running = true;
    final addresses = bindAddresses.isEmpty ? const ['0.0.0.0'] : bindAddresses;
    LogService.instance.debug(
      'Windows proxy server starting protocols=${protocols.map((value) => value.name).join(',')} addresses=$addresses ports=$ports upstream=${upstreamProxy?.url}',
    );
    try {
      for (final protocol in protocols) {
        final port = ports[protocol] ?? protocol.defaultPort;
        for (final address in addresses) {
          final server = await ServerSocket.bind(
            InternetAddress(address),
            port,
          );
          _servers.add(server);
          LogService.instance.debug(
            'Windows proxy listener bound protocol=${protocol.name} address=$address port=$port',
          );
          server.listen(
            (client) => unawaited(_handleClient(protocol, client)),
            onError: (_) {},
            cancelOnError: false,
          );
        }
      }
    } catch (error) {
      LogService.instance.debug(
        'Windows proxy server start failed',
        error: error,
      );
      await stop();
      throw PlatformException(
        code: 'port_unavailable',
        message: 'Unable to bind proxy listener: $error',
      );
    }
  }

  Future<void> stop() async {
    LogService.instance.debug(
      'Windows proxy server stopping listeners=${_servers.length}',
    );
    _running = false;
    for (final server in _servers) {
      await server.close();
    }
    _servers.clear();
    LogService.instance.debug('Windows proxy server stopped');
  }

  Future<void> _handleClient(ProxyProtocol protocol, Socket client) async {
    final reader = _SocketReader(client);
    final peer = '${client.remoteAddress.address}:${client.remotePort}';
    LogService.instance.debug(
      'Windows proxy client accepted protocol=${protocol.name} peer=$peer',
    );
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      if (protocol == ProxyProtocol.http) {
        await _handleHttp(client, reader);
      } else {
        await _handleSocks5(client, reader);
      }
    } catch (error, stack) {
      LogService.instance.debug(
        'Windows proxy client failed protocol=${protocol.name} peer=$peer',
        error: error,
        stack: stack,
      );
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
    LogService.instance.debug('SOCKS5 proxy request target=$host:$targetPort');
    final remote = await _connectProxyTarget(upstreamProxy, host, targetPort);
    client.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    await client.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: remote.reader,
      rightSocket: remote.socket,
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
      LogService.instance.debug(
        'HTTP CONNECT proxy request target=${target.host}:${target.port}',
      );
      final remote = await _connectProxyTarget(
        upstreamProxy,
        target.host,
        target.port,
      );
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
    LogService.instance.debug(
      'HTTP proxy request method=${firstParts[0]} target=$host:$targetPort',
    );
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

    final remote = await _connectProxyTarget(upstreamProxy, host, targetPort);
    remote.socket.add(ascii.encode(rebuilt.toString()));
    await remote.socket.flush();
    await _relay(
      leftReader: reader,
      leftSocket: client,
      rightReader: remote.reader,
      rightSocket: remote.socket,
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
    LogService.instance.debug('Windows proxy relay closing');
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
    LogService.instance.debug(
      'Windows local forwarder binding 127.0.0.1:$localPort remote=$remoteProtocol://$remoteHost:$remotePort',
    );
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    _server!.listen(
      (client) => unawaited(_handleClient(client)),
      onError: (_) {},
      cancelOnError: false,
    );
    LogService.instance.debug(
      'Windows local forwarder listening on $localPort',
    );
  }

  Future<void> stop() async {
    LogService.instance.debug('Windows local forwarder stopping');
    await _server?.close();
    _server = null;
    LogService.instance.debug('Windows local forwarder stopped');
  }

  Future<void> _handleClient(Socket client) async {
    final reader = _SocketReader(client);
    final peer = '${client.remoteAddress.address}:${client.remotePort}';
    LogService.instance.debug('Windows local forwarder client accepted $peer');
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      final first = await reader.readByte();
      reader.unreadByte(first);
      if (first == 0x05) {
        await _handleSocks5Client(client, reader);
      } else {
        await _handleHttpClient(client, reader);
      }
    } catch (error, stack) {
      LogService.instance.debug(
        'Windows local forwarder client failed $peer',
        error: error,
        stack: stack,
      );
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
    LogService.instance.debug(
      'Local forwarder SOCKS5 request target=$targetHost:$targetPort',
    );
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
      LogService.instance.debug(
        'Local forwarder HTTP CONNECT target=${target.host}:${target.port}',
      );
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
    LogService.instance.debug(
      'Local forwarder HTTP request method=${firstParts[0]} target=$host:$targetPort',
    );
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
    return _connectProxyTarget(
      RemoteProxyConfig(
        protocol: remoteProtocol,
        host: remoteHost,
        port: remotePort,
      ),
      targetHost,
      targetPort,
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
    LogService.instance.debug('Windows local forwarder relay closing');
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

Future<_ProxyConnection> _connectProxyTarget(
  RemoteProxyConfig? proxy,
  String targetHost,
  int targetPort,
) async {
  if (proxy == null) {
    LogService.instance.debug(
      'Direct TCP connect start $targetHost:$targetPort',
    );
    final socket = await Socket.connect(
      targetHost,
      targetPort,
      timeout: const Duration(seconds: 10),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    LogService.instance.debug(
      'Direct TCP connect success $targetHost:$targetPort',
    );
    return _ProxyConnection(socket: socket, reader: _SocketReader(socket));
  }

  LogService.instance.debug(
    'Proxy TCP connect start proxy=${proxy.url} target=$targetHost:$targetPort',
  );
  final socket = await Socket.connect(
    proxy.host,
    proxy.port,
    timeout: const Duration(seconds: 10),
  );
  socket.setOption(SocketOption.tcpNoDelay, true);
  final reader = _SocketReader(socket);
  try {
    if (proxy.protocol == ProxyProtocol.http) {
      LogService.instance.debug(
        'HTTP upstream CONNECT start $targetHost:$targetPort',
      );
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
        throw StateError('Remote HTTP proxy refused $targetHost:$targetPort');
      }
      LogService.instance.debug(
        'HTTP upstream CONNECT accepted $targetHost:$targetPort',
      );
    } else {
      LogService.instance.debug(
        'SOCKS5 upstream CONNECT start $targetHost:$targetPort',
      );
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();
      final version = await reader.readByte();
      final method = await reader.readByte();
      if (version != 0x05 || method != 0x00) {
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
      final replyVersion = await reader.readByte();
      final replyCode = await reader.readByte();
      await reader.readByte();
      final addressType = await reader.readByte();
      if (replyVersion != 0x05 || replyCode != 0x00) {
        throw StateError('Remote SOCKS5 refused $targetHost:$targetPort');
      }
      await _readSocksHost(reader, addressType);
      await reader.readPort();
      LogService.instance.debug(
        'SOCKS5 upstream CONNECT accepted $targetHost:$targetPort',
      );
    }
    LogService.instance.debug(
      'Proxy TCP connect success proxy=${proxy.url} target=$targetHost:$targetPort',
    );
    return _ProxyConnection(socket: socket, reader: reader);
  } catch (error, stack) {
    LogService.instance.debug(
      'Proxy TCP connect failed proxy=${proxy.url} target=$targetHost:$targetPort',
      error: error,
      stack: stack,
    );
    socket.destroy();
    await reader.cancel();
    rethrow;
  }
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
        _pauseIfNeeded();
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
  bool _paused = false;

  void unreadByte(int value) {
    _buffer.addFirst(value);
  }

  Future<int> readByte() async {
    await _ensureAvailable(1);
    final value = _buffer.removeFirst();
    _resumeIfNeeded();
    return value;
  }

  Future<List<int>> readExact(int count) async {
    await _ensureAvailable(count);
    final bytes = [for (var i = 0; i < count; i++) _buffer.removeFirst()];
    _resumeIfNeeded();
    return bytes;
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
    final count = _buffer.length > _maxRelayChunk
        ? _maxRelayChunk
        : _buffer.length;
    final chunk = [for (var i = 0; i < count; i++) _buffer.removeFirst()];
    _resumeIfNeeded();
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

  void _pauseIfNeeded() {
    if (_paused || _buffer.length < _highWaterMark) {
      return;
    }
    _paused = true;
    _subscription.pause();
  }

  void _resumeIfNeeded() {
    if (!_paused || _buffer.length > _lowWaterMark) {
      return;
    }
    _paused = false;
    _subscription.resume();
  }

  static const _maxRelayChunk = 64 * 1024;
  static const _highWaterMark = 256 * 1024;
  static const _lowWaterMark = 96 * 1024;
}
