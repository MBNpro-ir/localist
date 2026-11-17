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
        if (session['mode'] == 'port-forward' &&
            session.containsKey('initialForward')) {
          final forward = session['initialForward'];
          if (forward is! Map ||
              forward['localPort'] is! int ||
              (forward['localPort'] as int) < 1 ||
              (forward['localPort'] as int) > 65535 ||
              forward['remotePort'] is! int ||
              (forward['remotePort'] as int) < 1 ||
              (forward['remotePort'] as int) > 65535 ||
              !const {'127.0.0.1', 'localhost', '::1'}.contains(
                (forward['remoteHost'] as String?)?.trim().toLowerCase(),
              )) {
            throw const FormatException('Invalid network tunnel target.');
          }
          session['initialForward'] = Map<String, dynamic>.from(forward);
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
        final ids = (data['ids']