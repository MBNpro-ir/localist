import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads default proxy settings', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await AppSettings.load();

    expect(settings.protocol, ProxyProtocol.socks5);
    expect(settings.enabledProtocols, {
      ProxyProtocol.http,
      ProxyProtocol.socks5,
    });
    expect(settings.port, 2080);
    expect(settings.portFor(ProxyProtocol.http), 2060);
    expect(settings.portFor(ProxyProtocol.socks5), 2080);
    expect(settings.shareAllRoutes, isTrue);
    expect(settings.selectedLocalIps, isEmpty);
    expect(settings.rootRoutingEnabled, isFalse);
  });
}
