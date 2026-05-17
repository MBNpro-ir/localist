import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/service_state.dart';

const localistDiscoveryType = 'localist.discovery.v1';
const localistDiscoveryQueryOp = 'query';
const localistDiscoveryAnnounceOp = 'announce';
const localistDiscoveryPort = 37888;
const localistDiscoveryMulticastAddress = '239.255.88.88';

const _deviceIdKey = 'localist.discovery.deviceId';

Future<String> localistDiscoveryDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_deviceIdKey);
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }
  final random = Random.secure();
  final bytes = List<int>.generate(15, (_) => random.nextInt(256));
  final id = base64Url.encode(bytes).replaceAll('=', '');
  await prefs.setString(_deviceIdKey, id);
  return id;
}

String localistDiscoveryPlatformName() {
  if (Platform.isWindows) {
    return 'Windows';
  }
  if (Platform.isAndroid) {
    return 'Android';
  }
  return 'Localist';
}

Future<String> localistDiscoveryDeviceName() async {
  final hostname = Platform.localHostname.trim();
  if (hostname.isNotEmpty && hostname.toLowerCase() != 'localhost') {
    return hostname;
  }
  if (Platform.isWindows) {
    return Platform.environment['COMPUTERNAME']?.trim().isNotEmpty == true
        ? Platform.environment['COMPUTERNAME']!.trim()
        : 'Windows PC';
  }
  if (Platform.isAndroid) {
    return 'Android device';
  }
  return 'Localist device';
}

String encodeLocalistDiscoveryQuery({required String deviceId}) {
  return jsonEncode({
    'type': localistDiscoveryType,
    'op': localistDiscoveryQueryOp,
    'deviceId': deviceId,
  });
}

String encodeLocalistDiscoveryAnnouncement({
  required String deviceId,
  required String deviceName,
  required String platform,
  required List<SmartProxyEndpoint> endpoints,
}) {
  return jsonEncode({
    'type': localistDiscoveryType,
    'op': localistDiscoveryAnnounceOp,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'endpoints': endpoints.map((endpoint) => endpoint.toMap()).toList(),
  });
}

Map<Object?, Object?>? decodeLocalistDiscoveryPacket(List<int> data) {
  try {
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is Map<Object?, Object?>) {
      return decoded;
    }
  } catch (_) {
    return null;
  }
  return null;
}

bool isLocalistDiscoveryQuery(Map<Object?, Object?> map) {
  return map['type'] == localistDiscoveryType &&
      map['op'] == localistDiscoveryQueryOp;
}

bool isLocalistDiscoveryAnnouncement(Map<Object?, Object?> map) {
  return map['type'] == localistDiscoveryType &&
      map['op'] == localistDiscoveryAnnounceOp;
}
