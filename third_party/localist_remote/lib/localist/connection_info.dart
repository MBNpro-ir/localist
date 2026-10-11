/// Clipboard-only connection details. Session passwords are never persisted.
class RemoteConnectionInfo {
  RemoteConnectionInfo({required String id, this.password = ''})
      : id = normalizeId(id) {
    if (!isValidId(this.id) ||
        password.length > 256 ||
        password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid connection details.');
    }
  }

  final String id;
  final String password;

  static String normalizeId(String value) {
    final trimmed = value.trim();
    return RegExp(r'^[0-9\s]+$').hasMatch(trimmed)
        ? trimmed.replaceAll(RegExp(r'\s'), '')
        : trimmed;
  }

  static bool isValidId(String value) =>
      value.length <= 200 &&
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._:-]*$').hasMatch(value);

  static String displayId(String value) {
    final id = normalizeId(value);
    if (!RegExp(r'^\d+$').hasMatch(id)) return id;
    return id
        .replaceAllMapped(
            RegExp(r'\d{1,3}(?=(\d{3})*$)'), (match) => '${match.group(0)} ')
        .trim();
  }

  String toClipboardText() => 'Localist Remote Control\n${Uri(
        scheme: 'localist',
        host: 'connect',
        queryParameters: {'v': '1', 'id': id, 'password': password},
      )}';

  /// Accept one branded share link, a labelled ID/password pair, or an ID.
  /// Reading/parsing the clipboard does not launch anything by itself.
  static RemoteConnectionInfo parse(String text) {
    if (text.length > 4096 || text.contains('\x00')) {
      throw const FormatException('Invalid connection details.');
    }
    final source = text.trim();
    final links = RegExp(r'localist://[^\s]+', caseSensitive: false)
        .allMatches(source)
        .toList();
    if (links.isNotEmpty) {
      if (links.length != 1) {
        throw const FormatException('Copy one connection at a time.');
      }
      final uri = Uri.parse(links.single.group(0)!);
      final values = uri.queryParametersAll;
      if (uri.host != 'connect' ||
          uri.path.isNotEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.fragment.isNotEmpty ||
          values['v']?.singleOrNull != '1' ||
          values['id']?.length != 1 ||
          values['password']?.length != 1 ||
          values.keys.any((key) => !['v', 'id', 'password'].contains(key))) {
        throw const FormatException('Invalid Localist connection link.');
      }
      return RemoteConnectionInfo(
          id: values['id']!.single, password: values['password']!.single);
    }
    final ids = RegExp(r'^(?:ID|شناسه|آیدی)\s*:\s*(.+)$',
            caseSensitive: false, multiLine: true)
        .allMatches(source)
        .toList();
    final passwords = RegExp(r'^(?:Password|رمز)\s*:\s*(.*)$',
            caseSensitive: false, multiLine: true)
        .allMatches(source)
        .toList();
    if (ids.length == 1 && passwords.length <= 1) {
      return RemoteConnectionInfo(
          id: ids.single.group(1)!.trim(),
          password: passwords.isEmpty ? '' : passwords.single.group(1)!.trim());
    }
    return RemoteConnectionInfo(id: source);
  }
}
