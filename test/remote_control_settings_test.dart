import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/remote_control_settings.dart';
import 'package:localist/services/remote_device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('decodes the supplied server code and round trips it', () {
    final config = RemoteServerConfig.decode(RemoteServerConfig.suppliedCode);
    expect(config.idServer, '81.30.108.248');
    expect(config.relayServer, '81.30.108.248');
    expect(config.apiServer, isEmpty);
    expect(config.key, 'n4Zq55BrNpmfqWENX5ZqO3xo0oCsbASuSO71a5SGk5Y=');
    final decodedAgain = RemoteServerConfig.decode(config.encode());
    expect(decodedAgain.key, config.key);
    expect(decodedAgain.engineOptions['custom-rendezvous-server'], config.idServer);
  });

  test('rejects unsafe or malformed server values', () {
    expect(
      () => RemoteServerConfig.decode(jsonEncode({'host': 'bad host'})),
      throwsFormatException,
    );
    expect(
      () => RemoteServerConfig.decode(jsonEncode({'host': '1.2.3.4', 'key': 'bad'})),
      throwsFormatException,
    );
  });

  test('discovery packet preserves ID, hostname and platform', () {
    List<int> varint(int value) {
      final output = <int>[];
      do {
        output.add((value & 127) | (value > 127 ? 128 : 0));
        value >>= 7;
      } while (value > 0);
      return output;
    }
    List<int> field(int number, String value) {
      final data = utf8.encode(value);
      return [...varint((number << 3) | 2), ...varint(data.length), ...data];
    }
    final peer = [
      ...field(1, 'pong'), ...field(3, '123456'),
      ...field(5, 'Office PC'), ...field(6, 'windows'),
    ];
    final packet = [
      ...varint((22 << 3) | 2), ...varint(peer.length), ...peer,
    ];
    final device = RemoteDiscoveryProtocol.decode(packet, '192.168.1.10');
    expect(device, isNotNull);
    expect(device!.id, '123456');
    expect(device.name, 'Office PC');
    expect(device.platform, 'windows');
    expect(device.ip, '192.168.1.10');
  });

  test('saved devices survive service reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = RemoteDeviceService();
    await first.initialize();
    await first.rememberOpened('123456');
    await first.rename('123456', 'Office PC', 'windows');
    first.dispose();
    final second = RemoteDeviceService();
    await second.initialize();
    expect(second.devices.single.name, 'Office PC');
    expect(second.devices.single.model, 'windows');
    second.dispose();
  });
}
