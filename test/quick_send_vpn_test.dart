import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/screens/quick_send_page.dart';
import 'package:localist/services/apple_web_transfer_service.dart';
import 'package:localist/services/quick_send_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

Future<({int status, String body})> _request(
  Uri uri, {
  Object? json,
  List<int>? bytes,
}) => HttpOverrides.runWithHttpOverrides(() async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      json != null || bytes != null ? 'POST' : 'GET',
      uri,
    );
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(json)));
    } else if (bytes != null) {
      request.add(bytes);
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}, _DirectHttp());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = QuickSendService.instance;
  final web = AppleWebTransferService.instance;
  late Directory directory;
  late File offered;
  late int port;

  setUpAll(() async {
    final root = await Directory(
      '${Directory.current.path}/.runlogs/quick-send-vpn-qa',
    ).create(recursive: true);
    directory = await root.createTemp('fixture-');
    offered = await File(
      '${directory.path}/offered.txt',
    ).writeAsString('outgoing file with VPN active');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    port = reservation.port;
    await reservation.close();
    SharedPreferences.setMockInitialValues({
      'quickSend.port': port,
      'quickSend.destinationDirectory': directory.path,
      'quickSend.destinationCustomized': true,
      'quickSend.receiveEnabled': true,
      'quickSend.encryption': false,
      'quickSend.quickSave': true,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.prs.localist.vpn'),
      (_) async => null,
    );
    await service.initialize();
  });

  tearDownAll(() async {
    await web.stop();
    await service.disposeService();
    // Only remove the synthetic directory allocated by this test.
    final expectedParent = Directory(
      '${Directory.current.path}/.runlogs/quick-send-vpn-qa',
    ).absolute.path;
    expect(directory.absolute.parent.path, expectedParent);
    await directory.delete(recursive: true);
  });

  Widget app(bool vpn, {bool persian = false, bool settingsOnly = false}) =>
      MaterialApp(
        locale: Locale(persian ? 'fa' : 'en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: settingsOnly
              ? QuickSendStatusPanel(
                  settings: service.settings!,
                  deviceVpnActive: vpn,
                )
              : QuickSendPage(
                  key: const ValueKey('transfer'),
                  deviceVpnActive: vpn,
                  onOpenProfileSettings: () {},
                ),
        ),
      );

  testWidgets('VPN changes warn without interrupting native or web transfers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(false));
    await tester.runAsync(() async {
      // Discovery uses the test binding's blocked HTTP client; only explicit
      // loopback requests below opt in to real HTTP.
      await web.start(paths: [offered.path], offeredNames: const {});
    });
    final webUri = web.loopbackTestUri;
    Map<String, dynamic>? session;
    await tester.runAsync(() async {
      final response = await _request(
        Uri.parse('http://127.0.0.1:$port/api/localsend/v2/prepare-upload'),
        json: {
          'info': {'alias': 'Loopback sender'},
          'files': {
            'incoming': {
              'fileName': 'incoming.txt',
              'size': 5,
              'fileType': 'text/plain',
            },
          },
        },
      );
      expect(response.status, 200);
      session = jsonDecode(response.body) as Map<String, dynamic>;
    });

    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(find.text('VPN is active'), findsOneWidget);
    expect(find.text('Ready for Quick Send'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Add by IP',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(service.serverRunning, isTrue);
    expect(web.active, isTrue);
    expect(web.loopbackTestUri, webUri);

    await tester.runAsync(() async {
      // An upload authorized before the VPN toggle must still be accepted.
      final upload = Uri.parse('http://127.0.0.1:$port/api/localsend/v2/upload')
          .replace(
            queryParameters: {
              'sessionId': session!['sessionId'] as String,
              'fileId': 'incoming',
              'token': (session!['files'] as Map)['incoming'] as String,
            },
          );
      expect((await _request(upload, bytes: utf8.encode('hello'))).status, 200);
      expect(
        await File('${directory.path}/incoming.txt').readAsString(),
        'hello',
      );
      final state = await _request(webUri.resolve('state'));
      expect(state.status, 200);
      final files = (jsonDecode(state.body) as Map)['files'] as List;
      final download = await _request(
        webUri.resolve(files.single['url'] as String),
      );
      expect(download.body, await offered.readAsString());
      final receive = await service.createReceivedFile(
        'browser.txt',
        'text/plain',
      );
      expect(receive.parent.path, directory.path);

      // Discover a second loopback peer and send actual bytes with VPN active.
      final receiver = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      receiver.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/prepare-upload')) {
          final offer =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          request.response.write(
            jsonEncode({
              'sessionId': 'test-session',
              'files': {
                for (final id in (offer['files'] as Map).keys) id: 'test-token',
              },
            }),
          );
        } else if (request.uri.path.endsWith('/upload')) {
          await for (final chunk in request) {
            received.addAll(chunk);
          }
        } else {
          await request.drain<void>();
          request.response.write(
            jsonEncode({
              'alias': 'Loopback receiver',
              'version': '2.1',
              'fingerprint': 'vpn-warning-test-peer',
              'port': receiver.port,
              'protocol': 'http',
            }),
          );
        }
        await request.response.close();
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final device = await service.addManualDevice(
            host: '127.0.0.1',
            port: receiver.port,
            https: false,
          );
          await service.sendFiles(device, [offered.path]);
        }, _DirectHttp());
        expect(utf8.decode(received), await offered.readAsString());
      } finally {
        await receiver.close(force: true);
      }
    });
    await tester.pump();
    final peerCard = find.ancestor(
      of: find.text('Loopback receiver'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(peerCard).onTap, isNotNull);
    expect(tester.widget<ListTile>(peerCard).onLongPress, isNotNull);
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(find.text('VPN is active'), findsNothing);
    expect(
      service.devices.any((device) => device.id == 'vpn-warning-test-peer'),
      isTrue,
    );
    expect(web.loopbackTestUri, webUri);

    // Settings must report actual readiness even when showing the VPN warning.
    await tester.pumpWidget(app(true, settingsOnly: true));
    await tester.pump();
    expect(find.text('Ready to receive'), findsOneWidget);
    expect(find.text('Disabled by VPN'), findsNothing);
    expect(
      find.textContaining('sending and receiving remain enabled'),
      findsOneWidget,
    );

    // Mount directly with VPN already active, then turn it off. Neither the
    // initial state nor the change may retire the existing browser session.
    await tester.pumpWidget(app(true, persian: true));
    await tester.pump();
    expect(find.text('VPN روشن است'), findsOneWidget);
    expect(web.active, isTrue);
    await tester.pumpWidget(app(false, persian: true));
    await tester.pump();
    expect(find.text('VPN روشن است'), findsNothing);
    expect(service.serverRunning, isTrue);
    expect(web.loopbackTestUri, webUri);
    expect(tester.takeException(), isNull);
    // Let the bounded discovery burst finish using the widget clock, while
    // real interface enumeration can complete on the event loop.
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 1));
    }
    expect(service.scanning, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await web.stop();
      await service.disposeService();
    });
  });
}
