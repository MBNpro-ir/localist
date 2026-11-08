import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/services/remote_device_service.dart';
import 'package:localist/services/remote_credential_store.dart';
import 'package:localist/models/remote_control_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
    'reopening the shared address book does not leak periodic discovery timers',
    (tester) async {
      final service = RemoteDeviceService();
      await Future.wait([service.initialize(), service.initialize()]);
      await service.initialize();
      service.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'self identity removes own ID, local IP and alternate native ID on own LAN address',
    () async {
      final service = RemoteDeviceService();
      await service.initialize();
      addTearDown(service.dispose);
      await service.saveAddress(id: '123456', name: 'self');
      await service.saveAddress(id: '192.168.2.10', name: 'self IP');
      await service.saveAddress(id: '654321', name: 'peer');
      service.setLocalIdentity('123 456', addresses: ['192.168.2.10']);
      expect(service.devices.map((d) => d.id), ['654321']);
      expect(
        service.isLocal(
          const RemoteDevice(id: 'another-native-id', ip: '192.168.2.10'),
        ),
        true,
      );
      expect(
        service.isLocal(
          const RemoteDevice(id: '654321', name: 'self', ip: '192.168.2.11'),
        ),
        false,
      );
    },
  );
  test(
    'manual peer password is server-scoped, replaceable and removable without entering address-book JSON',
    () async {
      final store = RemoteCredentialStore();
      await store.write('one.example', '123', 'FirstPass1');
      expect(await store.read('two.example', '123'), null);
      expect(await store.read('one.example', '123'), 'FirstPass1');
      await store.write('one.example', '123', 'NewPass22');
      expect(await store.read('one.example', '123'), 'NewPass22');
      final service = RemoteDeviceService(credentials: store)
        ..credentialServer = 'one.example';
      await service.initialize();
      addTearDown(service.dispose);
      await service.saveAddress(id: '123', name: 'peer');
      expect(
        (await SharedPreferences.getInstance()).getString('remote.devices.v1'),
        isNot(contains('NewPass22')),
      );
      await service.forget('123');
      expect(await store.read('one.example', '123'), null);
    },
  );
  test(
    'only the old bundled server is migrated; custom/public settings are preserved',
    () async {
      for (final code in [
        RemoteServerConfig.legacySuppliedCode,
        const RemoteServerConfig().encode(),
        const RemoteServerConfig(idServer: 'custom.example').encode(),
      ]) {
        SharedPreferences.setMockInitialValues({
          'remote.control.profile.v1': jsonEncode({
            'schema': 2,
            'server': code,
            'values': <String, String>{},
          }),
        });
        final loaded = await RemoteControlProfile.load();
        expect(
          loaded.server.idServer,
          code == RemoteServerConfig.legacySuppliedCode
              ? 'rustdesk.mbnpro.ir'
              : RemoteServerConfig.decode(code).idServer,
        );
        expect(loaded.values['allow-insecure-tls-fallback'], 'Y');
      }
    },
  );
}
