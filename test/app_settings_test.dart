import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/app_settings.dart';
import 'package:localist/models/service_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads default proxy settings', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await AppSettings.load();

    expect(settings.protocol, ProxyProtocol.socks5);
    expect(settings.enabledProtocols, {ProxyProtocol.socks5});
    expect(settings.port, 3075);
    expect(settings.portFor(ProxyProtocol.http), 2060);
    expect(settings.portFor(ProxyProtocol.socks5), 3075);
    expect(settings.shareAllRoutes, isTrue);
    expect(settings.selectedLocalIps, isEmpty);
    expect(settings.rootRoutingEnabled, isFalse);
    expect(settings.windowsCloseBehavior, WindowsCloseBehavior.ask);
    expect(settings.windowsVpnProxyEnabled, isFalse);
    expect(settings.windowsVpnProxyPort, 10808);
  });

  test('saves Windows internal VPN proxy settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();

    await settings.setWindowsVpnProxy(enabled: true, port: 10809);
    final reloaded = await AppSettings.load();

    expect(reloaded.windowsVpnProxyEnabled, isTrue);
    expect(reloaded.windowsVpnProxyPort, 10809);
  });

  test('smart proxy payload uses compact scannable links', () {
    const payload = SmartProxyPayload(
      hotspotSsid: '',
      hotspotPassword: '',
      endpoints: [
        SmartProxyEndpoint(
          protocol: ProxyProtocol.http,
          host: '192.168.1.10',
          port: 2060,
        ),
        SmartProxyEndpoint(
          protocol: ProxyProtocol.socks5,
          host: '192.168.1.10',
          port: 3075,
        ),
      ],
    );

    final encoded = payload.encode();
    final decoded = SmartProxyPayload.tryParse(encoded);

    expect(encoded, startsWith('localist://smart?e='));
    expect(encoded.length, lessThan(90));
    expect(decoded, isNotNull);
    expect(decoded!.endpoints, hasLength(2));
    expect(decoded.endpoints.first.config.url, 'http://192.168.1.10:2060');
    expect(decoded.endpoints.last.config.url, 'socks5://192.168.1.10:3075');
  });

  test('discovered device parses announced endpoints', () {
    final device = LocalistDiscoveredDevice.fromAnnouncement(
      {
        'deviceId': 'source-1',
        'deviceName': 'Office PC',
        'platform': 'Windows',
        'endpoints': [
          {'protocol': 'http', 'host': '192.168.1.20', 'port': 2060},
          {'protocol': 'socks5', 'host': '192.168.1.20', 'port': 3075},
        ],
      },
      sourceAddress: '192.168.1.20',
      lastSeen: DateTime(2026),
    );

    expect(device.id, 'source-1');
    expect(device.name, 'Office PC');
    expect(device.platform, 'Windows');
    expect(device.endpoints, hasLength(2));
    expect(device.payload.encode(), contains('192.168.1.20'));
  });
}
