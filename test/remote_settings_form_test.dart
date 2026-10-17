import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/screens/remote_control_settings_section.dart';
import 'package:localist/services/rustdesk_debug_service.dart';

class _SettingsEngine extends RustDeskDebugService {
  final passwords = <String>[];
  bool rejectPassword = false;

  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> printerNames() async => [];
  @override
  Future<List<String>> audioInputNames() async => ['QA microphone'];
  @override
  Future<void> saveProfileValue(String key, String value) async {
    profile.values[key] = value;
    notifyListeners();
  }

  @override
  Future<void> setPermanentPassword(String password) async {
    if (rejectPassword) throw StateError('Native daemon rejected the password');
    passwords.add(password);
    hasPermanentPassword = password.isNotEmpty;
    notifyListeners();
  }
}

void main() {
  Future<_SettingsEngine> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _SettingsEngine()..hasPermanentPassword = true;
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(body: RemoteControlSettingsSection(service: engine)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security').first);
    await tester.pumpAndSettle();
    final button = find.text('Set permanent password');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    return engine;
  }

  testWidgets('empty password form cannot erase an existing password', (
    tester,
  ) async {
    final engine = await openForm(tester);
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();
    expect(engine.passwords, isEmpty);
    expect(engine.hasPermanentPassword, isTrue);
    expect(find.textContaining('Enter a new password;'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'password form validates and submits exactly the entered password',
    (tester) async {
      final engine = await openForm(tester);
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, '  ValidPass1  ');
      await tester.enterText(fields.last, 'Different1');
      await tester.tap(find.text('Set password'));
      await tester.pumpAndSettle();
      expect(engine.passwords, isEmpty);
      expect(find.text('The confirmation does not match'), findsOneWidget);
      await tester.enterText(fields.last, 'ValidPass1');
      await tester.tap(find.text('Set password'));
      await tester.pumpAndSettle();
      expect(engine.passwords, ['ValidPass1']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('Permanent password saved and enabled for connections'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native password failure stays visible and does not report success',
    (tester) async {
      final engine = await openForm(tester);
      engine.rejectPassword = true;
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, 'ValidPass1');
      await tester.enterText(fields.last, 'ValidPass1');
      await tester.tap(find.text('Set password'));
      await tester.pumpAndSettle();
      expect(engine.passwords, isEmpty);
      expect(find.textContaining('Native daemon rejected'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native audio inputs can be selected and offline printers stay saved',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = _SettingsEngine();
      engine.profile.values['printer-selected-name'] = 'Offline printer';
      engine.profile.values['printer-incomming-job-action'] = 'selected';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: RemoteControlSettingsSection(service: engine)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Auto update engine'), findsNothing);
      await tester.tap(find.text('Default device audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('QA microphone').last);
      await tester.pumpAndSettle();
      expect(engine.profile.values['audio-input'], 'QA microphone');
      expect(engine.profile.values['printer-selected-name'], 'Offline printer');
      expect(engine.profile.values['printer-incomming-job-action'], 'selected');
      await tester.tap(find.text('Printer').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved printer unavailable:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      engine.dispose();
    },
  );
}
