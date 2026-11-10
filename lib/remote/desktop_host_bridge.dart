import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'remote_peer_presence.dart';
import '../services/log_service.dart';

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
  final LogService _logs = LogService.instance;
  DesktopHostBridge({
    required this.openSession,
    required this.queryPresence,
    required this.synchronize,
    required this.presence,
    this.regeneratePassword,
    this.credentials,
  });
  final Future<void> Function(Map<String, dynamic>) openSession;
  final Future<void> Function(List<String>) queryPresence;
  final Future<void> Function() synchronize;
  final RemotePeerPresenceStore presence;
  final Future<void> Function()? regeneratePassword;
  final Future<Map<String, String>> Function()? credentials;
  HttpServer? _server;
  Future<void> _opening = Future<void>.value();
  Future<void> _synchronizing = Future<void>.value();
  final token = base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  Map<String, dynamic> get endpoint => {
    'bridgeVersion': 1,
    'commandPort': _server!.port,
    'commandToken': token,
  };

  Future<void> _synchronize() {
    _logs.debug('Remote desktop bridge profile synchronization queued');
    final next = _synchronizing.catchError((Object _) {}).then((_) {
      return synchronize();
    });
    _synchronizing = next;
    return next;
  }

  Future<void> start() async {
    _logs.debug('Remote desktop bridge opening');
    if (_server != null) {
      _logs.debug('Remote desktop bridge start rejected already running');
      throw StateError('Remote host bridge already started.');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => unawaited(_handle(request)));
    _logs.debug('Remote desktop bridge listening on loopback');
  }

  Future<void> close() async {
    _logs.debug('Remote desktop bridge closing');
    await _server?.close(force: true);
    _server = null;
    _logs.debug('Remote desktop bridge closed');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    try {
      if (request.headers.value('X-Localist-Host-Token') != token ||
          request.headers.value('Origin') != null) {
        _logs.debug(
          'Remote desktop bridge rejected unauthenticated or cross-origin request',
        );
        response.statusCode = HttpStatus.forbidden;
        response.write(jsonEncode({'error': 'Unauthorized host request.'}));
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/command') {
        _logs.debug('Remote desktop bridge rejected unsupported route');
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final decoded = jsonDecode(await _readBody(request));
      if (decoded is! Map<String, dynamic>) {
        _logs.debug('Remote desktop bridge rejected malformed command object');
        throw const FormatException('Invalid command object.');
      }
      final data = decoded;
      if (data['command'] == 'ping') {
        _logs.debug('Remote desktop bridge ping accepted');
        // The primary Localist process uses this lightweight authenticated
        // round-trip to distinguish a live retained host from an old status
        // file left behind after a crash or an update.
        response.write(jsonEncode({'ready': true}));
      } else if (data['command'] == 'syncProfile') {
        _logs.debug('Remote desktop bridge profile sync requested');
        // Profile changes are persisted by the primary Localist process. Ask
        // the retained host to apply them immediately instead of waiting for
        // its periodic status heartbeat. This is especially important for
        // authentication options: a password can be written successfully
        // while the host still accepts the previous verification method.
        await _synchronize();
        _logs.debug('Remote desktop bridge profile sync completed');
        response.write(jsonEncode({'applied': true}));
      } else if (data['command'] == 'regeneratePassword') {
        _logs.debug('Remote desktop bridge password regeneration requested');
        await _synchronize();
        final regenerate = regeneratePassword;
        if (regenerate == null) {
          throw StateError('Password regeneration is unavailable.');
        }
        await regenerate();
        _logs.debug('Remote desktop bridge password regeneration completed');
        response.write(jsonEncode({'regenerated': true}));
      } else if (data['command'] == 'credentials') {
        _logs.debug('Remote desktop bridge credential retrieval requested');
        await _synchronize();
        final read = credentials;
        if (read == null) throw StateError('Credentials are unavailable.');
        response.write(jsonEncode(await read()));
        _logs.debug('Remote desktop bridge credential retrieval completed');
      } else if (data['command'] == 'openSession') {
        _logs.debug('Remote desktop bridge open-session request received');
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
        _logs.debug(
          'Remote desktop bridge open-session validated mode=${session['mode']} relay=${session['relay'] == true} passwordProvided=${(session['password'] as String? ?? '').isNotEmpty}',
        );
        final task = _opening.catchError((Object _) {}).then((_) async {
          await _synchronize();
          await openSession(session);
        });
        _opening = task;
        await task;
        _logs.debug('Remote desktop bridge open-session command completed');
        response.write(jsonEncode({'accepted': true}));
      } else if (data['command'] == 'presence') {
        _logs.debug('Remote desktop bridge presence query received');
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
        await _synchronize();
        if (ids.isNotEmpty) await queryPresence(ids);
        _logs.debug(
          'Remote desktop bridge presence query completed ids=${ids.length}',
        );
        response.write(jsonEncode({'states': presence.snapshot(ids)}));
      } else {
        _logs.debug('Remote desktop bridge rejected unknown command');
        throw const FormatException('Unknown host command.');
      }
    } on FormatException catch (error) {
      _logs.debug('Remote desktop bridge malformed command rejected');
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': error.message}));
    } catch (error) {
      _logs.debug(
        'Remote desktop bridge command failed type=${error.runtimeType}',
      );
      response.statusCode = HttpStatus.serviceUnavailable;
      // Never echo a command/password in a log or error response.
      response.write(
        jsonEncode({
          'error': 'The remote host could not complete the request.',
        }),
      );
    } finally {
      await response.close();
      _logs.debug(
        'Remote desktop bridge command response closed status=${response.statusCode}',
      );
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
  final logs = LogService.instance;
  // Never log the request body or token; only the whitelisted command kind.
  const commands = {
    'ping',
    'syncProfile',
    'regeneratePassword',
    'credentials',
    'openSession',
    'presence',
  };
  final operation = commands.contains(command['command'])
      ? command['command']
      : 'unknown';
  logs.debug(
    'Remote desktop command outgoing kind=$operation timeoutMs=${timeout.inMilliseconds}',
  );
  final port = endpoint['commandPort'];
  final token = endpoint['commandToken'];
  if (endpoint['bridgeVersion'] != 1 ||
      port is! int ||
      port < 1 ||
      port > 65535 ||
      token is! String ||
      token.isEmpty) {
    logs.debug('Remote desktop command refused invalid bridge metadata');
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
    logs.debug(
      'Remote desktop command HTTP response status=${response.statusCode} kind=$operation',
    );
    final result =
        jsonDecode(await _readBody(response).timeout(timeout))
            as Map<String, dynamic>;
    if (response.statusCode != HttpStatus.ok) {
      logs.debug('Remote desktop command returned failure kind=$operation');
      throw StateError(
        result['error'] as String? ?? 'The remote host is unavailable.',
      );
    }
    logs.debug('Remote desktop command succeeded kind=$operation');
    return result;
  } finally {
    logs.debug('Remote desktop command connection closing kind=$operation');
    client.close(force: true);
  }
}
