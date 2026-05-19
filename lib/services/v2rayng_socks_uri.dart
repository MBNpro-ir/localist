import 'dart:convert';

String buildV2rayNgSocksUri({
  required String host,
  required int port,
  required String name,
}) {
  final userInfo = base64.encode(utf8.encode(':')).replaceAll('=', '');
  final encodedName = Uri.encodeComponent(name);
  final uriHost = _formatUriHost(host);
  return 'socks://$userInfo@$uriHost:$port#$encodedName';
}

String _formatUriHost(String host) {
  if (host.contains(':') && !host.startsWith('[')) {
    return '[$host]';
  }
  return host;
}
