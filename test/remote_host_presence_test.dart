import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/remote/desktop_host_bridge.dart';
import 'package:localist/remote/remote_peer_presence.dart';
import 'package:localist/services/remote_device_service.dart';

void main() {
  test('native online/offline expires; missing IDs remain unknown', () {
    var now = DateTime(2026);
    final presence = RemotePeerPresenceStore(now: () => now);
    presence.applyEvent({'onlines': '123,234', 'offlines': '345'});
    expect(presence.get('123'), RemotePeerPresence.online);
    expect(presence.get('345'), RemotePeerPresence.offline);
    expect(presence.get('456'), RemotePeerPresence.unknown);
    now = now.add(const Duration(seconds: 30));
    expect(presence.get('123'), RemotePeerPresence.unknown);
    presence.applyEvent({'onlines': '345', 'offlines': ''});
    expect(presence.get('345'), RemotePeerPresence.online);
    presence.clear();
    expect(presence.get('345'), RemotePeerPresence.unknown);
  });

  test(
    'device presence ignores late replies across server changes and disposal',
    () async {
      SharedPreferences.setMockInitialValues({});
      final reply = Completer<Map<String, String>>();
      var calls = 0;
      final service = RemoteDeviceService(
        queryPresence: (ids) {
          calls++;
          return reply.future;
        },
      );
      await service.initialize();
      await service.saveAddress(id: '123', name: 'PC');
      service.setPresenceContext(server: 'private', ready: true);
      final pending = service.refreshPresence();
      await service.refreshPresence().timeout(
        const Duration(milliseconds: 1),
        onTimeout: () {},
      );
      expect(calls, 1);
      service.setPresenceContext(server: 'public', ready: true);
      reply.complete({'123': 'online'});
      await pending;
      expect(
        service.presenceOf(service.devices.single),
        RemotePeerPresence.unknown,
      );
      await service.refreshPresence();
      expect(
        service.presenceOf(service.devices.single),
        RemotePeerPresence.online,
      );
      service.setPresenceContext(server: 'public', ready: false);
      expect(
        service.presenceOf(service.devices.single),
        RemotePeerPresence.unknown,
      );
      service.dispose();
      await service.refreshPresence();
      expect(calls, 2);
    },
  );

  test(
    'network failure clears cached status and LAN stays independently reachable',
    () async {
      SharedPreferences.setMockInitialValues({});
      var fail = false;
      final service = RemoteDeviceService(
        queryPresence: (_) async {
          if (fail) throw const SocketException('unavailable');
          return {'123': 'offline'};
        },
      );
      await service.initialize();
      await service.saveAddress(id: '123', name: 'PC');
      service.setPresenceContext(server: 'private', ready: true);
      await service.refreshPresence();
      expect(
        service.presenceOf(service.devices.single),
        RemotePeerPresence.offline,
      );
      fail = true;
      await service.refreshPresence();
      expect(
        service.presenceOf(service.devices.single),
        RemotePeerPresence.unknown,
      );
      expect(
        service.presenceOf(RemoteDevice(id: '123', lastSeen: DateTime.now())),
        RemotePeerPresence.online,
      );
      service.dispose();
    },
  );

  test(
    'old spaced IDs merge without losing address metadata or distinct IDs',
    () async {
      SharedPreferences.setMockInitialValues({
        'remote.devices.v1': jsonEncode([
          {
            'id': '183976',
            'name': 'Home',
            'inAddressBook': true,
            'tags': ['Home'],
            'favorite': true,
          },
          {'id': '183 976', 'name': '', 'lastOpened': '2026-10-12T10:00:00Z'},
          {'id': '1922512264', 'name': 'Phone'},
          {'id': '1992512264', 'name': 'Other'},
        ]),
      });
      final service = RemoteDeviceService();
      await service.initialize();
      expect(service.devices.length, 3);
      final pc = service.devices.singleWhere((d) => d.id == '183976');
      expect(pc.name, 'Home');
      expect(pc.tags, ['Home']);
      expect(pc.favorite, true);
      expect(pc.lastOpened, isNotNull);
      await service.rememberOpened('183 976');
      expect(service.devices.length, 3);
      service.dispose();
    },
  );

  group('retained desktop host dispatcher', () {
    late DesktopHostBridge bridge;
    late RemotePeerPresenceStore presence;
    late List<Map<String, dynamic>> opened;
    late List<List<String>> queried;
    late int synced;
    setUp(() async {
      presence = RemotePeerPresenceStore();
      opened = [];
      queried = [];
      synced = 0;
      bridge = DesktopHostBridge(
        presence: presence,
        synchronize: () async {
          synced++;
        },
        openSession: (session) async {
          opened.add(session);
        },
        queryPresence: (ids) async {
          queried.add(ids);
        },
      );
      await bridge.start();
    });
    tearDown(() async => bridge.close());

    test(
      'all session modes forward target, password and relay to one host',
      () async {
        for (final mode in desktopSessionModes) {
          expect(
            await sendDesktopHostCommand(bridge.endpoint, {
              'command': 'openSession',
              'session': {
                'mode': mode,
                'target': '183976',
                'password': 'temporary-secret',
                'relay': true,
              },
            }),
            {'accepted': true},
          );
        }
        expect(opened.length, desktopSessionModes.length);
        expect(synced, opened.length);
        expect(
          opened.every(
            (s) =>
                s['target'] == '183976' &&
                s['password'] == 'temporary-secret' &&
                s['relay'] == true,
          ),
          true,
        );
      },
    );

    test(
      'authenticated health check confirms the retained host is live',
      () async {
        expect(
          await sendDesktopHostCommand(bridge.endpoint, {'command': 'ping'}),
          {'ready': true},
        );
      },
    );

    test(
      'presence reports confirmed online/offline and unknown separately',
      () async {
        presence.applyEvent({'onlines': '123', 'offlines': '234'});
        expect(
          await sendDesktopHostCommand(bridge.endpoint, {
            'command': 'presence',
            'ids': ['123', '234', '345'],
          }),
          {
            'states': {'123': 'online', '234': 'offline', '345': 'unknown'},
          },
        );
        expect(queried.single, ['123', '234', '345']);
        expect(opened, isEmpty);
      },
    );

    test(
      'untrusted, browser-origin and malformed commands cannot open a window',
      () async {
        Future<int> post(String body, {String? token, String? origin}) async {
          final client = HttpClient()..findProxy = (_) => 'DIRECT';
          try {
            final request = await client.postUrl(
              Uri.parse(
                'http://127.0.0.1:${bridge.endpoint['commandPort']}/command',
              ),
            );
            if (token != null) {
              request.headers.set('X-Localist-Host-Token', token);
            }
            if (origin != null) request.headers.set('Origin', origin);
            request.write(body);
            final response = await request.close();
            await response.drain<void>();
            return response.statusCode;
          } finally {
            client.close(force: true);
          }
        }

        final token = bridge.endpoint['commandToken'] as String;
        expect(await post('{}'), 403);
        expect(
          await post('{}', token: token, origin: 'http://example.test'),
          403,
        );
        for (final body in [
          '[]',
          '{',
          '{"command":"openSession","session":4}',
          '{"command":"openSession","session":{"mode":"connect","target":"--install"}}',
          '{"command":"presence","ids":[5]}',
          '{"command":"presence","ids":["123 456"]}',
          jsonEncode({'command': 'presence', 'ids': List.filled(501, '123')}),
          jsonEncode({
            'command': 'openSession',
            'session': {
              'mode': 'connect',
              'target': '123',
              'password': 'x' * 33000,
            },
          }),
        ]) {
          expect(await post(body, token: token), 400);
        }
        expect(opened, isEmpty);
        expect(synced, 0);
      },
    );

    test(
      'concurrent launches serialize; failed creation does not retry or poison the queue',
      () async {
        await bridge.close();
        final first = Completer<void>();
        final entered = Completer<void>();
        var active = 0, peak = 0, attempts = 0;
        bridge = DesktopHostBridge(
          presence: presence,
          synchronize: () async {},
          queryPresence: (_) async {},
          openSession: (s) async {
            active++;
            if (active > peak) peak = active;
            attempts++;
            try {
              if (s['target'] == '123') {
                entered.complete();
                await first.future;
                throw StateError('secret-password');
              }
            } finally {
              active--;
            }
          },
        );
        await bridge.start();
        Future<Map<String, dynamic>> launch(String target) =>
            sendDesktopHostCommand(bridge.endpoint, {
              'command': 'openSession',
              'session': {'mode': 'connect', 'target': target},
            });
        final failed = expectLater(
          launch('123'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'sanitized error',
              isNot(contains('secret-password')),
            ),
          ),
        );
        await entered.future;
        final second = launch('234');
        first.complete();
        await failed;
        expect(await second, {'accepted': true});
        expect(peak, 1);
        expect(attempts, 2);
      },
    );
  });
}
