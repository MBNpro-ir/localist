import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/windows_vpn_worker.dart';

void main() {
  test(
    'encoded worker treats arguments as data and reports launch failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'localist-worker-test-',
      );
      final sentinel = File('${directory.path}/must-not-exist');
      final script = buildWindowsVpnScript({
        'exe': '${directory.path}/missing.exe',
        'parentPid': pid,
        'lease': directory.path,
        'args': [
          '-proxy',
          "http://user:\$(New-Item -Path '${sentinel.path}')@localhost:10808",
        ],
        'route': null,
      });
      expect(script, isNot(contains(sentinel.path)));
      final file = File('${directory.path}/worker.ps1');
      await file.writeAsString(script);
      final parse = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$tokens=\$null; \$errors=\$null; [Management.Automation.Language.Parser]::ParseFile('${file.path}',[ref]\$tokens,[ref]\$errors) | Out-Null; if(\$errors.Count){ \$errors | ForEach-Object Message; exit 1 }",
      ]);
      expect(parse.exitCode, 0, reason: '${parse.stdout} ${parse.stderr}');
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encodeWindowsCommand(script),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final state =
          jsonDecode(
                (await File(
                  '${directory.path}/status.json',
                ).readAsString()).replaceFirst('\uFEFF', ''),
              )
              as Map;
      expect(state['ready'], isFalse);
      expect(state['error'], isNotEmpty);
      expect(await sentinel.exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );
}
