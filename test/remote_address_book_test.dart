import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/models/remote_control_settings.dart';
import 'package:localist/services/remote_device_service.dart';
import 'package:localist/screens/remote_address_book.dart';
import 'package:localist/widgets/remote_ready_indicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'relay defaults follow private-server fields, public settings disable it',
    () {
      expect(const RemoteServerConfig().usesRelay, false);
      expect(
        const RemoteServerConfig(idServer: '81.30.108.248').usesRelay,
        true,
      );
      expect(
        const RemoteServerConfig(relayServer: '81.30.108.248').usesRelay,
        true,
      );
    },
  );
  test(
    'off display defaults do not enable presence-based native session toggles',
    () {
      for (final key in ['swap-left-right-mouse', 'collapse_toolbar', 'i444']) {
        final setting = remoteSettings.singleWhere((s) => s.key == key);
        expect(remoteDisplayValue(setting, 'N'), isEmpty);
        expect(remoteDisplayValue(setting, 'Y'), 'Y');
      }
      final copy = remoteSettings.singleWhere(
        (s) => s.key == 'enable-file-copy-paste',
      );
      expect(remoteDisplayValue(copy, 'N'), 'N');
    },
  );
  test(
    'approval migration enables Accept once and preserves later explicit choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'remote.control.profile.v1': jsonEncode({
          'server': const RemoteServerConfig().encode(),
          'values': {'approve-mode': 'password'},
        }),
      });
      final profile = await RemoteControlProfile.load();
      expect(profile.values['approve-mode'], 'password-click');
      profile.values['approve-mode'] = 'password';
      await profile.save();
      expect(
        (await RemoteControlProfile.load()).values['approve-mode'],
        'password',
      );
      expect(
        RemoteControlProfile().values['verification-method'],
        'use-temporary-password',
      );
    },
  );
  test(
    'address book names, tags and favorites persist; tag rename/removal updates every device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = RemoteDeviceService();
      await first.initialize();
      await first.saveAddress(
        id: '183 976',
        name: 'Home PC',
        tags: ['Home', ' Home ', 'Windows'],
      );
      await first.saveAddress(id: '234567', name: 'Phone', tags: ['Home']);
      await first.setFavorite('183976', true);
      await first.rememberOpened('183976');
      await first.renameTag('Home', 'Family');
      first.dispose();
      final second = RemoteDeviceService();
      await second.initialize();
      final pc = second.devices.singleWhere((d) => d.id == '183976');
      expect(pc.name, 'Home PC');
      expect(pc.favorite, true);
      expect(pc.tags, ['Family', 'Windows']);
      expect(pc.lastOpened, isNotNull);
      expect(second.tags, ['Family', 'Windows']);
      await second.renameTag('Family', '');
      expect(second.devices.every((d) => !d.tags.contains('Family')), true);
      await second.forget('234567');
      expect(second.devices.length, 1);
      second.dispose();
    },
  );
  test(
    'search, intersecting tags, group and deterministic sorting work together',
    () {
      final devices = [
        RemoteDevice(
          id: '2',
          name: 'Zebra PC',
          model: 'Windows',
          tags: ['Home', 'PC'],
          favorite: true,
          lastOpened: DateTime(2026),
        ),
        RemoteDevice(
          id: '1',
          name: 'Alpha Phone',
          tags: ['Home'],
          inAddressBook: true,
          lastSeen: DateTime.now(),
        ),
        const RemoteDevice(id: '3', name: 'Office'),
      ];
      expect(filterRemoteDevices(devices, tags: {'Home', 'PC'}).single.id, '2');
      expect(
        filterRemoteDevices(
          devices,
          group: RemoteDeviceGroup.favorites,
        ).single.id,
        '2',
      );
      expect(
        filterRemoteDevices(devices, group: RemoteDeviceGroup.lan).single.id,
        '1',
      );
      expect(filterRemoteDevices(devices, query: 'windows').single.id, '2');
      expect(
        filterRemoteDevices(
          devices,
          sort: RemoteDeviceSort.name,
        ).map((d) => d.id),
        ['1', '3', '2'],
      );
    },
  );
  for (final width in [360.0, 1360.0]) {
    testWidgets(
      'device card connects directly and excludes self at width $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final service = RemoteDeviceService();
        await service.initialize();
        await service.saveAddress(id: '123456', name: 'My own device');
        await service.saveAddress(
          id: '183976',
          name: 'Home PC',
          tags: ['Home'],
        );
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? connected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RemoteAddressBook(
                  service: service,
                  localId: '123456',
                  canConnect: true,
                  onConnect: (id) => connected = id,
                ),
              ),
            ),
          ),
        );
        expect(find.text('My own device'), findsNothing);
        await tester.tap(find.text('Home PC'));
        await tester.pump();
        expect(connected, '183976');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      },
    );
  }
  testWidgets('readiness shows actual registration and hosting state', (
    tester,
  ) async {
    Future<void> show(bool ready, bool online, bool hosting) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: RemoteReadyIndicator(
                ready: ready,
                online: online,
                hosting: hosting,
                server: '81.30.108.248',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await show(true, false, true);
    expect(find.text('Connecting to server'), findsOneWidget);
    await show(true, true, true);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('81.30.108.248'), findsOneWidget);
    await show(true, true, false);
    expect(find.text('Hosting stopped'), findsOneWidget);
  });
}
