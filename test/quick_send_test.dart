import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/quick_send_settings.dart';
import 'package:localist/services/quick_send_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Quick Send strips traversal and invalid file-name characters', () {
    expect(
      QuickSendService.sanitizeFileName(r'..\..\report:final?.pdf'),
      'report_final_.pdf',
    );
    expect(QuickSendService.sanitizeFileName('../'), 'received-file');
    expect(
      QuickSendService.sanitizeRelativeFilePath(
        r'Photos\Holiday/Day 1/picture.jpg',
      ).replaceAll(r'\', '/'),
      'Photos/Holiday/Day 1/picture.jpg',
    );
    expect(
      QuickSendService.sanitizeRelativeFilePath('../../safe.txt'),
      'safe.txt',
    );
  });

  test('Quick Send categorizes default receive folders by content type', () {
    expect(
      QuickSendService.receiveCategoryFor('photo.jpg', 'image/jpeg'),
      'Images',
    );
    expect(
      QuickSendService.receiveCategoryFor(
        'movie.mkv',
        'application/octet-stream',
      ),
      'Videos',
    );
    expect(
      QuickSendService.receiveCategoryFor('manual.pdf', 'application/pdf'),
      'Documents',
    );
    expect(
      QuickSendService.receiveCategoryFor(
        'localist.apk',
        'application/octet-stream',
      ),
      'Apps',
    );
    expect(
      QuickSendService.receiveCategoryFor(
        'backup.7z',
        'application/octet-stream',
      ),
      'Archives',
    );
  });

  test('Quick Send preserves a legacy custom receive destination', () async {
    SharedPreferences.setMockInitialValues({
      'quickSend.destinationDirectory': r'D:\Received',
    });
    final custom = await QuickSendSettings.load(
      legacyDefaultDestination: r'C:\Downloads',
    );
    expect(custom.destinationCustomized, isTrue);

    SharedPreferences.setMockInitialValues({
      'quickSend.destinationDirectory': r'C:\Downloads\',
    });
    final oldDefault = await QuickSendSettings.load(
      legacyDefaultDestination: r'C:\Downloads',
    );
    expect(oldDefault.destinationCustomized, isFalse);
  });

  test(
    'active discovery scans LAN targets but never scans its own address',
    () {
      final targets = QuickSendService.buildSubnetTargets([
        '192.168.42.129',
        '10.10.10.2',
        '0.0.0.0',
      ]);

      expect(targets, contains('192.168.42.1'));
      expect(targets, contains('192.168.42.254'));
      expect(targets, contains('10.10.10.1'));
      expect(targets, isNot(contains('192.168.42.129')));
      expect(targets, isNot(contains('10.10.10.2')));
      expect(targets, isNot(contains('0.0.0.0')));
      expect(QuickSendService.isUsableLanAddress('192.168.137.1'), isTrue);
      expect(QuickSendService.isUsableLanAddress('127.0.0.1'), isFalse);
      expect(QuickSendService.isUsableLanAddress('169.254.10.20'), isFalse);
    },
  );

  test('Quick Send serves LocalSend v2 info with the device name', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();

    SharedPreferences.setMockInitialValues({
      'quickSend.port': port,
      'quickSend.destinationDirectory': Directory.systemTemp.path,
      'quickSend.destinationCustomized': true,
      'quickSend.receiveEnabled': true,
      'quickSend.encryption': false,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const nativeChannel = MethodChannel('com.prs.localist.vpn');
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      if (call.method == 'getDeviceDetails') {
        return <String, Object?>{'computerName': 'QA-WINDOWS'};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return Directory.systemTemp.path;
    });

    final service = QuickSendService.instance;
    Socket? socket;
    try {
      await service.initialize();
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.write(
        'GET /api/localsend/v2/info HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Connection: close\r\n\r\n',
      );
      await socket.flush();
      final bytes = await socket.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final rawResponse = utf8.decode(bytes);
      final headerEnd = rawResponse.indexOf('\r\n\r\n');
      expect(headerEnd, greaterThan(0));
      final body = rawResponse.substring(headerEnd + 4);
      final info = jsonDecode(body) as Map<String, dynamic>;

      expect(rawResponse, startsWith('HTTP/1.1 200'));
      expect(info['alias'], 'QA-WINDOWS');
      expect(info['version'], '2.1');
      expect(info['alias'], isNot('localhost'));
    } finally {
      socket?.destroy();
      await service.disposeService();
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
    }
  });
}
