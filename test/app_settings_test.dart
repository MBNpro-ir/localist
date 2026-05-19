import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/app_settings.dart';
import 'package:localist/models/service_state.dart';
import 'package:localist/services/app_update_service.dart';
import 'package:localist/services/v2rayng_socks_uri.dart';
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
    expect(settings.language, AppLanguage.system);
    expect(settings.languageSelected, isFalse);
  });

  test('saves app language selection', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();

    await settings.setLanguage(AppLanguage.persian);
    final reloaded = await AppSettings.load();

    expect(reloaded.language, AppLanguage.persian);
    expect(reloaded.languageSelected, isTrue);
    expect(reloaded.locale?.languageCode, 'fa');
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

  test('v2rayNG socks URI uses no-auth socks share format', () {
    final uri = buildV2rayNgSocksUri(
      host: '192.168.1.10',
      port: 3075,
      name: 'Localist Xray 192.168.1.10:3075',
    );

    expect(
      uri,
      'socks://Og@192.168.1.10:3075#Localist%20Xray%20192.168.1.10%3A3075',
    );
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

  test('update asset picker chooses apk for supported abi', () {
    final release = AppRelease(
      name: 'Localist v3.0.0',
      tagName: 'v3.0.0',
      htmlUrl: localistLatestReleaseUrl,
      version: AppVersion.tryParse('v3.0.0')!,
      assets: const [
        UpdateAsset(
          name: 'localist-v3.0.0-android-armeabi-v7a.apk',
          downloadUrl: 'https://example.com/arm.apk',
        ),
        UpdateAsset(
          name: 'localist-v3.0.0-android-arm64-v8a.apk',
          downloadUrl: 'https://example.com/arm64.apk',
        ),
      ],
    );

    final asset = release.pickAndroidAsset(['arm64-v8a', 'armeabi-v7a']);

    expect(asset?.name, contains('arm64-v8a'));
  });

  test('app versions compare semantic parts and build numbers', () {
    final current = AppVersion.tryParse('2.1.0+21')!;
    final next = AppVersion.tryParse('v3.0.0')!;

    expect(next.compareTo(current), greaterThan(0));
    expect(
      AppVersion.tryParse(
        '3.0.0+31',
      )!.compareTo(AppVersion.tryParse('3.0.0+30')!),
      greaterThan(0),
    );
  });
}
