import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'remote_peer_presence.dart';

const desktopSessionModes = {
  'connect',
  'file-transfer',
  'view-camera',
  'terminal',
  'port-forward',
  'rdp',
};

/// Only the retained host owns desktop windows. Primary UI requests do not
/// launch another native main process or forward through a window-title race.
class DesktopHostBridge {
  DesktopHostBridge({
    required this.openSession,
    required this.queryPresence,
    required this.synchronize,
    required this.presence,
  });
  final Future<void> Function(Map<String, dynamic>) openSession;
  final Future<void> Function(List<String>) queryPresence;
  final Future<void> Function() synchronize;
  final RemotePeerPresenceStore presence;
  HttpServer? _server;
  Future<void> _opening = Future<void>.value();
  final token = base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  Map<String, dynamic> get endpoint => {
    'bridgeVersion': 1,
    'commandPort': _server!.port,
    'commandToken': token,
  };

  Future<void> start() async {
    if (_server != null) {
      throw StateError('Remote host bridge already started.');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    try {
      if (request.headers.value('X-Localist-Host-Token') != token ||
          request.headers.value('Origin') != null) {
        response.statusCode = HttpStatus.forbidden;
        response.write(jsonEncode({'error': 'Unauthorized host request.'}));
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/command') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final decoded = jsonDecode(await _readBody(request));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid command object.');
      }
      final data = decoded;
      if (data['command'] == 'ping') {
        // The primary Localist process uses this lightweight authenticated
        // round-trip to distinguish a live retained host from an old status
        // file left behind after a crash or an update.
        response.write(jsonEncode({'ready': true}));
      } else if (data['command'] == 'openSession') {
        if (data['session'] is! Map ||
            data['session']['target'] is! String ||
            (data['session']['password'] != null &&
                data['session']['password'] is! String) ||
            (data['session']['relay'] != null &&
                data['session']['relay'] is! bool)) {
          throw const FormatException('Invalid session request.');
        }
        final session = Map<String, dynamic>.from(data['session'] as Map);
        final id = session['target'] as String? ?? '';
        if (!desktopSessionModes.contains(session['mode']) ||
            id.isEmpty ||
            id.length > 200 ||
            id.startsWith('-') ||
            id.contains(RegExp(r'[\s\x00-\x1f]')) ||
            (session['password'] as String? ?? '').length > 2048) {
          throw const FormatException('Invalid session request.');
        }
        final task = _opening.catchError((Object _) {}).then((_) async {
          await synchronize();
          await openSession(session);
        });
        _opening = task;
        await task;
        response.write(jsonEncode({'accepted': true}));
      } else if (data['command'] == 'presence') {
        if (data['ids'] is! List ||
            (data['ids'] as List).length > 500 ||
            (data['ids'] as List).any((id) => id is! String)) {
          throw const FormatException('Invalid presence IDs.');
        }
        final ids = (data['ids'] as List).cast<String>().toSet().toList();
        if (ids.length > 500 ||
            ids.any((id) => !RegExp(r'^\d{1,200}$').hasMatch(id))) {
          throw const FormatException('Invalid presence IDs.');
        }
        await synchronize();
        if (ids.isNotEmpty) await queryPresence(ids);
        response.write(jsonEncode({'states': presence.snapshot(ids)}));
      } else {
        throw const FormatException('Unknown host command.');
      }
    } on FormatException catch (error) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': error.message}));
    } catch (_) {
      response.statusCode = HttpStatus.serviceUnavailable;
      // Never echo a command/password in a log or error response.
      response.write(
        jsonEncode({
          'error': 'The remote host could not complete the request.',
        }),
      );
    } finally {
      await response.close();
    }
  }
}

Future<String> _readBody(Stream<List<int>> stream) async {
  final bytes = <int>[];
  var oversized = false;
  await for (final part in stream.timeout(const Duration(seconds: 5))) {
    if (bytes.length + part.length > 32768) oversized = true;
    if (!oversized) bytes.addAll(part);
  }
  if (oversized) throw const FormatException('Host message too large.');
  return utf8.decode(bytes);
}

Future<Map<String, dynamic>> sendDesktopHostCommand(
  Map<String, dynamic> endpoint,
  Map<String, dynamic> command, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final port = endpoint['commandPort'];
  final token = endpoint['commandToken'];
  if (endpoint['bridgeVersion'] != 1 ||
      port is! int ||
      port < 1 ||
      port > 65535 ||
      token is! String ||
      token.isEmpty) {
    throw StateError('Restart Localist to load the updated remote host.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  // Loopback traffic must bypass the user's network proxy.
  client.findProxy = (_) => 'DIRECT';
  try {
    final request = await client
        .postUrl(Uri.parse('http://127.0.0.1:$port/command'))
        .timeout(timeout);
    request.headers.set('X-Localist-Host-Token', token);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(command));
    final response = await request.close().timeout(timeout);
    final result =
        jsonDecode(await _readBody(response).timeout(timeout))
            as Map<String, dynamic>;
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        result['error'] as String? ?? 'The remote host is unavailable.',
      );
    }
    return result;
  } finally {
    client.close(force: true);
  }
}
