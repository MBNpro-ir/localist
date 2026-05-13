import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProxyProtocol {
  http('HTTP', 'http', 2060),
  socks5('SOCKS5', 'socks5', 2080);

  const ProxyProtocol(this.label, this.scheme, this.defaultPort);

  final String label;
  final String scheme;
  final int defaultPort;

  static ProxyProtocol fromName(String? value) {
    return ProxyProtocol.values.firstWhere(
      (protocol) => protocol.name == value,
      orElse: () => ProxyProtocol.socks5,
    );
  }
}

class AppSettings extends ChangeNotifier {
  AppSettings({
    required Set<ProxyProtocol> enabledProtocols,
    required Map<ProxyProtocol, int> protocolPorts,
    required bool shareAllRoutes,
    required Set<String> selectedLocalIps,
    required bool rootRoutingEnabled,
  }) : _enabledProtocols = _coerceProtocols(enabledProtocols),
       _protocolPorts = _coerceProtocolPorts(protocolPorts),
       _shareAllRoutes = shareAllRoutes,
       _selectedLocalIps = {...selectedLocalIps},
       _rootRoutingEnabled = rootRoutingEnabled;

  static const _protocolKey = 'proxy.protocol';
  static const _protocolsKey = 'proxy.protocols';
  static const _portKey = 'proxy.port';
  static const _httpPortKey = 'proxy.port.http';
  static const _socks5PortKey = 'proxy.port.socks5';
  static const _shareAllRoutesKey = 'sharing.shareAllRoutes';
  static const _legacySelectiveKey = 'vpn.selectiveSharing';
  static const _selectedLocalIpsKey = 'sharing.selectedLocalIps';
  static const _rootRoutingKey = 'root.routingEnabled';

  Set<ProxyProtocol> _enabledProtocols;
  Map<ProxyProtocol, int> _protocolPorts;
  bool _shareAllRoutes;
  Set<String> _selectedLocalIps;
  bool _rootRoutingEnabled;

  Set<ProxyProtocol> get enabledProtocols =>
      Set.unmodifiable(_enabledProtocols);
  ProxyProtocol get protocol => _enabledProtocols.first;
  int get port => portFor(protocol);
  Map<ProxyProtocol, int> get protocolPorts => Map.unmodifiable(_protocolPorts);
  bool get shareAllRoutes => _shareAllRoutes;
  Set<String> get selectedLocalIps => Set.unmodifiable(_selectedLocalIps);
  bool get rootRoutingEnabled => _rootRoutingEnabled;

  int portFor(ProxyProtocol protocol) {
    return _protocolPorts[protocol] ?? protocol.defaultPort;
  }

  String proxyUrl(ProxyProtocol protocol, {String host = '192.168.43.1'}) {
    return '${protocol.scheme}://$host:${portFor(protocol)}';
  }

  bool isProtocolEnabled(ProxyProtocol protocol) {
    return _enabledProtocols.contains(protocol);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedProtocols = prefs.getStringList(_protocolsKey);
    final legacyProtocol = prefs.getString(_protocolKey);
    final legacyPort = prefs.getInt(_portKey);
    final storedSocks5Port = prefs.getInt(_socks5PortKey);
    return AppSettings(
      enabledProtocols: storedProtocols == null && legacyProtocol == null
          ? _defaultProtocols
          : storedProtocols == null
          ? {ProxyProtocol.fromName(legacyProtocol)}
          : storedProtocols.map(ProxyProtocol.fromName).toSet(),
      protocolPorts: {
        ProxyProtocol.http:
            prefs.getInt(_httpPortKey) ?? ProxyProtocol.http.defaultPort,
        ProxyProtocol.socks5:
            (storedSocks5Port == 2070 ? null : storedSocks5Port) ??
            (legacyPort == 2070 ? null : legacyPort) ??
            ProxyProtocol.socks5.defaultPort,
      },
      shareAllRoutes:
          prefs.getBool(_shareAllRoutesKey) ??
          (prefs.getBool(_legacySelectiveKey) == null
              ? true
              : !(prefs.getBool(_legacySelectiveKey) ?? false)),
      selectedLocalIps:
          prefs.getStringList(_selectedLocalIpsKey)?.toSet() ?? const {},
      rootRoutingEnabled: prefs.getBool(_rootRoutingKey) ?? false,
    );
  }

