import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localist/remote/desktop_host_bridge.dart';
import 'package:localist/remote/desktop_host_runtime.dart';
import 'package:localist/remote/remote_peer_presence.dart';

void main() {
  late Directory directory;
  late File statusFile;
  late DesktopHostBridge bridge;
  late DesktopHostRuntime runtime;
  var starts = 0;
  var readyOnStart = true;
  var retireAllowed = true;
  var running = false;
  final retired = <int>[];
  const path = r'C:\Localist\LocalistRemote.exe';

  Map<String, dynamic> status(int pid, {Map<String, dynamic>? overrides}) => {
    'statusVersion': desktopHostStatusVersion,
    'hostExecutable': path,
    'hostFingerprint': 'bundled-digest',
    'pid': pid,
    'ready': true,
    'updatedMs': DateTime.now().millisecondsSinceEpoch,
    'activeSessions': 0,
    ...bridge.endpoint,
    ...?overrides,
  };
  Future<void> write(Map<String, dynamic> value) =>
      statusFile.writeAsString(jsonEncode(value));

  setUp(() async {
    starts = 0;
    readyOnStart = true;
    retireAllowed = true;
    running = false;
    retired.clear();
    directory = await Directory.systemTemp.createTemp('localist-host-runtime');
    statusFile = File('${directory.path}/status.json');
    bridge = DesktopHostBridge(
      openSession: (_) async {},
      queryPresence: (_) async {},
      synchronize: () async {},
      presence: RemotePeerPresenceStore(),
    );
    await bridge.start();
    runtime = DesktopHostRuntime(
      statusFile: statusFile,
      executablePath: path,
      fingerprint: () async => 'bundled-digest',
      isHostRunning: (_) async => running,
      retireHost: (value) async {
        retired.add(value['pid'] as int);
        return retireAllowed;
      },
      startHost: () async {
        starts++;
        if (readyOnStart) await write(status(200 + starts));
        return DesktopHostProcess(200 + starts, Completer<int>().future);
      },
      startupTimeout: const Duration(milliseconds: 100),
      pollInterval: const Duration(milliseconds: 5),
    );
  });
  tearDown(() async {
    await bridge.close();
    await directory.delete(recursive: true);
  });

  test(
    'adopts only a current bundle after authenticated health check',
    () async {
      await write(status(100));
      await runtime.ensureStarted();
      expect(starts, 0);
      expect(retired, isEmpty);
      await runtime.stop();
      expect(retired, [100]);
      expect(await statusFile.exists(), false);
    },
  );

  test(
    'old versions, paths and fingerprints are replaced before startup',
    () async {
      for (final overrides in [
        {'statusVersion': 1},
        {'hostExecutable': r'C:\OldBuild\LocalistRemote.exe'},
        {'hostFingerprint': 'previous-release'},
      ]) {
        await write(status(100, overrides: overrides));
        await runtime.ensureStarted();
        expect((await runtime.status())!['pid'], 200 + starts);
      }
      expect(starts, 3);
      expect(retired, [100, 100, 100]);
    },
  );

  test('recent dead endpoint is not adopted; readiness is rechecked', () async {
    await write(status(100));
    await runtime.ensureStarted();
    await write(status(100, overrides: {'commandToken': 'wrong-token'}));
    await runtime.ensureStarted();
    expect(starts, 1);
    expect(retired, [100]);
  });

  test(
    'stale active session record cannot permanently block recovery',
    () async {
      await write(
        status(
          100,
          overrides: {
            'updatedMs': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'activeSessions': 2,
            'commandToken': 'dead-host-token',
          },
        ),
      );
      expect(await runtime.status(), isNull);
      await runtime.ensureStarted();
      expect(starts, 1);
    },
  );

  test('live session in a different bundle is protected', () async {
    await write(
      status(
        100,
        overrides: {'hostFingerprint': 'other-bundle', 'activeSessions': 1},
      ),
    );
    await expectLater(runtime.ensureStarted(), throwsStateError);
    expect(starts, 0);
    expect(retired, isEmpty);
    await runtime.stop();
    expect(await statusFile.exists(), true);
  });

  test('concurrent startup requests launch once', () async {
    await Future.wait(List.generate(10, (_) => runtime.ensureStarted()));
    expect(starts, 1);
  });

  test(
    'timeout retires the partial process and allows a clean retry',
    () async {
      readyOnStart = false;
      await expectLater(
        runtime.ensureStarted(),
        throwsA(isA<TimeoutException>()),
      );
      expect(retired, [201]);
      await runtime.stop();
      readyOnStart = true;
      await runtime.ensureStarted();
      expect(starts, 2);
    },
  );

  test(
    'malformed status is removed without authorizing a process kill',
    () async {
      await write({'pid': 'bad', 'updatedMs': 'bad', 'activeSessions': 'bad'});
      await runtime.ensureStarted();
      expect(starts, 1);
      expect(retired, isEmpty);
    },
  );

  test(
    'denied retirement stops recovery and preserves the old status',
    () async {
      await write(status(100, overrides: {'statusVersion': 1}));
      retireAllowed = false;
      await expectLater(runtime.ensureStarted(), throwsStateError);
      expect(starts, 0);
      expect(jsonDecode(await statusFile.readAsString())['pid'], 100);
    },
  );

  test('closing one bundle leaves a replacement status untouched', () async {
    await runtime.ensureStarted();
    await write(status(999));
    await runtime.stop();
    expect(retired, [201]);
    expect(jsonDecode(await statusFile.readAsString())['pid'], 999);
  });

  test(
    'a busy live host keeps its PID and sessions despite a stale heartbeat',
    () async {
      running = true;
      await write(
        status(
          100,
          overrides: {
            'commandToken': 'unresponsive-during-window-creation',
            'updatedMs': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'activeSessions': 0,
          },
        ),
      );
      await runtime.ensureStarted();
      expect((await runtime.status())!['pid'], 100);
      expect(starts, 0);
      expect(retired, isEmpty);
    },
  );

  test(
    'a busy foreign host with active sessions cannot be terminated',
    () async {
      running = true;
      await write(
        status(
          100,
          overrides: {
            'hostFingerprint': 'other-bundle',
            'commandToken': 'unresponsive',
            'updatedMs': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'activeSessions': 2,
          },
        ),
      );
      await expectLater(runtime.ensureStarted(), throwsStateError);
      expect(starts, 0);
      expect(retired, isEmpty);
    },
  );

  test(
    'slow heartbeat with a responsive active session is protected',
    () async {
      await write(
        status(
          100,
          overrides: {
            'hostFingerprint': 'other-bundle',
            'updatedMs': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'activeSessions': 1,
          },
        ),
      );
      await expectLater(runtime.ensureStarted(), throwsStateError);
      expect(retired, isEmpty);
    },
  );

  test(
    'recycled PID uses its original heartbeat and preserves new status',
    () async {
      await runtime.ensureStarted();
      final original = jsonDecode(await statusFile.readAsString()) as Map;
      await write(
        status(201, overrides: {'commandToken': 'replacement-token'}),
      );
      await runtime.stop();
      expect(retired, [201]);
      expect(
        jsonDecode(await statusFile.readAsString())['commandToken'],
        'replacement-token',
      );
      expect(original['commandToken'], isNot('replacement-token'));
    },
  );
}
