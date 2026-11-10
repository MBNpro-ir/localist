import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/screens/live_capture_page.dart';
import 'package:localist/services/capture_discovery_service.dart';
import 'package:localist/services/capture_hub_service.dart';
import 'package:localist/services/live_capture_service.dart';
import 'package:localist/services/log_service.dart';
import 'package:localist/services/windows_virtual_devices_service.dart';
import 'package:localist/services/capture_audio_settings.dart';
import 'package:localist/widgets/capture_receivers_panel.dart';

class _Stream extends Fake implements MediaStream {
  @override
  List<MediaStreamTrack> getVideoTracks() => [];
  @override
  List<MediaStreamTrack> getAudioTracks() => [];
}

class _Capture extends LiveCaptureService {
  bool started = false;
  final commands = <Map<String, dynamic>>[];
  @override
  Future<void> requestCaptureControl(Map<String, dynamic> command) async {
    commands.add(command);
    options = options.copyWith(
      audioSettings: options.audioSettings.withValues(command),
    );
    notifyListeners();
  }

  @override
  Future<void> selectMicrophone(String id) async {
    options = options.copyWith(microphoneId: id);
    notifyListeners();
  }

  @override
  bool get broadcasting => started;
  @override
  Future<void> start(LiveCaptureOptions value, {int port = 0}) async {
    options = value;
    localStream = _Stream();
    started = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    started = false;
  }
}

class _Preview extends RTCVideoRenderer {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> setSrcObject({MediaStream? stream, String? trackId}) async {}
}

class _Hub extends CaptureHubService {
  _Hub(this.peer);
  final CaptureReceiver peer;
  @override
  List<CaptureReceiver> get receivers => [peer];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const media = MethodChannel('FlutterWebRTC.Method');
  const bridge = MethodChannel('com.prs.localist.vpn');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(media, (_) async => null);
    await LiveCaptureService.initializeMedia();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      media,
      (call) async => call.method == 'getSources'
          ? {
              'sources': [
                {
                  'deviceId': 'mic',
                  'kind': 'audioinput',
                  'label': 'Phone microphone',
                },
              ],
            }
          : null,
    );
    messenger.setMockMethodCallHandler(
      bridge,
      (_) async => <String, dynamic>{},
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('localist/audioDevices'),
      (_) async => null,
    );
  });
  testWidgets('Bluetooth input appears automatically on device changes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var bluetooth = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          media,
          (call) async => call.method == 'getSources'
              ? {
                  'sources': [
                    {
                      'deviceId': 'mic',
                      'kind': 'audioinput',
                      'label': 'Phone microphone',
                    },
                    if (bluetooth)
                      {
                        'deviceId': 'bluetooth',
                        'kind': 'audioinput',
                        'label': 'Bluetooth headset',
                      },
                    if (bluetooth)
                      {
                        'deviceId': 'bluetooth',
                        'kind': 'audioinput',
                        'label': 'Bluetooth headset',
                      },
                  ],
                }
              : null,
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveCapturePage(service: _Capture(), renderer: _Preview()),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth audio permission'), findsNothing);
    expect(find.byTooltip('Refresh inputs'), findsNothing);
    bluetooth = true;
    await tester.runAsync(() async {
      navigator.mediaDevices.ondevicechange?.call(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final inputs = tester.widgetList<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    final mic = inputs.firstWhere(
      (input) => input.items?.any((item) => item.value == 'mic') == true,
    );
    expect(mic.items!.where((item) => item.value == 'bluetooth'), hasLength(1));
    bluetooth = false;
    expect(navigator.mediaDevices.ondevicechange, isNotNull);
    await tester.runAsync(() async {
      navigator.mediaDevices.ondevicechange?.call(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final updated = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .firstWhere(
          (input) => input.items?.any((item) => item.value == 'mic') == true,
        );
    expect(updated.items!.where((item) => item.value == 'bluetooth'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Server settings keep their positions and accept local and Player changes while live',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = _Capture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveCapturePage(service: capture, renderer: _Preview()),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Camera'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 30 &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Start live capture'),
                    )
                    .onPressed ==
                null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      final microphoneBefore = tester.getRect(find.text('Microphone input'));
      final gainBefore = tester.getTopLeft(find.text('Automatic gain'));
      await tester.tap(find.text('Start live capture'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(capture.started, true);
      expect(tester.getRect(find.text('Microphone input')), microphoneBefore);
      expect(tester.getTopLeft(find.text('Automatic gain')), gainBefore);
      await tester.drag(find.byType(Slider).first, const Offset(-500, 0));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(capture.options.audioSettings.gainDb, -30);
      expect(capture.commands, isNotEmpty);
      // The server receives the same applied state that a Player update broadcasts.
      capture.options = capture.options.copyWith(
        audioSettings: const CaptureAudioSettings(gainDb: 40, bitrateKbps: 256),
      );
      capture.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Manual gain: 40 dB'), findsOneWidget);
      expect(tester.getRect(find.text('Microphone input')), microphoneBefore);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(media, null);
    messenger.setMockMethodCallHandler(bridge, null);
  });
  testWidgets(
    'Android hides reception while sending and restores it after stop',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final capture = _Capture()..started = true;
      capture.options = const LiveCaptureOptions(camera: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveCapturePage(service: capture, renderer: _Preview()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('capture-receive-card')), findsNothing);
      expect(find.text('USB, OBS & virtual device guide'), findsNothing);
      capture.started = false;
      capture.notifyListeners();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Receiver'));
      await tester.tap(find.text('Receiver'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('capture-receive-card')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final camera in [false, true]) {
    testWidgets(
      'receiver exposes only ${camera ? 'camera' : 'microphone'} controls',
      (tester) async {
        final capture = _Capture();
        final renderer = _Preview();
        final peer = CaptureReceiver(
          CaptureAdvertisement(
            id: 'media-controls-peer',
            name: 'Phone',
            model: 'Test phone',
            host: '192.168.42.1',
            port: 1234,
            key: 'x' * 43,
            camera: camera,
            microphone: !camera,
          ),
          0,
          capture,
          renderer,
          WindowsVirtualDevicesService(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CaptureReceiversPanel(hub: _Hub(peer), windows: true),
            ),
          ),
        );
        await tester.tap(find.text('Phone'));
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('Toggle video'),
          camera ? findsOneWidget : findsNothing,
        );
        expect(
          find.byTooltip('Toggle this device audio'),
          camera ? findsNothing : findsOneWidget,
        );
        if (!camera) {
          expect(find.textContaining('Localist Camera'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        capture.dispose();
      },
    );
  }
  testWidgets(
    'microphone-only sending has no camera preview or camera actions',
    (tester) async {
      await tester.runAsync(() async {
        expect(
          (await LiveCaptureService.inputDevices()).where(
            (d) => d.kind == 'audioinput',
          ),
          isNotEmpty,
        );
      });
      final capture = _Capture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveCapturePage(service: capture, renderer: _Preview()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Camera'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start live capture'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 30 &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Start live capture'),
                    )
                    .onPressed ==
                null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start live capture'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Start live capture'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(
        capture.started,
        true,
        reason:
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join(' | ') +
            LogService.instance.dump(),
      );
      expect(capture.options.camera, false);
      expect(find.byType(RTCVideoView), findsNothing);
      expect(find.byTooltip('Mute microphone'), findsOneWidget);
      expect(find.byTooltip('Pause camera'), findsNothing);
      expect(find.byTooltip('Switch camera'), findsNothing);
      expect(find.byTooltip('Mirror preview'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