  Future<void> setProtocolEnabled(ProxyProtocol protocol, bool enabled) async {
    final next = {..._enabledProtocols};
    if (enabled) {
      next.add(protocol);
    } else if (next.length > 1) {
      next.remove(protocol);
    }
    await setEnabledProtocols(next);
  }

  Future<void> setEnabledProtocols(Set<ProxyProtocol> values) async {
    final safeValues = _coerceProtocols(values);
    if (_setEquals(_enabledProtocols, safeValues)) {
      return;
    }
    _enabledProtocols = safeValues;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _protocolsKey,
      _enabledProtocols.map((protocol) => protocol.name).toList(),
    );
    await prefs.setString(_protocolKey, _enabledProtocols.first.name);
  }

  Future<void> setPort(int value) async {
    await setProtocolPort(protocol, value);
  }

  Future<void> setProtocolPort(ProxyProtocol protocol, int value) async {
    final safePort = _coercePort(value, fallback: protocol.defaultPort);
    if (portFor(protocol) == safePort) {
      return;
    }
    _protocolPorts = {..._protocolPorts, protocol: safePort};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portKeyFor(protocol), safePort);
    if (protocol == ProxyProtocol.socks5) {
      await prefs.setInt(_portKey, safePort);
    }
  }

  Future<void> setShareAllRoutes(bool value) async {
    if (_shareAllRoutes == value) {
      return;
    }
    _shareAllRoutes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareAllRoutesKey, value);
  }

  Future<void> setLocalIpSelected(String ip, bool selected) async {
    final next = {..._selectedLocalIps};
    if (selected) {
      next.add(ip);
    } else {
      next.remove(ip);
    }
    if (_setStringEquals(_selectedLocalIps, next)) {
      return;
    }
    _selectedLocalIps = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedLocalIpsKey, next.toList()..sort());
  }

  bool isLocalIpSelected(String ip) {
    return _selectedLocalIps.contains(ip);
  }

  Future<void> setRootRoutingEnabled(bool value) async {
    if (_rootRoutingEnabled == value) {
      return;
    }
    _rootRoutingEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rootRoutingKey, value);
  }

  static const _defaultProtocols = {ProxyProtocol.socks5, ProxyProtocol.http};

  static int _coercePort(int value, {int fallback = 2080}) {
    if (value < 1024) {
      return fallback;
    }
    if (value > 65535) {
      return 65535;
    }
    return value;
  }

  static Set<ProxyProtocol> _coerceProtocols(Set<ProxyProtocol> values) {
    if (values.isEmpty) {
      return _defaultProtocols;
    }
    return {...values};
  }

  static Map<ProxyProtocol, int> _coerceProtocolPorts(
    Map<ProxyProtocol, int> values,
  ) {
    return {
      for (final protocol in ProxyProtocol.values)
        protocol: _coercePort(
          values[protocol] ?? protocol.defaultPort,
          fallback: protocol.defaultPort,
        ),
    };
  }

  static String _portKeyFor(ProxyProtocol protocol) {
    return switch (protocol) {
      ProxyProtocol.http => _httpPortKey,
      ProxyProtocol.socks5 => _socks5PortKey,
    };
  }

  static bool _setEquals(Set<ProxyProtocol> first, Set<ProxyProtocol> second) {
    if (first.length != second.length) {
      return false;
    }
    return first.containsAll(second);
  }

  static bool _setStringEquals(Set<String> first, Set<String> second) {
    if (first.length != second.length) {
      return false;
    }
    return first.containsAll(second);
  }
}
