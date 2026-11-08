import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/services/quick_send_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'two uploads produce a single completion only after the last response; failed batch has its own event',
    () async {
      final previousHttpOverride = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousHttpOverride);
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.prs.localist.vpn'),
            (_) async => null,
          );
      final directory = await Directory.systemTemp.createTemp(
        'localist-sound-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final files = [
        for (final name in ['one.txt', 'two.txt'])
          await File('${directory.path}/$name').writeAsString('content'),
      ];
      final service = QuickSendService.instance;
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final ownPort = reservation.port;
      await reservation.close();
      SharedPreferences.setMockInitialValues({
        'quickSend.port': ownPort,
        'quickSend.destinationDirectory': directory.path,
        'quickSend.destinationCustomized': true,
        'quickSend.receiveEnabled': true,
        'quickSend.encryption': false,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path,
          );
      await service.initialize();
      addTearDown(service.disposeService);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var uploaded = 0;
      var reject = false;
      final before = service.sendBatchCompletions;
      server.listen((request) async {
        if (request.uri.path.endsWith('prepare-upload')) {
          final data =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': 'test-session',
              'files': {
                for (final id in (data['files'] as Map).keys) id: 'token',
              },
            }),
          );
        } else {
          await request.drain<void>();
          expect(service.sendBatchCompletions, reject ? before + 1 : before);
          uploaded++;
          if (reject) request.response.statusCode = 500;
        }
        await request.response.close();
      });
      final device = QuickSendDevice(
        ip: '127.0.0.1',
        alias: 'peer',
        version: '2.1',
        deviceModel: 'test',
        deviceType: 'desktop',
        fingerprint: 'remote-test',
        port: server.port,
        https: false,
        download: false,
        lastSeen: DateTime.now(),
      );
      await service.sendFiles(device, files.map((f) => f.path).toList());
      expect(uploaded, 2);
      expect(service.sendBatchCompletions, before + 1);
      // The failure must not increment the success batch counter.
      final failed = service.failedBatchCompletions;
      reject = true;
      await expectLater(
        service.sendFiles(device, files.map((f) => f.path).toList()),
        throwsA(isA<HttpException>()),
      );
      expect(service.failedBatchCompletions, failed + 1);
      expect(service.sendBatchCompletions, before + 1);
    },
  );
}
