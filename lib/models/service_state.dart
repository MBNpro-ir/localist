import 'dart:convert';

import 'app_settings.dart';

class UsageStats {
  const UsageStats({
    required this.sessionRxBytes,
    required this.sessionTxBytes,
    required this.totalRxBytes,
    required this.totalTxBytes,
  });

  final int sessionRxBytes;
  final int sessionTxBytes;
  final int totalRxBytes;
  final int totalTxBytes;

  int get sessionTotalBytes => sessionRxBytes + sessionTxBytes;
  int get totalBytes => totalRxBytes + totalTxBytes;

  factory UsageStats.fromMap(Map<Object?, Object?> map) {
    return UsageStats(
      sessionRxBytes: _asInt(map['sessionRxBytes']),
      sessionTxBytes: _asInt(map['sessionTxBytes']),
      totalRxBytes: _asInt(map['totalRxBytes']),
      totalTxBytes: _asInt(map['totalTxBytes']),
    );
  }

  static const empty = UsageStats(
    sessionRxBytes: 0,
    sessionTxBytes: 0,
    totalRxBytes: 0,
    totalTxBytes: 0,
  );
}

class HotspotInfo {
  const HotspotInfo({
    required this.active,
    required this.ssid,
    required this.password,
    required this.ipAddress,
    required this.managedByLocalist,
    required this.systemDetected,
  });

  final bool active;
  final String ssid;
  final String password;
  final String ipAddress;
  final bool managedByLocalist;
  final bool systemDetected;

  String proxyUrl(ProxyProtocol protocol, int port) {
    final host = ipAddress.isEmpty ? '192.168.43.1' : ipAddress;
    return '${protocol.scheme}://$host:$port';
  }

  factory HotspotInfo.fromMap(Map<Object?, Object?> map) {
    return HotspotInfo(
      active: map['active'] == true,
      ssid: (map['ssid'] as String?) ?? 'Android hotspot',
      password: (map['password'] as String?) ?? '',
      ipAddress: (map['ipAddress'] as String?) ?? '192.168.43.1',
      managedByLocalist: map['managedByLocalist'] == true,
      systemDetected: map['systemDetected'] == true,
    );
  }

  static const inactive = HotspotInfo(
    active: false,
    ssid: 'Android hotspot',
    password: '',
    ipAddress: '192.168.43.1',
    managedByLocalist: false,
    systemDetected: false,
  );
}

class RemoteProxyConfig {
  const RemoteProxyConfig({
    required this.protocol,
    required this.host,
    required this.port,
  });

  final ProxyProtocol protocol;
  final String host;
  final int port;

  String get url => '${protocol.scheme}://$host:$port';

  factory RemoteProxyConfig.fromMap(Map<Object?, Object?> map) {
    return RemoteProxyConfig(
      protocol: ProxyProtocol.fromName(map['protocol'] as String?),
      host: (map['host'] as String?) ?? '',
      port: _asInt(map['port'], fallback: ProxyProtocol.socks5.defaultPort),
    );
  }

  Map<String, Object> toMap() {
    return {'protocol': protocol.name, 'host': host, 'port': port};
  }

  static RemoteProxyConfig? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || !uri.hasPort) {
      return null;
    }
    ProxyProtocol? protocol;
    for (final candidate in ProxyProtocol.values) {
      if (candidate.scheme == uri.scheme.toLowerCase()) {
        protocol = candidate;
        break;
      }
    }
    if (protocol == null || uri.port < 1 || uri.port > 65535) {
      return null;
    }
    return RemoteProxyConfig(
      protocol: protocol,
      host: uri.host,
      port: uri.port,
    );
  }
}

class SmartProxyEndpoint {
  const SmartProxyEndpoint({
    required this.protocol,
    required this.host,
    required this.port,
  });

  final ProxyProtocol protocol;
  final String host;
  final int port;

  String get label => '${protocol.label} $host:$port';
  RemoteProxyConfig get config =>
      RemoteProxyConfig(protocol: protocol, host: host, port: port);

  Map<String, Object> toMap() {
    return {'protocol': protocol.name, 'host': host, 'port': port};
  }

  factory SmartProxyEndpoint.fromMap(Map<Object?, Object?> map) {
    return SmartProxyEndpoint(
      protocol: ProxyProtocol.fromName(map['protocol'] as String?),
      host: (map['host'] as String?) ?? '',
      port: _asInt(map['port'], fallback: ProxyProtocol.socks5.defaultPort),
    );
  }
}

class SmartProxyPayload {
  const SmartProxyPayload({
    required this.hotspotSsid,
    required this.hotspotPassword,
    required this.endpoints,
  });

