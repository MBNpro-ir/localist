// ignore_for_file: avoid_relative_lib_imports

import '../lib/models/developer_bridge_models.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  check(
    AdbEndpoint.tryParse('192.168.4.2:5555')?.value == '192.168.4.2:5555',
    'IPv4 endpoint parsing failed',
  );
  check(
    AdbEndpoint.tryParse('[fe80::1]:37123')?.value == '[fe80::1]:37123',
    'IPv6 endpoint parsing failed',
  );
  for (final value in [
    '192.168.4.2:0',
    '192.168.4.2:65536',
    '192.168.4.2:5555;whoami',
    '-help:5555',
    '999.999.4.2:5555',
  ]) {
    check(
      AdbEndpoint.tryParse(value) == null,
      'Accepted invalid endpoint $value',
    );
  }

  final devices = parseAdbDevices('''
List of devices attached
192.168.4.2:5555 device model:Pixel_8
usb-1 offline
usb-2 unauthorized
''');
  check(devices.length == 3, 'ADB device list parsing failed');
  check(devices[0].model == 'Pixel_8', 'ADB model parsing failed');
  check(
    devices[1].status == AdbDeviceStatus.offline,
    'Offline status parsing failed',
  );
  check(
    devices[2].status == AdbDeviceStatus.unauthorized,
    'Unauthorized status parsing failed',
  );

  final services = parseAdbMdnsServices('''
List of discovered mdns services
adb-123._adb-tls-pairing._tcp. 192.168.4.2:37123
adb-123._adb-tls-connect._tcp. 192.168.4.2:42217
''');
  check(services.length == 2, 'mDNS service parsing failed');
  check(services[0].pairing, 'Pairing endpoint kind was lost');
  check(!services[1].pairing, 'Connect endpoint kind was lost');
  check(
    services[0].endpoint.port != services[1].endpoint.port,
    'Pairing and connection ports were not kept separate',
  );

  check(
    classifyAdbFailure('error: device unauthorized') ==
        DeveloperBridgeErrorCode.deviceUnauthorized,
    'Unauthorized error classification failed',
  );
  check(
    classifyAdbFailure('failed to connect: connection refused') ==
        DeveloperBridgeErrorCode.endpointUnreachable,
    'Unreachable error classification failed',
  );
  check(
    classifyAdbFailure('', timedOut: true) ==
        DeveloperBridgeErrorCode.commandTimedOut,
    'Timeout error classification failed',
  );
  check(
    classifyAdbFailure('pairing required') ==
        DeveloperBridgeErrorCode.pairingRequired,
    'Pairing-required error classification failed',
  );
  check(
    classifyAdbFailure('mDNS subsystem unavailable') ==
        DeveloperBridgeErrorCode.wirelessDebuggingUnsupported,
    'Wireless debugging support error classification failed',
  );
  check(
    classifyAdbFailure('TLS authentication failed') ==
        DeveloperBridgeErrorCode.tlsAuthenticationFailed,
    'TLS authentication error classification failed',
  );
}
