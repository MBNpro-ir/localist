import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:localist/screens/live_capture_page.dart';
import 'package:localist/services/live_capture_service.dart';
import 'package:localist/widgets/glass.dart';

class _Capture extends LiveCaptureService {
  bool started = false;
  @override
  bool get broadcasting => started;
  @override
  Future<void> start(LiveCaptureOptions value, {int port = 0}) async {
    options = value;
    started = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    started = false;
    notifyListeners();
  }
}

class _Preview extends RTCVideoRenderer {
  @override
  Future<void> initialize() async {}
  @override
  set srcObject(MediaStream? stream) {}
  @override
  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const imageKey = ValueKey('capture-layout-image');
  const webrtc = MethodChannel('FlutterWebRTC.Method');
  const bridge = MethodChannel('com.prs.localist.vpn');
  const events = MethodChannel('FlutterWebRTC.Event');
  setUpAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(webrtc, (_) async => null);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    // Complete shared plugin initialization outside any widget test's clock.
    await LiveCaptureService.initializeMedia();
    // Use readable real glyphs for optional screenshots rather than Ahem boxes.
    final font = FontLoader('CaptureLayoutQA');
    font.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            'windows/installer/fonts/Vazirmatn-Regular.ttf',
          ).readAsBytes(),
        ),
      ),
    );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(
      webrtc,
      (call) async => call.method == 'getSources'
          ? {
              'sources': [
                {
                  'deviceId': 'camera',
                  'kind': 'videoinput',
                  'label': 'Integrated USB camera',
                },
                {
                  'deviceId': 'microphone',
                  'kind': 'audioinput',
                  'label': 'Microphone array (Realtek High Definition Audio)',
                },
                {
                  'deviceId': 'cable',
                  'kind': 'audiooutput',
                  'label': 'CABLE Input (VB-Audio Virtual Cable)',
                },
              ],
            }
          : null,
    );
    messenger.setMockMethodCallHandler(
      bridge,
      (call) async => call.method == 'getCaptureDeviceCapabilities'
          ? {
              'modes': [
                {'width': 640, 'height': 480, 'minFps': 1, 'maxFps': 30},
                {'width': 1280, 'height': 720, 'minFps': 1, 'maxFps': 60},
                {'width': 1920, 'height': 1080, 'minFps': 1, 'maxFps': 60},
                {'width': 3840, 'height': 2160, 'minFps': 1, 'maxFps': 30},
              ],
              'minBitrateKbps': 64,
              'maxBitrateKbps': 80000,
              'codecs': 'avc',
            }
          : call.method == 'getWindowsVirtualCameraStatus'
          ? {'installed': false}
          : null,
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(webrtc, null);
    messenger.setMockMethodCallHandler(bridge, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Widget app(
    _Capture capture, {
    required bool persian,
    required double scale,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff008b9c),
      brightness: brightness,
    );
    return MaterialApp(
      locale: Locale(persian ? 'fa' : 'en'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'CaptureLayoutQA',
        scaffoldBackgroundColor: scheme.surface,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: imageKey,
        child: Scaffold(
          body: LocalistVisualStyle(
            simple: true,
            child: LiveCapturePage(service: capture, renderer: _Preview()),
          ),
        ),
      ),
    );
  }

  Future<void> saveImage(WidgetTester tester, String name) async {
    if (Platform.environment['LOCALIST_CAPTURE_LAYOUT_IMAGES'] != '1') return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(imageKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '.runlogs/capture-layout-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final sample in [
    (
      name: 'desktop-en',
      size: const Size(1844, 994),
      fa: false,
      scale: 1.0,
      platform: TargetPlatform.windows,
      brightness: Brightness.dark,
    ),
    (
      name: 'desktop-fa',
      size: const Size(1290, 900),
      fa: true,
      scale: 1.0,
      platform: TargetPlatform.windows,
      brightness: Brightness.light,
    ),
    (
      name: 'window-small',
      size: const Size(900, 780),
      fa: false,
      scale: 1.0,
      platform: TargetPlatform.windows,
      brightness: Brightness.dark,
    ),
    (
      name: 'desktop-large-text',
      size: const Size(1290, 900),
      fa: true,
      scale: 1.5,
      platform: TargetPlatform.windows,
      brightness: Brightness.dark,
    ),
    (
      name: 'phone-fa',
      size: const Size(320, 800),
      fa: true,
      scale: 1.5,
      platform: TargetPlatform.android,
      brightness: Brightness.light,
    ),
    (
      name: 'phone-en',
      size: const Size(360, 800),
      fa: false,
      scale: 1.3,
      platform: TargetPlatform.android,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('${sample.name}: capture cards adapt without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = sample.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = sample.platform;
      final capture = _Capture();
      await tester.pumpWidget(
        app(
          capture,
          persian: sample.fa,
          scale: sample.scale,
          brightness: sample.brightness,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Rear camera',
        'Automatic',
        'Continue in background with a Stop notification',
        'Allow receiver / OBS capture controls',
        'Automatically receive devices',
        'دوربین پشت',
        'خودکار',
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
      final send = tester.getRect(
        find.byKey(const ValueKey('capture-send-card')),
      );
      final receive = tester.getRect(
        find.byKey(const ValueKey('capture-receive-card')),
      );
      final desktop = find
          .byKey(const ValueKey('capture-desktop-columns'))
          .evaluate()
          .isNotEmpty;
      if (desktop) {
        expect(receive.top, send.top);
        expect(
          sample.fa ? receive.right < send.left : receive.left > send.right,
          true,
        );
        final output = tester.getRect(
          find.byKey(const ValueKey('capture-outputs-card')),
        );
        expect(output.top, closeTo(receive.bottom + 18, .1));
        expect(output.top, lessThan(sample.size.height));
        expect(
          find.byKey(const ValueKey('capture-settings-columns')),
          findsOneWidget,
        );
      } else {
        expect(receive.top, greaterThan(send.bottom));
      }
      if (sample.platform == TargetPlatform.windows) {
        expect(
          find.text(sample.fa ? 'دوربین پشت' : 'Rear camera'),
          findsNothing,
        );
        expect(
          find.text(
            sample.fa
                ? 'ادامهٔ انتقال در پس‌زمینه با اعلان توقف'
                : 'Continue in background with a Stop notification',
          ),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(const ValueKey('capture-outputs-card')),
          findsNothing,
        );
      }
      await saveImage(tester, sample.name);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'resizing keeps capture quality and automatic reception alongside sharing',
    (tester) async {
      tester.view.physicalSize = const Size(1844, 994);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final capture = _Capture();
      await tester.pumpWidget(
        app(capture, persian: false, scale: 1, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('High quality'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      tester.view.physicalSize = const Size(900, 780);
      await tester.pumpAndSettle();
      expect(find.text('3840 × 2160'), findsOneWidget);
      expect(find.text('Automatically receive devices'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start live capture'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        capture.started,
        true,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      expect(capture.options.width, 3840);
      expect(capture.options.bitrateKbps, 24883);
      tester.view.physicalSize = const Size(1844, 994);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('capture-session-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('capture-receive-card')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('capture-session-card')))
            .dy,
        tester
            .getTopLeft(find.byKey(const ValueKey('capture-receive-card')))
            .dy,
      );
      expect(tester.takeException(), isNull);
      await saveImage(tester, 'desktop-active');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
