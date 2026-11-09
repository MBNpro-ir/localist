import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/screens/remote_debug_page.dart';
import 'package:localist/services/remote_device_service.dart';
import 'package:localist/services/rustdesk_debug_service.dart';

class _ReadyRemote extends RustDeskDebugService {
  _ReadyRemote() {
    ready = true;
    online = true;
    hosting = true;
    localId = '123456';
    localPassword = 'qa-password';
  }
  @override
  Future<void> initialize() async {}
  void updateInputPermission(bool value) {
    inputEnabled = value;
    notifyListeners();
  }
}

class _EmptyDevices extends RemoteDeviceService {
  @override
  Future<void> initialize() async {}
}

void main() {
  testWidgets(
    'Android input request disappears after grant and returns after revocation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final remote = _ReadyRemote(), devices = _EmptyDevices();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteDebugPage(service: remote, devices: devices),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Enable input permission'), findsOneWidget);
      remote.updateInputPermission(true);
      await tester.pump();
      expect(find.text('Enable input permission'), findsNothing);
      expect(find.text('Input permission enabled'), findsNothing);
      remote.updateInputPermission(false);
      await tester.pump();
      expect(find.text('Enable input permission'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
      devices.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final persian in [false, true]) {
    testWidgets('remote screen has one device heading and a connect heading '
        '(${persian ? 'Persian' : 'English'})', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReadyRemote();
      final devices = _EmptyDevices();
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(persian ? 'fa' : 'en'),
          supportedLocales: const [Locale('en'), Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: RemoteDebugPage(service: remote, devices: devices),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text(persian ? 'این دستگاه' : 'This device'), findsOneWidget);
      final headings = tester.widgetList<Text>(
        find.text(persian ? 'اتصال' : 'Connect'),
      );
      expect(headings.any((text) => text.style != null), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      remote.dispose();
      devices.dispose();
    });
  }
}
