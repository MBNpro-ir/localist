import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Passwords are scoped to the ID server so identical IDs on different servers
/// cannot reuse a credential. Never put plaintext in preferences or peer JSON.
class RemoteCredentialStore {
  RemoteCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String server, String id) =>
      'localist.remote.peer.${sha256.convert(utf8.encode('$server\n$id'))}';
  Future<String?> read(String server, String id) =>
      _storage.read(key: _key(server, id));
  Future<void> write(String server, String id, String password) {
    if (password.length > 128 ||
        password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid peer password.');
    }
    return password.isEmpty
        ? _storage.delete(key: _key(server, id))
        : _storage.write(key: _key(server, id), value: password);
  }
}
