import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/log_service.dart';
import 'package:localist/services/native_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.prs.localist.vpn');

  tearDown(() {
    LogService.instance.setDebugMode(false);
    LogService.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'native bridge debug traces do not include sensitive arguments',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return true;
          });

      LogService.instance.setDebugMode(true);
      const secret = 'secret-value-QA-please-do-not-log';
      expect(
        await NativeBridgeService.instance.applyRemoteOption(
          r'C:\private\config.toml',
          'password',
          secret,
        ),
        true,
      );

      final output = LogService.instance.dump();
      expect(methods, ['applyRemoteOption']);
      expect(output, contains('NativeBridge -> applyRemoteOption'));
      expect(output, contains('NativeBridge <- applyRemoteOption'));
      expect(output, contains('map(size=3)'));
      expect(output, isNot(contains(secret)));
      expect(output, isNot(contains('config.toml')));
      expect(output, isNot(contains('password')));
    },
  );

  test('native bridge does not emit traces when Debug is disabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);

    LogService.instance.setDebugMode(false);
    LogService.instance.clear();
    await NativeBridgeService.instance.applyRemoteOption(
      'path',
      'key',
      'value',
    );
    expect(LogService.instance.entries, isEmpty);
  });

  test('native failures do not log credential or path payloads', () async {
    const secret = 'native-error-secret-QA';
    const privatePath = r'C:\private\native-error.toml';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'REMOTE_OPTION_FAILED',
            message: 'Could not apply $secret at $privatePath',
            details: {'password': secret},
          );
        });
    LogService.instance.setDebugMode(true);
    await expectLater(
      NativeBridgeService.instance.applyRemoteOption(
        privatePath,
        'password',
        secret,
      ),
      throwsA(isA<PlatformException>()),
    );
    final output = LogService.instance.dump();
    expect(output, contains('NativeBridge !! applyRemoteOption failed'));
    expect(output, isNot(contains(secret)));
    expect(output, isNot(contains(privatePath)));
  });
}
