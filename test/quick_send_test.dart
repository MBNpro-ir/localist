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
  test('Windows hosted Wi-Fi interface is not mistaken for loopback', () {
    expect(
      AppleWebTransferService.isIgnoredNetworkInterface(
        'Local Area Connection* 12',
      ),
      isFalse,
    );
    expect(AppleWebTransferService.isIgnoredNetworkInterface('lo0'), isTrue);
    expect(
      AppleWebTransferService.isIgnoredNetworkInterface(
        'Loopback Pseudo-Interface 1',
      ),
      isTrue,
    );
  });

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

  test('received transfer history survives JSON persistence', () {
    final updatedAt = DateTime.utc(2026, 9, 7, 8, 26, 23);
    final transfer = QuickSendTransfer(
      id: 'receive-session-file',
      deviceName: 'Pixel 📱',
      fileName: 'photo.jpg',
      path: r'C:\Received\photo.jpg',
      totalBytes: 4096,
      transferredBytes: 4096,
      direction: QuickSendDirection.receiving,
      state: QuickSendTransferState.completed,
      message: '',
      updatedAt: updatedAt,
    );

    final restored = QuickSendTransfer.fromJson(
      jsonDecode(jsonEncode(transfer.toJson())) as Map<String, dynamic>,
    );

    expect(restored.id, transfer.id);
    expect(restored.deviceName, transfer.deviceName);
    expect(restored.fileName, transfer.fileName);
    expect(restored.path, transfer.path);
    expect(restored.totalBytes, transfer.totalBytes);
    expect(restored.transferredBytes, transfer.transferredBytes);
    expect(restored.direction, QuickSendDirection.receiving);
    expect(restored.state, QuickSendTransferState.completed);
    expect(restored.updatedAt, updatedAt);
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

  test('Apple web transfer prioritizes real Windows LAN adapters', () {
    expect(
      AppleWebTransferService.networkInterfacePriority(
        'Local Area Connection* 12',
      ),
      0,
    );
    expect(
      AppleWebTransferService.networkInterfacePriority('Wi-Fi'),
      lessThan(AppleWebTransferService.networkInterfacePriority('Ethernet')),
    );
    expect(
      AppleWebTransferService.isIgnoredNetworkInterface(
        'vEthernet (Default Switch)',
      ),
      isTrue,
    );
    expect(
      AppleWebTransferService.isIgnoredNetworkInterface('Tailscale'),
      isTrue,
    );
    expect(AppleWebTransferService.isIgnoredNetworkInterface('Wi-Fi'), isFalse);
    expect(
      AppleWebTransferService.isUsableNetworkAddress('192.168.137.1'),
      isTrue,
    );
    expect(
      AppleWebTransferService.isUsableNetworkAddress('169.254.1.20'),
      isFalse,
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

  test(
    'native dropped files remain queued until Quick Send consumes them',
    () async {
      final bridge = NativeBridgeService.instance;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      await messenger.handlePlatformMessage(
        'com.prs.localist.vpn',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('quickSendSharedFiles', [
            {'path': r'C:\Drop\photo.jpg', 'name': 'photo.jpg'},
          ]),
        ),
        (_) {},
      );

      expect(await bridge.hasQuickSendSharedFiles(), isTrue);
      final files = await bridge.takeQuickSendSharedFiles();
      expect(files, hasLength(1));
      expect(files.single.path, r'C:\Drop\photo.jpg');
      expect(await bridge.hasQuickSendSharedFiles(), isFalse);
    },
  );

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

  test('Quick Send accepts emoji names and rejects unsafe aliases', () {
    expect(QuickSendSettings.isValidAlias('MBN PC 🚀'), isTrue);
    expect(QuickSendSettings.validateAlias('   '), 'empty');
    expect(QuickSendSettings.validateAlias('name\nline'), 'controlCharacter');
    expect(
      QuickSendSettings.validateAlias(
        List.filled(QuickSendSettings.maxAliasCharacters + 1, 'a').join(),
      ),
      'tooLong',
    );
  });

  test('Quick Send persists profile identity settings', () async {
    SharedPreferences.setMockInitialValues({
      'quickSend.alias': 'Desk ✨',
      'quickSend.profile.completed': true,
      'quickSend.profile.avatarPreset': 'spark',
      'quickSend.profile.avatarColor': 0xFF6750A4,
      'quickSend.profile.imagePath': r'C:\avatar.png',
    });
    final settings = await QuickSendSettings.load();

    expect(settings.alias, 'Desk ✨');
    expect(settings.profileSetupCompleted, isTrue);
    expect(settings.avatarPreset, 'spark');
    expect(settings.avatarColorValue, 0xFF6750A4);
    expect(settings.profileImagePath, r'C:\avatar.png');
  });

  test('Quick Send accepts only bounded profile thumbnails from peers', () {
    final thumbnail = base64Encode(const [0x89, 0x50, 0x4E, 0x47]);
    final device = QuickSendDevice.fromWire({
      'alias': 'Nearby device',
      'avatarPreset': 'spark',
      'avatarColor': 0xFF6750A4,
      'avatarImage': thumbnail,
    }, ip: '192.168.1.20');
    final invalid = QuickSendDevice.fromWire({
      'alias': 'Invalid image',
      'avatarImage': '%%%not-base64',
    }, ip: '192.168.1.21');

    expect(device.avatarImageBase64, thumbnail);
    expect(invalid.avatarImageBase64, isEmpty);
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
      // Windows uses the native computer name; CI on Linux uses the hostname.
      expect(
        info['alias'],
        Platform.isWindows ? 'QA-WINDOWS' : Platform.localHostname.trim(),
      );
      expect(info['version'], '2.1');
      expect(info['alias'], isNot('localhost'));
      expect(info['avatarPreset'], 'person');
      expect(info['avatarColor'], 0xFF006A6A);
    } finally {
      socket?.destroy();
      await service.disposeService();
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
    }
  });

  test(
    'native batch confirms exact bytes and preserves an existing file on failure',
    () async {
      final service = QuickSendService.instance;
      final originalSettings = service.settings!;
      final directory = await Directory.systemTemp.createTemp(
        'localist-native-batch',
      );
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      const channel = MethodChannel('com.prs.localist.vpn');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final before = service.receiveBatchCompletions;
      final existing = await File(
        '${directory.path}/report.txt',
      ).writeAsString('original');
      try {
        await service.updateSettings(
          service.settings!.copyWith(
            port: port,
            destinationDirectory: directory.path,
            destinationCustomized: true,
            quickSave: true,
            overwrite: true,
          ),
        );
        await service.restart();
        final prepared = await _rawHttpRequest(
          Uri.parse('http://127.0.0.1:$port/api/localsend/v2/prepare-upload'),
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: utf8.encode(
            jsonEncode({
              'info': {'alias': 'Native QA'},
              'files': {
                'a': {'fileName': 'a.txt', 'size': 3, 'fileType': 'text/plain'},
                'b': {
                  'fileName': 'report.txt',
                  'size': 5,
                  'fileType': 'text/plain',
                },
              },
            }),
          ),
        );
        expect(prepared.status, 200);
        final session = jsonDecode(prepared.body) as Map<String, dynamic>;
        Uri upload(String id) =>
            Uri.parse('http://127.0.0.1:$port/api/localsend/v2/upload').replace(
              queryParameters: {
                'sessionId': session['sessionId'] as String,
                'fileId': id,
                'token': (session['files'] as Map)[id] as String,
              },
            );
        expect(
          (await _rawHttpRequest(
            upload('a'),
            method: 'POST',
            body: utf8.encode('one'),
          )).status,
          200,
        );
        expect(service.receiveBatchCompletions, before);
        expect(
          (await _rawHttpRequest(
            upload('b'),
            method: 'POST',
            body: utf8.encode('no'),
          )).status,
          500,
        );
        expect(await existing.readAsString(), 'original');
        expect(service.receiveBatchCompletions, before);
        expect(
          (await _rawHttpRequest(
            upload('b'),
            method: 'POST',
            body: utf8.encode('final'),
          )).status,
          200,
        );
        expect(await existing.readAsString(), 'final');
        expect(await File('${directory.path}/a.txt').readAsString(), 'one');
        expect(service.receiveBatchCompletions, before + 1);
        expect(
          await directory
              .list()
              .where((f) => f.path.endsWith('.part'))
              .toList(),
          isEmpty,
        );
      } finally {
        await service.updateSettings(originalSettings);
        await service.disposeService();
        await directory.delete(recursive: true);
      }
    },
  );

  test('Apple browser transfer serves downloads and accepts uploads', () async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final offeredFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'localist-browser-offer-$unique.txt',
    );
    final refreshedFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'localist-browser-refresh-$unique.txt',
    );
    final uploadedName = 'localist-safari-upload-$unique.txt';
    final uploadedFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$uploadedName',
    );
    await offeredFile.writeAsString('hello from Localist');
    await refreshedFile.writeAsString('selected after Safari opened');

    final service = AppleWebTransferService.instance;
    try {
      final automatic = await service.start(
        paths: [offeredFile.path],
        offeredNames: {offeredFile.path: 'hello.txt'},
      );
      expect(automatic, isFalse);
      expect(service.active, isTrue);
      if (Platform.isWindows) {
        expect(service.errorMessage, isEmpty);
        expect(service.statusMessage, contains('Windows'));
      }

      final homeResponse = await _rawHttpRequest(service.loopbackTestUri);
      expect(homeResponse.status, HttpStatus.ok);
      expect(homeResponse.body, contains('Localist Web Transfer'));
      expect(homeResponse.body, contains('Connected devices'));
      expect(
        homeResponse.body,
        contains('window.setInterval(refreshSharedContent, 1000)'),
      );

      final initial = await _rawHttpRequest(
        service.loopbackTestUri.resolve('state'),
      );
      final initialFiles =
          (jsonDecode(initial.body) as Map<String, dynamic>)['files']
              as List<dynamic>;
      expect(initialFiles.single['name'], 'hello.txt');
      final downloadPath = initialFiles.single['url'] as String;
      final downloadResponse = await _rawHttpRequest(
        service.loopbackTestUri.resolve(downloadPath),
      );
      expect(downloadResponse.status, HttpStatus.ok);
      expect(downloadResponse.body, contains('hello from Localist'));

      service.setSharedContent(
        paths: [refreshedFile.path],
        offeredNames: {refreshedFile.path: 'live-selection.txt'},
        selectedText: 'shared after Safari opened',
      );
      final stateResponse = await _rawHttpRequest(
        service.loopbackTestUri.resolve('state'),
      );
      expect(stateResponse.status, HttpStatus.ok);
      final state = jsonDecode(stateResponse.body) as Map<String, dynamic>;
      final stateFiles = state['files'] as List<dynamic>;
      expect(stateFiles, hasLength(1));
      expect(
        (stateFiles.single as Map<String, dynamic>)['name'],
        'live-selection.txt',
      );
      expect(state['text'], 'shared after Safari opened');

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

      Future<Map<String, dynamic>> join(String name) async {
        final result = await _rawHttpRequest(
          service.loopbackTestUri.resolve('join'),
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: utf8.encode(jsonEncode({'name': name, 'platform': 'iPhone'})),
        );
        expect(result.status, 200);
        return jsonDecode(result.body) as Map<String, dynamic>;
      }

      final alice = await join('iPhone A');
      final bob = await join('iPhone B');
      final charlie = await join('Browser C');
      Uri peerUri(
        String route,
        Map<String, dynamic> peer, [
        Map<String, String> extra = const {},
      ]) => service.loopbackTestUri
          .resolve(route)
          .replace(
            queryParameters: {
              'peer': peer['id'] as String,
              'key': peer['key'] as String,
              ...extra,
            },
          );
      final before = QuickSendService.instance.receiveBatchCompletions;
      for (var index = 0; index < 2; index++) {
        final result = await _rawHttpRequest(
          peerUri('upload-file', alice, {
            'name': 'relay-$index.txt',
            'size': '5',
            'target': bob['id'] as String,
            'batch': 'test-batch',
            'count': '2',
            'index': '$index',
          }),
          method: 'POST',
          body: utf8.encode('hello'),
        );
        expect(result.status, 200);
        expect(
          QuickSendService.instance.receiveBatchCompletions,
          before + (index == 1 ? 1 : 0),
        );
      }
      final bobState =
          jsonDecode((await _rawHttpRequest(peerUri('state', bob))).body)
              as Map<String, dynamic>;
      expect(bobState['devices'], hasLength(greaterThanOrEqualTo(4)));
      final inbox = bobState['inbox'] as List<dynamic>;
      expect(inbox, hasLength(2));
      final privateFile = inbox.first as Map<String, dynamic>;
      final otherState =
          jsonDecode((await _rawHttpRequest(peerUri('state', charlie))).body)
              as Map<String, dynamic>;
      expect(otherState['inbox'], isEmpty);
      expect(
        (await _rawHttpRequest(
          peerUri('download/${privateFile['id']}', charlie),
        )).status,
        404,
      );
      final received = await _rawHttpRequest(
        peerUri('download/${privateFile['id']}', bob),
      );
      expect(received.status, 200);
      expect(received.body, 'hello');
      final outgoing = QuickSendService.instance.transfers.firstWhere(
        (file) =>
            file.direction == QuickSendDirection.sending &&
            file.deviceName == 'iPhone B',
      );
      expect(outgoing.state, QuickSendTransferState.transferring);
      expect(outgoing.progress, lessThan(1));
      expect(
        (await _rawHttpRequest(
          peerUri('receipt', bob, {
            'file': privateFile['id'] as String,
            'bytes': '4',
          }),
          method: 'POST',
        )).status,
        400,
      );
      // A wrong receipt must not consume the pending transfer.
      expect(
        (await _rawHttpRequest(
          peerUri('receipt', bob, {
            'file': privateFile['id'] as String,
            'bytes': '5',
          }),
          method: 'POST',
        )).status,
        204,
      );
      expect(
        QuickSendService.instance.transfers
            .firstWhere((file) => file.id == outgoing.id)
            .state,
        QuickSendTransferState.completed,
      );
    } finally {
      await service.stop();
      if (await offeredFile.exists()) {
        await offeredFile.delete();
      }
      if (await refreshedFile.exists()) {
        await refreshedFile.delete();
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
  final response = latin1.decode(responseBytes);
  final headerEnd = response.indexOf('\r\n\r\n');
  if (headerEnd < 0) {
    throw const FormatException('Invalid HTTP response.');
  }
  final status =
      int.tryParse(response.substring(0, headerEnd).split(' ').elementAt(1)) ??
      0;
  var responseBody = response.substring(headerEnd + 4);
  if (response
      .substring(0, headerEnd)
      .toLowerCase()
      .contains('transfer-encoding: chunked')) {
    final output = StringBuffer();
    var cursor = 0;
    while (cursor < responseBody.length) {
      final end = responseBody.indexOf('\r\n', cursor);
      if (end < 0) break;
      final length = int.parse(
        responseBody.substring(cursor, end).split(';').first,
        radix: 16,
      );
      if (length == 0) break;
      cursor = end + 2;
      output.write(responseBody.substring(cursor, cursor + length));
      cursor += length + 2;
    }
    responseBody = output.toString();
  }
  return (
    status: status,
    body: utf8.decode(latin1.encode(responseBody), allowMalformed: true),
  );
}
