import 'dart:convert';
import 'dart:io';

import 'package:localist/services/developer_agent_transport.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tools/developer_agent_rustdesk_transport_poc.dart '
      '<local-forward-port> <pairing-code> <certificate-sha256> [apk-path]',
    );
    exitCode = 64;
    return;
  }

  final localPort = int.parse(args[0]);
  final pairingCode = args[1];
  final fingerprint = args[2];
  final apk = args.length == 4 ? File(args[3]) : null;
  final client = RustDeskRemoteTransport(
    localPort: localPort,
    pairingCode: pairingCode,
    certificateSha256: fingerprint,
  );

  try {
    await client.connect();
    stdout.writeln('PASS RustDesk local-forward TLS and pairing');

    const payload = {
      'purpose': 'developer-agent-rustdesk-transport-poc',
      'sequence': [1, 2, 3],
    };
    final echoed = await client.echo(payload);
    if (jsonEncode(echoed) != jsonEncode(payload)) {
      throw StateError('RustDesk transport Echo payload did not round-trip');
    }
    stdout.writeln('PASS RustDesk adapter Echo');

    if (apk != null) {
      if (!await apk.exists()) {
        throw FileSystemException('APK not found', apk.path);
      }
      final result = await client.sendApk(apk);
      if (result['type'] != 'apkReceived' ||
          result['size'] != await apk.length() ||
          result['sha256'] == null ||
          result['packageName'] == null) {
        throw StateError('Android returned incomplete APK validation metadata');
      }
      stdout.writeln('PASS RustDesk adapter APK transfer and validation');
    }
  } finally {
    await client.close();
  }
  if (client.isConnected) {
    throw StateError('RustDesk adapter remained connected');
  }
  stdout.writeln('PASS RustDesk adapter disconnect');

  final reconnect = RustDeskRemoteTransport(
    localPort: localPort,
    pairingCode: pairingCode,
    certificateSha256: fingerprint,
  );
  try {
    await reconnect.connect();
    if (await reconnect.echo('reconnected') != 'reconnected') {
      throw StateError('RustDesk adapter did not recover after disconnect');
    }
    stdout.writeln('PASS RustDesk adapter reconnect');
  } finally {
    await reconnect.close();
  }
}
