import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localist/services/virtual_adb_endpoint_service.dart';

Future<void> main(List<String> arguments) async {
  final endpoint = VirtualAdbEndpointService();
  var printedConnections = 0;
  var printedRejects = 0;
  var printedError = '';
  endpoint.addListener(() {
    if (endpoint.acceptedConnections != printedConnections) {
      printedConnections = endpoint.acceptedConnections;
      stdout.writeln('ADB transport connected ($printedConnections total).');
    }
    if (endpoint.rejectedServices != printedRejects) {
      printedRejects = endpoint.rejectedServices;
      stdout.writeln(
        'ADB service explicitly rejected: ${endpoint.lastRejectedService}',
      );
    }
    final error = endpoint.lastError ?? '';
    if (error.isNotEmpty && error != printedError) {
      printedError = error;
      stdout.writeln('ADB endpoint diagnostic: $error');
    }
  });

  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (Platform.isWindows && localAppData != null) {
    final adb =
        Platform.environment['ADB_EXE'] ??
        '$localAppData\\Android\\Sdk\\platform-tools\\adb.exe';
    if (arguments.contains('--self-test')) {
      await _runSelfTest(endpoint, adb);
      return;
    }
  } else if (arguments.contains('--self-test')) {
    stderr.writeln('--self-test currently requires Windows Android SDK.');
    exitCode = 2;
    return;
  }

  final address = await endpoint.start();
  stdout.writeln('Virtual ADB PoC listening on $address (loopback only).');
  stdout.writeln('Run: adb connect $address');
  stdout.writeln('Then: adb devices -l');
  stdout.writeln('Press Enter to stop.');
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await endpoint.stop();
  endpoint.dispose();
  stdout.writeln('Virtual ADB PoC stopped.');
}

Future<void> _runSelfTest(
  VirtualAdbEndpointService endpoint,
  String adb,
) async {
  if (!await File(adb).exists()) {
    stderr.writeln('ADB executable not found: $adb');
    exitCode = 2;
    return;
  }
  final address = await endpoint.start();
  try {
    final connect = await Process.run(adb, ['connect', address]);
    if (connect.exitCode != 0 ||
        !'${connect.stdout}${connect.stderr}'.contains('connected to')) {
      throw StateError(
        'adb connect failed: ${connect.stdout}${connect.stderr}',
      );
    }
    stdout.writeln('PASS adb connect: $address');

    final listing = await Process.run(adb, ['devices', '-l']);
    final devicesOutput = '${listing.stdout}${listing.stderr}';
    if (listing.exitCode != 0 ||
        !RegExp(
          '^${RegExp.escape(address)}\\s+device\\b',
          multiLine: true,
        ).hasMatch(devicesOutput)) {
      throw StateError(
        'ADB did not enumerate the PoC as device:\n$devicesOutput',
      );
    }
    stdout.writeln('PASS adb devices -l: device state');

    final shell = await Process.run(adb, [
      '-s',
      address,
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    if (shell.exitCode == 0 ||
        !(shell.stdout.toString() + shell.stderr.toString()).contains(
          'closed',
        ) ||
        endpoint.lastRejectedService?.startsWith('shell:') != true) {
      throw StateError(
        'Unsupported shell was not explicitly rejected: ${shell.stdout}${shell.stderr}',
      );
    }
    stdout.writeln('PASS unsupported shell rejected and recorded');

    final apk = File(
      '${Directory.current.path}${Platform.pathSeparator}'
      'build${Platform.pathSeparator}app${Platform.pathSeparator}'
      'outputs${Platform.pathSeparator}flutter-apk${Platform.pathSeparator}'
      'app-debug.apk',
    );
    if (await apk.exists()) {
      final rejectedBeforeInstall = endpoint.rejectedServices;
      final install = await Process.run(adb, [
        '-s',
        address,
        'install',
        '-r',
        apk.path,
      ]);
      if (install.exitCode == 0 ||
          endpoint.rejectedServices <= rejectedBeforeInstall) {
        throw StateError(
          'Unsupported ADB install was not explicitly rejected: '
          '${install.stdout}${install.stderr}',
        );
      }
      stdout.writeln(
        'PASS APK install rejected (${endpoint.lastRejectedService})',
      );
    }

    final disconnect = await Process.run(adb, ['disconnect', address]);
    if (disconnect.exitCode != 0) {
      throw StateError(
        'ADB disconnect failed: ${disconnect.stdout}${disconnect.stderr}',
      );
    }
    stdout.writeln('PASS adb disconnect: session cleanup');
  } catch (error) {
    stderr.writeln('FAIL Virtual ADB integration test: $error');
    exitCode = 1;
  } finally {
    await endpoint.stop();
    endpoint.dispose();
  }
}