  final String hotspotSsid;
  final String hotspotPassword;
  final List<SmartProxyEndpoint> endpoints;

  String encode() {
    final payload = {
      'type': 'localist.smart.v1',
      'proxies': endpoints.map((endpoint) => endpoint.toMap()).toList(),
    };
    final data = base64Url.encode(utf8.encode(jsonEncode(payload)));
    return 'localist://smart?data=$data';
  }

  static SmartProxyPayload? tryParse(String value) {
    try {
      final trimmed = value.trim();
      String? rawJson;
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.scheme == 'localist' && uri.host == 'smart') {
        final data = uri.queryParameters['data'];
        if (data != null) {
          rawJson = utf8.decode(base64Url.decode(base64Url.normalize(data)));
        }
      } else if (trimmed.startsWith('{')) {
        rawJson = trimmed;
      }
      if (rawJson == null) {
        return null;
      }
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<Object?, Object?> ||
          decoded['type'] != 'localist.smart.v1') {
        return null;
      }
      final hotspot = decoded['hotspot'] as Map<Object?, Object?>? ?? const {};
      final endpoints =
          (decoded['proxies'] as List<Object?>?)
              ?.whereType<Map<Object?, Object?>>()
              .map(SmartProxyEndpoint.fromMap)
              .where((endpoint) => endpoint.host.isNotEmpty)
              .toList() ??
          const [];
      if (endpoints.isEmpty) {
        return null;
      }
      return SmartProxyPayload(
        hotspotSsid: (hotspot['ssid'] as String?) ?? '',
        hotspotPassword: (hotspot['password'] as String?) ?? '',
        endpoints: endpoints,
      );
    } catch (_) {
      return null;
    }
  }
}

class ServiceSnapshot {
  const ServiceSnapshot({
    required this.vpnConnected,
    required this.deviceVpnActive,
    required this.proxyRunning,
    required this.receivingRunning,
    required this.localProxyRunning,
    required this.localProxyPort,
    required this.hotspot,
    required this.protocols,
    required this.protocolPorts,
    required this.port,
    required this.shareAllRoutes,
    required this.localProxyIps,
    required this.usage,
    required this.remoteProxy,
    required this.root,
  });

  final bool vpnConnected;
  final bool deviceVpnActive;
  final bool proxyRunning;
  final bool receivingRunning;
  final bool localProxyRunning;
  final int localProxyPort;
  final HotspotInfo hotspot;
  final Set<ProxyProtocol> protocols;
  final Map<ProxyProtocol, int> protocolPorts;
  final int port;
  final bool shareAllRoutes;
  final List<String> localProxyIps;
  final UsageStats usage;
  final RemoteProxyConfig? remoteProxy;
  final RootRoutingInfo root;

  factory ServiceSnapshot.initial({
    required ProxyProtocol protocol,
    required int port,
  }) {
    return ServiceSnapshot(
      vpnConnected: false,
      deviceVpnActive: false,
      proxyRunning: false,
      receivingRunning: false,
      localProxyRunning: false,
      localProxyPort: 3781,
      hotspot: HotspotInfo.inactive,
      protocols: {protocol},
      protocolPorts: {
        ProxyProtocol.http: ProxyProtocol.http.defaultPort,
        ProxyProtocol.socks5: port,
      },
      port: port,
      shareAllRoutes: true,
      localProxyIps: const [],
      usage: UsageStats.empty,
      remoteProxy: null,
      root: RootRoutingInfo.inactive,
    );
  }

