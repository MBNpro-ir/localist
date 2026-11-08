import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/media_stream_service.dart';

/// Launched by test_stream_web.cjs against synthetic files in the workspace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('real local media server for browser acceptance', () async {
    final root = Directory('${Directory.current.path}/.runlogs/stream-web-qa');
    final service = MediaStreamService.instance;
    try {
      service.persian = true;
      await service.startFiles([
        for (final name in [
          'Mountain trail.mp4',
          'Evening colours.png',
          'Coastal lines.png',
          'Ambient session.wav',
          'Unavailable clip.mp4',
          'نور صبح ـ خاطرهٔ سفر در یک روز آرام و طولانی.png',
        ])
          File('${root.path}/fixtures/$name'),
      ]);
      await File(
        '${root.path}/port.json',
      ).writeAsString(jsonEncode({'port': service.port}));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (!await File('${root.path}/done').exists() &&
          DateTime.now().isBefore(deadline)) {
        final language = File('${root.path}/language');
        if (await language.exists()) {
          final value = await language.readAsString();
          service.persian = value == 'fa';
          await File('${root.path}/language-applied').writeAsString(value);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await File('${root.path}/done').exists(), true);
    } finally {
      await service.stop();
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
