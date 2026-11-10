import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/apple_web_transfer_service.dart';
import 'package:localist/services/quick_send_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Synthetic loopback host for test_browser_transfer.cjs; no user data/settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('browser language and relay acceptance host', () async {
    final root = Directory(
      '${Directory.current.path}/.runlogs/manual-review-20261110/browser',
    );
    await root.create(recursive: true);
    final offered = await File(
      '${root.path}/host.txt',
    ).writeAsString('host download fixture');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    SharedPreferences.setMockInitialValues({
      'quickSend.port': port,
      'quickSend.destinationDirectory': root.path,
      'quickSend.destinationCustomized': true,
      'quickSend.receiveEnabled': true,
      'quickSend.encryption': false,
      'quickSend.quickSave': true,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.prs.localist.vpn'),
      (_) async => null,
    );
    final web = AppleWebTransferService.instance;
    try {
      web.persian = true;
      await web.start(
        paths: [offered.path],
        offeredNames: {offered.path: '<host>.txt'},
        useHotspot: false,
      );
      await File(
        '${root.path}/ready.json',
      ).writeAsString(jsonEncode({'url': web.loopbackTestUri.toString()}));
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (!await File('${root.path}/done').exists() &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await File('${root.path}/done').exists(), true);
    } finally {
      await web.stop();
      await QuickSendService.instance.disposeService();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
