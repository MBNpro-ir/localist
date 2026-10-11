import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A scoped elevated worker owns only tun2socks and its routes. Localist's UI,
/// navigator and pending operation stay in the original unelevated process.
class WindowsVpnWorker {
  Directory? _lease;
  Timer? _monitor;
  bool ready = false;
  Future<void> start({
    required String executable,
    required List<String> arguments,
    Map<String, String>? route,
    required void Function() onExit,
  }) async {
    await stop();
    final lease = await Directory.systemTemp.createTemp('localist-vpn-');
    _lease = lease;
    final config = {
      'exe': executable,
      'args': arguments,
      'parentPid': pid,
      'lease': lease.path,
      'route': route,
    };
    final encoded = encodeWindowsCommand(buildWindowsVpnScript(config));
    final launch = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "try { Start-Process -FilePath (Join-Path \$PSHOME 'powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile -NonInteractive -EncodedCommand $encoded' -ErrorAction Stop | Out-Null } catch { exit 1 }",
    ]);
    if (launch.exitCode != 0) {
      throw PlatformException(
        code: 'windows_admin_required',
        message: 'Administrator permission was cancelled.',
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final status = await _status(lease);
      if (status?['ready'] == true) {
        ready = true;
        _monitor = Timer.periodic(const Duration(seconds: 1), (_) async {
          if ((await _status(lease))?['ready'] == false &&
              identical(_lease, lease)) {
            ready = false;
            _monitor?.cancel();
            onExit();
          }
        });
        return;
      }
      if (status?['error'] is String) {
        throw PlatformException(
          code: 'wintun_start_failed',
          message: status!['error'] as String,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await stop();
    throw PlatformException(
      code: 'wintun_start_failed',
      message: 'The elevated VPN worker did not become ready.',
    );
  }

  Future<Map<String, dynamic>?> _status(Directory lease) async {
    try {
      return jsonDecode(
            (await File(
              '${lease.path}/status.json',
            ).readAsString()).replaceFirst('\uFEFF', ''),
          )
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    _monitor?.cancel();
    final lease = _lease;
    _lease = null;
    ready = false;
    if (lease == null) return;
    await File('${lease.path}/stop').writeAsString('stop');
    for (var n = 0; n < 50; n++) {
      if ((await _status(lease))?['ready'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

String encodeWindowsCommand(String text) {
  final bytes = ByteData(text.codeUnits.length * 2);
  for (var i = 0; i < text.codeUnits.length; i++) {
    bytes.setUint16(i * 2, text.codeUnits[i], Endian.little);
  }
  return base64Encode(bytes.buffer.asUint8List());
}

String buildWindowsVpnScript(Map<String, Object?> config) {
  // All untrusted values are JSON data, never interpolated as PowerShell code.
  final data = base64Encode(utf8.encode(jsonEncode(config)));
  return "\$cfg = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$data')) | ConvertFrom-Json\n"
      r'''
$ErrorActionPreference = 'Stop'
$routes = [Collections.Generic.List[object]]::new()
$tun = $null
$failure = ''
function Status([bool]$ready, [string]$errorText = '') {
  @{ ready=$ready; error=$errorText; pid=$PID } | ConvertTo-Json -Compress |
    Set-Content -LiteralPath (Join-Path $cfg.lease 'status.json') -Encoding UTF8
}
function QuoteArg([string]$value) {
  '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Netsh([string[]]$argv) {
  & (Join-Path $env:WINDIR 'System32\netsh.exe') @argv | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Windows could not configure the VPN interface or route.' }
}
function AddRoute([string]$prefix, [string]$iface, [string]$gateway) {
  Netsh -argv @('interface','ipv4','add','route',$prefix,$iface,$gateway,'metric=1','store=active')
  $routes.Add(@($prefix,$iface,$gateway))
}
try {
  $parent = Get-Process -Id $cfg.parentPid -ErrorAction Stop
  $argumentLine = ($cfg.args | ForEach-Object { QuoteArg $_ }) -join ' '
  $tun = Start-Process -FilePath $cfg.exe -WorkingDirectory (Split-Path -Parent $cfg.exe) -ArgumentList $argumentLine -WindowStyle Hidden -PassThru
  $found = $false
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    if ($tun.HasExited) { throw 'The VPN engine exited before the interface was ready.' }
    & (Join-Path $env:WINDIR 'System32\netsh.exe') interface show interface name=wintun | Out-Null
    if ($LASTEXITCODE -eq 0) { $found = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$found) { throw 'The Wintun interface did not appear.' }
  Netsh -argv @('interface','ipv4','set','address','name=wintun','source=static','addr=198.18.0.1','mask=255.254.0.0')
  Netsh -argv @('interface','ipv4','set','dnsservers','name=wintun','static','address=1.1.1.1','register=none','validate=no')
  if ($cfg.route) { AddRoute ($cfg.route.ip + '/32') $cfg.route.interface $cfg.route.gateway }
  AddRoute '0.0.0.0/1' 'wintun' '198.18.0.1'
  AddRoute '128.0.0.0/1' 'wintun' '198.18.0.1'
  Status $true
  while (!$tun.HasExited -and !$parent.HasExited -and !(Test-Path -LiteralPath (Join-Path $cfg.lease 'stop'))) {
    Start-Sleep -Milliseconds 250
    $parent.Refresh()
    $tun.Refresh()
  }
} catch {
  $failure = $_.Exception.Message
} finally {
  foreach ($route in $routes) {
    & (Join-Path $env:WINDIR 'System32\netsh.exe') interface ipv4 delete route $route[0] $route[1] $route[2] store=active | Out-Null
  }
  if ($tun -and !$tun.HasExited) { Stop-Process -Id $tun.Id -ErrorAction SilentlyContinue }
  Status $false $failure
}
''';
}
