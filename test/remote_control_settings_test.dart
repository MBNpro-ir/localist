import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/remote_control_settings.dart';
import 'package:localist/services/remote_device_service.dart';
import 'package:localist/services/rustdesk_debug_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'retained Windows host reads new password policy despite stale preferences cache',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'localist-profile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      String encoded(String method) => jsonEncode({
        'schema': 2,
        'server': const RemoteServerConfig().encode(),
        'values': {'verification-method': method},
      });
      SharedPreferences.setMockInitialValues({
        'remote.control.profile.v1': encoded('use-temporary-password'),
      });
      final file = File('${directory.path}/shared_preferences.json');
      await file.writeAsString(
        jsonEncode({
          'flutter.remote.control.profile.v1': encoded('use-both-passwords'),
        }),
      );
      final fresh = await RemoteControlProfile.load(
        refreshSharedStore: true,
        sharedStore: file,
      );
      expect(fresh.values['verification-method'], 'use-both-passwords');
      expect(
        (await RemoteControlProfile.load()).values['verification-method'],
        'use-temporary-password',
      );
      await file.writeAsString(
        jsonEncode({
          'flutter.remote.control.profile.v1': encoded(
            'use-permanent-password',
          ),
        }),
      );
      expect(
        (await RemoteControlProfile.load(
          refreshSharedStore: true,
          sharedStore: file,
        )).values['verification-method'],
        'use-permanent-password',
      );
    },
  );

  test(
    'partial shared preference writes never silently reset the host profile',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'localist-profile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final file = File('${directory.path}/shared_preferences.json');
      await file.writeAsString('{');
      await expectLater(
        RemoteControlProfile.load(refreshSharedStore: true, sharedStore: file),
        throwsFormatException,
      );
    },
  );
  test(
    'private relay is automatic and clearing servers restores public routing',
    () {
      final private = RemoteControlProfile();
      expect(private.serverOptions['force-always-relay'], 'Y');
      final public = RemoteControlProfile(server: const RemoteServerConfig());
      for (final key in [
        'custom-rendezvous-server',
        'relay-server',
        'api-server',
        'key',
      ]) {
        expect(public.serverOptions[key], isEmpty);
      }
      expect(public.serverOptions['force-always-relay'], 'N');
    },
  );
  test('password policy is part of the native server profile', () {
    final profile = RemoteControlProfile(
      values: {
        'verification-method': 'use-both-passwords',
        'approve-mode': 'password',
        'temporary-password-length': '8',
      },
    );
    expect(profile.serverOptions['verification-method'], 'use-both-passwords');
    expect(profile.serverOptions['approve-mode'], 'password');
    expect(profile.serverOptions['temporary-password-length'], '8');
  });
  test('permanent password validation matches the RustDesk desktop rules', () {
    expect(permanentPasswordValidationError(''), isNull);
    expect(permanentPasswordValidationError('short1A'), isNotNull);
    expect(permanentPasswordValidationError('lowercase1'), isNotNull);
    expect(permanentPasswordValidationError('UPPERCASE1'), isNotNull);
    expect(permanentPasswordValidationError('NoDigitAa'), isNotNull);
    expect(permanentPasswordValidationError('ValidPass1'), isNull);
    expect(permanentPasswordValidationError('A1a' * 43), isNotNull);
    expect(permanentPasswordValidationError('Valid\nPass1'), isNotNull);
  });
  test('setting a password enables it even after manual-only approval', () {
    expect(
      remotePasswordPolicy({
        'verification-method': 'use-temporary-password',
        'approve-mode': 'click',
      }, 'ValidPass1'),
      {
        'verification-method': 'use-both-passwords',
        'approve-mode': 'password-click',
      },
    );
  });
  test(
    'changing a permanent-only password preserves permanent-only policy',
    () {
      expect(
        remotePasswordPolicy({
          'verification-method': 'use-permanent-password',
          'approve-mode': 'password',
        }, 'NewPass12'),
        {'verification-method': 'use-permanent-password'},
      );
    },
  );
  test('removing permanent password enables OTP and keeps approval policy', () {
    expect(
      remotePasswordPolicy({
        'verification-method': 'use-permanent-password',
        'approve-mode': 'click',
      }, ''),
      {'verification-method': 'use-temporary-password'},
    );
  });
  test('decodes the supplied server code and round trips it', () {
    final config = RemoteServerConfig.decode(RemoteServerConfig.suppliedCode);
    expect(config.idServer, '81.30.108.248');
    expect(config.relayServer, '81.30.108.248');
    expect(config.apiServer, isEmpty);
    expect(config.key, 'n4Zq55BrNpmfqWENX5ZqO3xo0oCsbASuSO71a5SGk5Y=');
    final decodedAgain = RemoteServerConfig.decode(config.encode());
    expect(decodedAgain.key, config.key);
    expect(
      decodedAgain.engineOptions['custom-rendezvous-server'],
      config.idServer,
    );
  });

  test('rejects unsafe or malformed server values', () {
    expect(
      () => RemoteServerConfig.decode(jsonEncode({'host': 'bad host'})),
      throwsFormatException,
    );
    expect(
      () => RemoteServerConfig.decode(
        jsonEncode({'host': '1.2.3.4', 'key': 'bad'}),
      ),
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
      ...field(1, 'pong'),
      ...field(3, '123456'),
      ...field(5, 'Office PC'),
      ...field(6, 'windows'),
    ];
    final packet = [...varint((22 << 3) | 2), ...varint(peer.length), ...peer];
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
