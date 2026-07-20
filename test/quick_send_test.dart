import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/models/quick_send_settings.dart';
import 'package:localist/services/apple_web_transfer_service.dart';
import 'package:localist/services/native_bridge_service.dart';
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

  test('Apple web transfer builds iPhone-compatible Wi-Fi QR payloads', () {
    expect(
      AppleWebTransferService.buildWifiQrPayload(
        ssid: 'Localist; Private',
        password: r'p:a\ss',
      ),
      r'WIFI:T:WPA;S:Localist\; Private;P:p\:a\\ss;;',
    );
    expect(
      AppleWebTransferService.buildWifiQrPayload(
        ssid: 'Localist Open',
        password: '',
      ),
      'WIFI:T:nopass;S:Localist Open;;',
    );
    expect(
      AppleWebTransferService.buildWifiQrPayload(ssid: '', password: ''),
      isEmpty,
    );
  });

  test('Android local-only hotspot details are decoded safely', () {
    final info = LocalOnlyHotspotInfo.fromMap({
      'supported': true,
      'active': true,
      'managed': true,
      'ssid': 'Localist_42',
      'password': 'secret',
      'primaryAddress': '192.168.43.1',
      'addresses': ['192.168.43.1', '192.168.43.1', '', '192.168.137.1'],
      'errorCode': '',
      'message': '',
      'permissionRequired': false,
    });

    expect(info.active, isTrue);
    expect(info.managed, isTrue);
    expect(info.ssid, 'Localist_42');
    expect(info.addresses, ['192.168.43.1', '192.168.137.1']);
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

  test('Apple browser transfer serves downloads and accepts uploads', () async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final offeredFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'localist-browser-offer-$unique.txt',
    );
    final uploadedName = 'localist-safari-upload-$unique.txt';
    final uploadedFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$uploadedName',
    );
    await offeredFile.writeAsString('hello from Localist');

    final service = AppleWebTransferService.instance;
    try {
      final automatic = await service.start(
        paths: [offeredFile.path],
        offeredNames: {offeredFile.path: 'hello.txt'},
      );
      expect(automatic, isFalse);
      expect(service.active, isTrue);

      final homeResponse = await _rawHttpRequest(service.loopbackTestUri);
      expect(homeResponse.status, HttpStatus.ok);
      expect(homeResponse.body, contains('Localist Web Transfer'));
      expect(homeResponse.body, contains('hello.txt'));

      final downloadPath = RegExp(
        r'href="([^"]+/download/[^"]+)"',
      ).firstMatch(homeResponse.body)!.group(1)!;
      final downloadResponse = await _rawHttpRequest(
        service.loopbackTestUri.resolve(downloadPath),
      );
      expect(downloadResponse.status, HttpStatus.ok);
      expect(downloadResponse.body, contains('hello from Localist'));

      final boundary = 'localist-test-$unique';
      final uploadBody = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="files"; '
        'filename="$uploadedName"\r\n'
        'Content-Type: text/plain\r\n\r\n'
        'hello from Safari\r\n'
        '--$boundary--\r\n',
      );
      final uploadResponse = await _rawHttpRequest(
        service.loopbackTestUri.resolve('upload'),
        method: 'POST',
        headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
        body: uploadBody,
      );
      expect(uploadResponse.status, HttpStatus.seeOther);
      expect(await uploadedFile.readAsString(), 'hello from Safari');
    } finally {
      await service.stop();
      if (await offeredFile.exists()) {
        await offeredFile.delete();
      }
      if (await uploadedFile.exists()) {
        await uploadedFile.delete();
      }
      await QuickSendService.instance.disposeService();
    }
  });
}

Future<({int status, String body})> _rawHttpRequest(
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const {},
  List<int> body = const [],
}) async {
  final socket = await Socket.connect(uri.host, uri.port);
  final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final request = StringBuffer()
    ..write('$method $target HTTP/1.1\r\n')
    ..write('Host: ${uri.host}:${uri.port}\r\n')
    ..write('Connection: close\r\n');
  for (final entry in headers.entries) {
    request.write('${entry.key}: ${entry.value}\r\n');
  }
  if (body.isNotEmpty) {
    request.write('Content-Length: ${body.length}\r\n');
  }
  request.write('\r\n');
  socket.add(utf8.encode(request.toString()));
  if (body.isNotEmpty) {
    socket.add(body);
  }
  await socket.flush();
  final responseBytes = await socket.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  socket.destroy();
  final response = utf8.decode(responseBytes, allowMalformed: true);
  final headerEnd = response.indexOf('\r\n\r\n');
  if (headerEnd < 0) {
    throw const FormatException('Invalid HTTP response.');
  }
  final status =
      int.tryParse(response.substring(0, headerEnd).split(' ').elementAt(1)) ??
      0;
  return (status: status, body: response.substring(headerEnd + 4));
}
