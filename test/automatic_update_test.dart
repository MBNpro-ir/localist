import 'dart:io';
import 'package:flutter/material.dart';
import 'package:localist/widgets/update_action.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:localist/services/app_update_service.dart';
import 'package:localist/services/automatic_update_controller.dart';

class FakeUpdates extends AppUpdateService {
  FakeUpdates(this.file);
  final File file;
  int checks = 0, downloads = 0, preparations = 0;
  bool fail = false;
  AppVersion version = AppVersion.tryParse('6.0.1')!;
  @override
  Future<AppUpdateCheck> checkForUpdate() async {
    checks++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final asset = UpdateAsset(
      name: 'localist-windows-x64.zip',
      downloadUrl: 'https://example.com/$version.zip',
      size: 3,
      digest: 'sha256:${sha256.convert([1, 2, 3])}',
    );
    return AppUpdateCheck(
      current: AppVersion.tryParse('6.0.0')!,
      release: AppRelease(
        name: '6.0.1',
        tagName: 'v6.0.1',
        htmlUrl: '',
        version: version,
        assets: [asset],
      ),
      androidAsset: asset,
      windowsAsset: asset,
      supportedAbis: [],
    );
  }

  @override
  Future<File> downloadWindowsUpdate(
    UpdateAsset asset, {
    required void Function(int, int) onProgress,
  }) async {
    downloads++;
    if (fail) throw const HttpException('Interrupted download');
    await file.writeAsBytes([1, 2, 3]);
    onProgress(3, 3);
    return file;
  }

