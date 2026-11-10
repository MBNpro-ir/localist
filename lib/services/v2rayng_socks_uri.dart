import 'dart:convert';
import 'log_service.dart';

String buildV2rayNgSocksUri({
  required String host,
  required int port,
  required String name,
}) {
  LogService.instance.debug(
    'v2rayNG SOCKS URI construction requested port=$port ipv6=${host.contains(':')} labelLength=${name.length}',
  );
  final userInfo = base64.encode(utf8.encode(':')).replaceAll('=', '');
  final encodedName = Uri.encodeComponent(name);
  final uriHost = _formatUriHost(host);
  final uri = 'socks://$userInfo@$uriHost:$port#$encodedName';
  LogService.instance.debug('v2rayNG SOCKS URI constructed');
  return uri;
}

String _formatUriHost(String host) {
  if (host.contains(':') && !host.startsWith('[')) {
    return '[$host]';
  }
  return host;
}
