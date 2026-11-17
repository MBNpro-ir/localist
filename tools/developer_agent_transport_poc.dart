import 'dart:convert';
import 'dart:io';

import 'package:localist/services/developer_agent_transport.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    stderr.writeln(
      'Usage: dart run tools/developer_agent_transport_poc.dart '
      '<host> <port> <pairing-code> <certificate-sha256> <apk-path>',
    );
    exitCode = 64;
    return;
  }

  final host = args[0];
  final port = int.parse(args[1]);
  final pairingCode = args[2];
  final fingerprint = args[3];
  final apk = File(args[4]);

  Future<void> expectRejected(
    String label,
    LocalLanTransport client,
    RegExp expectedFailure,
  ) async {
    String? failure;
    try {
      await client.connect();
    } on Exception catch (error) {
      failure = error.toString();
    } finally {
      await client.close();
    }
    if (failure == null) throw StateError('$label was unexpectedly accepted');
    if (!expectedFailure.hasMatch(failure)) {
      throw StateError('$label failed for an unexpected reason: $failure');
    }
    stdout.writeln('PASS $label rejected');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  final wrongPin = LocalLanTransport(
    host: host,
    port: port,
    pairingCode: pairingCode,
    certificateSha256: fingerprint == List.filled(32, '00').join()
        ? List.filled(32, '11').join()
        : List.filled(32, '00').join(),
  );
  await expectRejected(
    'wrong TLS pin',
    wrongPin,
    RegExp(r'CERTIFICATE_VERIFY_FAILED|certificate verify|certificate rejected', caseSensitive: false),
  );

  final wrongCode = LocalLanTransport(
    host: host,
    port: port,
    pairingCode: pairingCode == '00000000' ? '00000001' : '00000000',
    certificateSha256: fingerprint,
  );
  await expectRejected(
    'wrong pairing code',
    wrongCode,
    RegExp(r'Android Agent closed the connection|connection closed', caseSensitive: false),
  );

  final client = LocalLanTransport(
    host: host,
    port: port,
    pairingCode: pairingCode,
    certificateSha256: fingerprint,
  );
  await client.connect();
  stdout.writeln('PASS authenticated TLS session');

  final payload = <String, Object?>{
    'purpose': 'developer-agent-echo-poc',
    'numbers': [1, 2, 3],
  };
  final echoed = await client.echo(payload);
  if (jsonEncode(echoed) != jsonEncode(payload)) {
    throw StateError('Echo payload did not round-trip');
  }
  stdout.writeln('PASS authenticated echo');

  final received = await client.sendApk(apk);
  final size = await apk.length();
  if (received['type'] != 'apkReceived' ||
      received['size'] != size ||
      received['sha256'] == null ||
      received['packageName'] == null) {
    throw StateError('Android returned incomplete APK validation metadata');
  }
  stdout.writeln('PASS APK transfer and Android package validation');

  await client.close();
  if (client.isConnected) throw StateError('Client remained connected after close');
  stdout.writeln('PASS disconnect');

  final reconnect = LocalLanTransport(
    host: host,
    port: port,
    pairingCode: pairingCode,
    certificateSha256: fingerprint,
  );
  await reconnect.connect();
  if (await reconnect.echo('reconnected') != 'reconnected') {
    throw StateError('Agent did not recover after disconnect');
  }
  await reconnect.close();
  stdout.writeln('PASS reconnect after disconnect');
}
