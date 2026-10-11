import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localist/services/crash_reporter_service.dart';
import 'package:localist/services/log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'an unhandled error never enables Debug or opens a window/mail client',
    () async {
      SharedPreferences.setMockInitialValues({'debug.activeMode': false});
      final calls = <String>[];
      const channel = MethodChannel('com.prs.localist.vpn');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return true;
          });
      await CrashReporterService.instance.reportFatalError(
        StateError('QA unhandled error'),
        StackTrace.current,
      );
      expect(LogService.instance.debugModeEnabled, false);
      expect(
        (await SharedPreferences.getInstance()).getBool('debug.activeMode'),
        false,
      );
      expect(calls, isEmpty);
      expect(
        LogService.instance.entries.any(
          (e) => e.message.contains('QA unhandled error'),
        ),
        true,
      );
    },
  );
}
