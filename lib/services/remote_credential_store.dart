import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'log_service.dart';

/// Passwords are scoped to the ID server so identical IDs on different servers
/// cannot reuse a credential. Never put plaintext in preferences or peer JSON.
class RemoteCredentialStore {
  RemoteCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String server, String id) =>
      'localist.remote.peer.${sha256.convert(utf8.encode('$server\n$id'))}';
  Future<String?> read(String server, String id) async {
    LogService.instance.debug(
      'Remote credential lookup requested serverScoped=${server.isNotEmpty}',
    );
    try {
      final credential = await _storage.read(key: _key(server, id));
      LogService.instance.debug(
        'Remote credential lookup finished found=${credential != null}',
      );
      return credential;
    } catch (error) {
      LogService.instance.debug(
        'Remote credential lookup failed type=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> write(String server, String id, String password) {
    if (password.length > 128 ||
        password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      LogService.instance.debug(
        'Remote credential update rejected by validation',
      );
      throw const FormatException('Invalid peer password.');
    }
    LogService.instance.debug(
      'Remote credential update requested operation=${password.isEmpty ? 'delete' : 'write'}',
    );
    return (password.isEmpty
            ? _storage.delete(key: _key(server, id))
            : _storage.write(key: _key(server, id), value: password))
        .then(
          (_) {
            LogService.instance.debug('Remote credential update finished');
          },
          onError: (Object error) {
            LogService.instance.debug(
              'Remote credential update failed type=${error.runtimeType}',
            );
            throw error;
          },
        );
  }
}
