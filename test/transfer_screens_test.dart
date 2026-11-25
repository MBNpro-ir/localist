import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/screens/transfer_history_page.dart';
import 'package:localist/screens/stream_page.dart';
import 'package:localist/services/media_stream_service.dart';
import 'package:localist/services/quick_send_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = QuickSendService.instance;
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('localist-history-qa');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => false,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.prs.localist.vpn'),
      (_) async => null,
    );
    for (final name in ['holiday.mp4', 'receipt.pdf', 'song.mp3']) {
      final id = service.beginBrowserTransfer(
        deviceName: 'iPhone QA',
        fileName: name,
        path: '${directory.path}/$name',
        totalBytes: 2000,
      );
      service.updateBrowserTransfer(
        id,
        2000,
        state: QuickSendTransferState.completed,
      );
    }
  });
  tearDownAll(() async {
    await service.clearReceivedHistory();
    await directory.delete(recursive: true);
  });

  Widget app(Widget child, {bool persian = false}) => MaterialApp(
    locale: Locale(persian ? 'fa' : 'en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.4)),
      child: child!,
    ),
    home: child,
  );

  testWidgets('narrow history gallery composes category and search filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(TransferHistoryPage(service: service)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.pumpAndSettle();
    expect(find.text('1 items'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching files'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Persian Stream fits a narrow display with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Scaffold(body: StreamPage(service: MediaStreamService.instance)),
        persian: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('انتخاب رسانه‌ها'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('DLNA'), findsNothing);
    expect(find.textContaining('Miracast'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Stream Receive opens discovered and typed endpoints', (
    tester,
  ) async {
    const channel = MethodChannel('com.prs.localist.vpn');
    final messenger = tester.binding.defaultBinaryMessenger;
    final opened = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openUri') {
        opened.add((call.arguments as Map)['uri'] as String);
        return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final stream = MediaStreamService.instance;
    final discovered = Uri.parse('http://192.168.1.50:53547');
    stream.discovery.addresses = [discovered];
    addTearDown(() => stream.discovery.addresses = const []);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        app(Scaffold(body: StreamPage(service: stream, receiving: true))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Scan QR code'),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('192.168.1.50:53547'));
      await tester.enterText(find.byType(TextField), '192.168.1.60:53547');
      final open = find.text('Open in browser');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(opened, [
      discovered.toString(),
      'http://192.168.1.60:53547',
      discovered.toString(),
      'http://192.168.1.60:53547',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
