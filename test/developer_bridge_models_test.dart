import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/developer_bridge_models.dart';

void main() {
  group('AdbEndpoint', () {
    test('accepts IPv4 and hostname endpoints with valid ports', () {
      expect(
        AdbEndpoint.tryParse('192.168.4.2:5555')?.value,
        '192.168.4.2:5555',
      );
      expect(
        AdbEndpoint.tryParse('phone.local:37123')?.value,
        'phone.local:37123',
      );
    });

    test('normalizes bracketed IPv6 endpoints', () {
      expect(AdbEndpoint.tryParse('[fe80::1]:37123')?.value, '[fe80::1]:37123');
    });

    test('rejects malformed endpoint input and out-of-range ports', () {
      for (final endpoint in [
        '',
        '192.168.4.2',
        '192.168.4.2:0',
        '192.168.4.2:65536',
        '192.168.4.2:5555;whoami',
        '-help:5555',
        '999.999.4.2:5555',
        'bad.-label.local:5555',
        '[not-ipv6]:5555',
        'phone..local:5555',
      ]) {
        expect(AdbEndpoint.tryParse(endpoint), isNull, reason: endpoint);
      }
    });
  });

  test('parses adb device states without treating headers as devices', () {
    final devices = parseAdbDevices('''
List of devices attached
192.168.4.2:5555 device product:pixel model:Pixel_8 transport_id:2
emulator-5554 offline transport_id:3
USB123 unauthorized usb:1-1
''');

    expect(devices, hasLength(3));
    expect(devices[0].status, AdbDeviceStatus.device);
    expect(devices[0].model, 'Pixel_8');
    expect(devices[1].status, AdbDeviceStatus.offline);
    expect(devices[2].status, AdbDeviceStatus.unauthorized);
    expect(devices[2].isUsb, isTrue);
    expect(devices[0].isUsb, isFalse);
  });

  test('parses separate wireless pairing and connection ports', () {
    final services = parseAdbMdnsServices('''
List of discovered mdns services
adb-123._adb-tls-pairing._tcp. 192.168.4.2:37123
adb-123._adb-tls-connect._tcp. 192.168.4.2:42217
''');

    expect(services, hasLength(2));
    expect(services[0].pairing, isTrue);
    expect(services[0].endpoint.value, '192.168.4.2:37123');
    expect(services[1].pairing, isFalse);
    expect(services[1].endpoint.value, '192.168.4.2:42217');
  });

  test('maps common ADB failures to stable error codes', () {
    expect(
      classifyAdbFailure('error: device unauthorized'),
      DeveloperBridgeErrorCode.deviceUnauthorized,
    );
    expect(
      classifyAdbFailure('failed to connect: connection refused'),
      DeveloperBridgeErrorCode.endpointUnreachable,
    );
    expect(
      classifyAdbFailure('invalid code', pairing: true),
      DeveloperBridgeErrorCode.pairingRejected,
    );
    expect(
      classifyAdbFailure('error: pairing required'),
      DeveloperBridgeErrorCode.pairingRequired,
    );
    expect(
      classifyAdbFailure('mDNS subsystem unavailable'),
      DeveloperBridgeErrorCode.wirelessDebuggingUnsupported,
    );
    expect(
      classifyAdbFailure('TLS authentication failed'),
      DeveloperBridgeErrorCode.tlsAuthenticationFailed,
    );
    expect(
      classifyAdbFailure('', timedOut: true),
      DeveloperBridgeErrorCode.commandTimedOut,
    );
  });
}
