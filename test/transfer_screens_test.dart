import 'dart:io';
import 'package:flutter/material.dart';
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
    expect(find.text('انتخاب فایل رسانه'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('انتقال کل صفحه / Miracast'),
      300,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