  factory ServiceSnapshot.fromMap(
    Map<Object?, Object?> map, {
    required ProxyProtocol fallbackProtocol,
    required int fallbackPort,
    Map<ProxyProtocol, int>? fallbackPorts,
  }) {
    final protocolNames = (map['protocols'] as List<Object?>?)
        ?.whereType<String>()
        .map(ProxyProtocol.fromName)
        .toSet();
    final protocolName = map['protocol'] as String?;
    final remoteProxyMap = map['remoteProxy'] as Map<Object?, Object?>?;
    final rootMap = map['root'] as Map<Object?, Object?>?;
    final parsedPorts = _parseProtocolPorts(
      map['ports'] as Map<Object?, Object?>?,
      fallbackPorts ??
          {
            ProxyProtocol.http: ProxyProtocol.http.defaultPort,
            ProxyProtocol.socks5: fallbackPort,
          },
    );
    return ServiceSnapshot(
      vpnConnected: map['vpnConnected'] == true,
      deviceVpnActive: map['deviceVpnActive'] == true,
      proxyRunning: map['proxyRunning'] == true,
      receivingRunning: map['receivingRunning'] == true,
      localProxyRunning: map['localProxyRunning'] == true,
      localProxyPort: _asInt(map['localProxyPort'], fallback: 3781),
      hotspot: HotspotInfo.fromMap(
        (map['hotspot'] as Map<Object?, Object?>?) ?? const {},
      ),
      protocols: (protocolNames == null || protocolNames.isEmpty)
          ? {
              protocolName == null
                  ? fallbackProtocol
                  : ProxyProtocol.fromName(protocolName),
            }
          : protocolNames,
      protocolPorts: parsedPorts,
      port: _asInt(
        map['port'],
        fallback: parsedPorts[fallbackProtocol] ?? fallbackPort,
      ),
      shareAllRoutes: map.containsKey('shareAllRoutes')
          ? map['shareAllRoutes'] == true
          : !(map['selectiveSharing'] == true),
      localProxyIps:
          (map['localProxyIps'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      usage: UsageStats.fromMap(
        (map['usage'] as Map<Object?, Object?>?) ?? const {},
      ),
      remoteProxy:
          remoteProxyMap == null ||
              (remoteProxyMap['host'] as String? ?? '').isEmpty
          ? null
          : RemoteProxyConfig.fromMap(remoteProxyMap),
      root: RootRoutingInfo.fromMap(rootMap ?? const {}),
    );
  }

  ServiceSnapshot copyWith({
    bool? vpnConnected,
    bool? deviceVpnActive,
    bool? proxyRunning,
    bool? receivingRunning,
    bool? localProxyRunning,
    int? localProxyPort,
    HotspotInfo? hotspot,
    Set<ProxyProtocol>? protocols,
    Map<ProxyProtocol, int>? protocolPorts,
    int? port,
    bool? shareAllRoutes,
    List<String>? localProxyIps,
    UsageStats? usage,
    RemoteProxyConfig? remoteProxy,
    RootRoutingInfo? root,
  }) {
    return ServiceSnapshot(
      vpnConnected: vpnConnected ?? this.vpnConnected,
      deviceVpnActive: deviceVpnActive ?? this.deviceVpnActive,
      proxyRunning: proxyRunning ?? this.proxyRunning,
      receivingRunning: receivingRunning ?? this.receivingRunning,
      localProxyRunning: localProxyRunning ?? this.localProxyRunning,
      localProxyPort: localProxyPort ?? this.localProxyPort,
      hotspot: hotspot ?? this.hotspot,
      protocols: protocols ?? this.protocols,
      protocolPorts: protocolPorts ?? this.protocolPorts,
      port: port ?? this.port,
      shareAllRoutes: shareAllRoutes ?? this.shareAllRoutes,
      localProxyIps: localProxyIps ?? this.localProxyIps,
      usage: usage ?? this.usage,
      remoteProxy: remoteProxy ?? this.remoteProxy,
      root: root ?? this.root,
    );
  }

  int portFor(ProxyProtocol protocol) {
    return protocolPorts[protocol] ?? protocol.defaultPort;
  }
}

class RootRoutingInfo {
  const RootRoutingInfo({
    required this.available,
    required this.enabled,
    required this.active,
    required this.vpnInterface,
    required this.clientSubnets,
    required this.availableClientSubnets,
    required this.availableLocalIps,
    required this.lastError,
  });

  final bool available;
  final bool enabled;
  final bool active;
  final String vpnInterface;
  final List<String> clientSubnets;
  final List<String> availableClientSubnets;
  final List<String> availableLocalIps;
  final String lastError;

  factory RootRoutingInfo.fromMap(Map<Object?, Object?> map) {
    return RootRoutingInfo(
      available: map['available'] == true,
      enabled: map['enabled'] == true,
      active: map['active'] == true,
      vpnInterface: (map['vpnInterface'] as String?) ?? '',
      clientSubnets:
          (map['clientSubnets'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      availableClientSubnets:
          (map['availableClientSubnets'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      availableLocalIps:
          (map['availableLocalIps'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      lastError: (map['lastError'] as String?) ?? '',
    );
  }

  static const inactive = RootRoutingInfo(
    available: false,
    enabled: false,
    active: false,
    vpnInterface: '',
    clientSubnets: [],
    availableClientSubnets: [],
    availableLocalIps: [],
    lastError: '',
  );
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

Map<ProxyProtocol, int> _parseProtocolPorts(
  Map<Object?, Object?>? value,
  Map<ProxyProtocol, int> fallback,
) {
  return {
    for (final protocol in ProxyProtocol.values)
      protocol: _asInt(
        value?[protocol.name],
        fallback: fallback[protocol] ?? protocol.defaultPort,
      ),
  };
}