  @override
  Future<File> downloadAndroidUpdate(
    UpdateAsset asset, {
    required void Function(int, int) onProgress,
  }) => downloadWindowsUpdate(asset, onProgress: onProgress);
  @override
  Future<String> prepareWindowsUpdate(File archive, AppVersion version) async {
    preparations++;
    return '${file.path}.stage';
  }
}

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('localist-update-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
    'startup and settings share a single preparation; download is reused',
    () async {
      final backend = FakeUpdates(File('${directory.path}/update.zip'));
      final updates = AutomaticUpdateController(
        service: backend,
        windows: true,
      );
      final states = <AutomaticUpdateState>[];
      updates.addListener(() => states.add(updates.state));
      await Future.wait([updates.checkAndPrepare(), updates.checkAndPrepare()]);
      expect(backend.checks, 1);
      expect(backend.downloads, 1);
      expect(updates.state, AutomaticUpdateState.ready);
      expect(updates.progress, 1);
      expect(
        states,
        containsAllInOrder([
          AutomaticUpdateState.checking,
          AutomaticUpdateState.downloading,
          AutomaticUpdateState.preparing,
          AutomaticUpdateState.ready,
        ]),
      );
      expect(states, isNot(contains(AutomaticUpdateState.installing)));
      await updates.checkAndPrepare();
      expect(backend.downloads, 1);
      updates.dispose();
    },
  );
  test(
    'interrupted download never reports ready and a retry recovers',
    () async {
      final backend = FakeUpdates(File('${directory.path}/update.zip'))
        ..fail = true;
      final updates = AutomaticUpdateController(
        service: backend,
        windows: true,
      );
      await updates.checkAndPrepare();
      expect(updates.state, AutomaticUpdateState.failed);
      expect(updates.package, isNull);
      backend.fail = false;
      await updates.checkAndPrepare();
      expect(updates.state, AutomaticUpdateState.ready);
      updates.dispose();
    },
  );
  test(
    'declined prepared update remains available after restart; newer release supersedes it',
    () async {
      final backend = FakeUpdates(File('${directory.path}/update.zip'));
      final first = AutomaticUpdateController(service: backend, windows: true);
      await first.checkAndPrepare();
      await first.defer();
      expect(first.deferred, isTrue);
      first.dispose();
      final reopened = AutomaticUpdateController(
        service: backend,
        windows: true,
      );
      await reopened.checkAndPrepare();
      expect(reopened.state, AutomaticUpdateState.ready);
      expect(reopened.deferred, isTrue);
      expect(reopened.shouldPrompt, isFalse);
      backend.version = AppVersion.tryParse('6.0.2')!;
      await reopened.checkAndPrepare();
      expect(reopened.state, AutomaticUpdateState.ready);
      expect(reopened.check!.release.version.toString(), '6.0.2');
      expect(reopened.deferred, isFalse);
      expect(reopened.shouldPrompt, isTrue);
      expect(backend.downloads, 3);
      reopened.dispose();
    },
  );
  test(
    'install rechecks latest release and does not launch installer on check failure',
    () async {
      final backend = FakeUpdates(File('${directory.path}/update.zip'));
      final updates = AutomaticUpdateController(
        service: backend,
        windows: true,
      );
      await updates.checkAndPrepare();
      backend.version = AppVersion.tryParse('6.0.3')!;
      backend.fail = true;
      expect(await updates.installPreparedUpdate(), isFalse);
      expect(backend.checks, 2);
      expect(updates.state, AutomaticUpdateState.failed);
      expect(updates.check!.release.version.toString(), '6.0.3');
      updates.dispose();
    },
  );
  test(
    'Android granted install access opens installer once without another permission request',
    () async {
      final backend = FakeUpdates(File('${directory.path}/update.apk'));
      var permissionRequests = 0, installs = 0;
      final updates = AutomaticUpdateController(
        service: backend,
        windows: false,
        canInstallPackages: () async => true,
        requestInstallPermission: () async {
          permissionRequests++;
          return true;
        },
        installAndroidPackage: (path) async {
          installs++;
          return true;
        },
      );
      await updates.checkAndPrepare();
      await updates.accept();
      expect(await updates.installPreparedUpdate(), isTrue);
      expect(permissionRequests, 0);
      expect(installs, 1);
      expect(updates.installPermissionNeeded, isFalse);
      expect(updates.installRequested, isFalse);
      updates.dispose();
    },
  );
  testWidgets(
    'update prompt requires a Yes or No choice; deferred icon remains actionable',
    (tester) async {
      final backend = FakeUpdates(File('${directory.path}/update.zip'));
      final updates = AutomaticUpdateController(
        service: backend,
        windows: true,
      );
      await tester.runAsync(() => updates.checkAndPrepare());
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Test'),
                  actions: [
                    SizedBox(
                      width: 40,
                      child: LocalistUpdateAction(
                        updates: updates,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      final prompt = confirmLocalistUpdate(page, updates, refresh: false);
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Update ready'), findsOneWidget);
      await tester.tap(find.text('No, later'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await prompt;
      expect(updates.deferred, isTrue);
      expect(find.byIcon(Icons.install_mobile), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      updates.dispose();
    },
  );
  test('release digest and size reject corrupted packages', () async {
    final file = File('${directory.path}/update.zip');
    await file.writeAsBytes([1, 2, 3]);
    final asset = UpdateAsset(
      name: 'update.zip',
      downloadUrl: '',
      size: 3,
      digest: 'sha256:${sha256.convert([1, 2, 3])}',
    );
    await validateUpdateFile(file, asset);
    await file.writeAsBytes([1, 2, 4]);
    await expectLater(
      validateUpdateFile(file, asset),
      throwsA(isA<FileSystemException>()),
    );
    await file.writeAsBytes([1, 2]);
    await expectLater(
      validateUpdateFile(file, asset),
      throwsA(isA<FileSystemException>()),
    );
  });
  test(
    'real HTTP download is atomic, checks release digest and reuses verified file',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.contentLength = 3;
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      final service = AppUpdateService(
        downloadDirectory: directory,
        clientFactory: () => RealHttpOverrides().createHttpClient(null),
      );
      final asset = UpdateAsset(
        name: 'windows.zip',
        downloadUrl: 'http://127.0.0.1:${server.port}/windows.zip',
        size: 3,
        digest: 'sha256:${sha256.convert([1, 2, 3])}',
      );
      try {
        final file = await service.downloadWindowsUpdate(
          asset,
          onProgress: (_, _) {},
        );
        expect(await file.readAsBytes(), [1, 2, 3]);
        expect(File('${file.path}.part').existsSync(), false);
        await service.downloadWindowsUpdate(asset, onProgress: (_, _) {});
        expect(requests, 1);
        final bad = UpdateAsset(
          name: 'corrupt.zip',
          downloadUrl: asset.downloadUrl,
          size: 3,
          digest: 'sha256:${sha256.convert([3, 2, 1])}',
        );
        await expectLater(
          service.downloadWindowsUpdate(bad, onProgress: (_, _) {}),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(p.join(directory.path, 'corrupt.zip')).existsSync(), false);
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'Windows staging validates complete bundle and version; rejects traversal',
    () {
      final archive = Archive();
      for (final name in [
        'Localist.exe',
        'LocalistUpdater.exe',
        'LocalistRemote.exe',
        'librustdesk.dll',
        'flutter_windows.dll',
      ]) {
        archive.addFile(ArchiveFile(name, 3, [1, 2, 3]));
      }
      archive.addFile(
        ArchiveFile.string(
          'data/flutter_assets/pubspec.yaml',
          'version: 6.0.1+63\n',
        ),
      );
      final zip = File('${directory.path}/update.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      expect(
        stageWindowsArchive([zip.path, '${directory.path}/stage', '6.0.1']),
        p.normalize('${directory.path}/stage'),
      );
      expect(
        () =>
            stageWindowsArchive([zip.path, '${directory.path}/wrong', '6.0.2']),
        throwsFormatException,
      );
      final bad = Archive()..addFile(ArchiveFile.string('../escape.txt', 'no'));
      zip.writeAsBytesSync(ZipEncoder().encode(bad));
      expect(
        () => stageWindowsArchive([
          zip.path,
          '${directory.path}/unsafe',
          '6.0.1',
        ]),
        throwsFormatException,
      );
      expect(File('${directory.path}/escape.txt').existsSync(), false);
    },
  );
  test(
    'a cached staged update is rebuilt if a required DLL was removed',
    () async {
      final archive = Archive();
      for (final name in [
        'Localist.exe',
        'LocalistUpdater.exe',
        'LocalistRemote.exe',
        'librustdesk.dll',
        'flutter_windows.dll',
      ]) {
        archive.addFile(ArchiveFile(name, 3, [1, 2, 3]));
      }
      archive.addFile(
        ArchiveFile.string(
          'data/flutter_assets/pubspec.yaml',
          'version: 6.0.1+63\n',
        ),
      );
      final zip = File(p.join(directory.path, 'update.zip'));
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      final service = AppUpdateService();
      AppVersion version = AppVersion.tryParse('6.0.1')!;
      final first = await service.prepareWindowsUpdate(zip, version);
      expect(await service.prepareWindowsUpdate(zip, version), first);
      await File(p.join(first, 'flutter_windows.dll')).delete();
      final rebuilt = await service.prepareWindowsUpdate(zip, version);
      expect(rebuilt, isNot(first));
      expect(isCompleteWindowsBundle(rebuilt, '6.0.1'), true);
    },
  );
}
