import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/app_settings.dart';
import 'package:localist/models/service_state.dart';
import 'package:localist/services/proxy_endpoint_resolver.dart';

void main() {
  test('smart payload preserves device identity and endpoints', () {
    const payload = SmartProxyPayload(
      hotspotSsid: '',
      hotspotPassword: '',
      deviceId: 'device-123',
      deviceName: 'Living room PC',
      endpoints: [
        SmartProxyEndpoint(
          protocol: ProxyProtocol.socks5,
          host: '192.168.1.5',
          port: 3075,
        ),
      ],
    );

    final parsed = SmartProxyPayload.tryParse(payload.encode());

    expect(parsed, isNotNull);
    expect(parsed!.deviceId, 'device-123');
    expect(parsed.deviceName, 'Living room PC');
    expect(parsed.endpoints.single.host, '192.168.1.5');
    expect(parsed.endpoints.single.port, 3075);
  });

  test('resolver prefers the address that delivered discovery', () {
    final resolver = ProxyEndpointResolver();
    final phases = resolver.buildCandidatePhases(
      advertisedEndpoints: const [
        SmartProxyEndpoint(
          protocol: ProxyProtocol.socks5,
          host: '10.0.0.10',
          port: 3075,
        ),
      ],
      discoveredDevices: [
        LocalistDiscoveredDevice(
          id: 'device-123',
          name: 'PC',
          platform: 'Windows',
          sourceAddress: '192.168.50.8',
          endpoints: const [
            SmartProxyEndpoint(
              protocol: ProxyProtocol.socks5,
              host: '10.0.0.10',
              port: 3075,
            ),
          ],
          lastSeen: DateTime(2026),
        ),
      ],
      deviceId: 'device-123',
    );

    expect(phases.first.single.host, '192.168.50.8');
    expect(phases.last.single.host, '10.0.0.10');
  });

  test('resolver never substitutes a different device on the same port', () {
    final resolver = ProxyEndpointResolver();
    final phases = resolver.buildCandidatePhases(
      advertisedEndpoints: const [
        SmartProxyEndpoint(
          protocol: ProxyProtocol.socks5,
          host: '10.0.0.10',
          port: 3075,
        ),
      ],
      discoveredDevices: [
        LocalistDiscoveredDevice(
          id: 'different-device',
          name: 'Other PC',
          platform: 'Windows',
          sourceAddress: '192.168.50.99',
          endpoints: const [
            SmartProxyEndpoint(
              protocol: ProxyProtocol.socks5,
              host: '192.168.50.99',
              port: 3075,
            ),
          ],
          lastSeen: DateTime(2026),
        ),
      ],
      deviceId: 'expected-device',
    );

    expect(phases.expand((phase) => phase).map((value) => value.host), [
      '10.0.0.10',
    ]);
  });
}
