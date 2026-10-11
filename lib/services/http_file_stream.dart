import 'dart:io';

import 'package:mime/mime.dart';

/// One byte range (RFC 9110). Multiple ranges are rejected rather than silently
/// returning different bytes; suffix ranges and zero-length files are covered.
({int start, int end})? parseFileRange(String? value, int length) {
  if (value == null) return (start: 0, end: length);
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
  if (match == null || length == 0) {
    throw const FormatException('Invalid range');
  }
  final first = match.group(1)!;
  final last = match.group(2)!;
  if (first.isEmpty) {
    final suffix = int.tryParse(last) ?? 0;
    if (suffix <= 0) throw const FormatException('Invalid suffix');
    return (start: (length - suffix).clamp(0, length), end: length);
  }
  final start = int.tryParse(first) ?? length;
  final end = last.isEmpty ? length : (int.tryParse(last) ?? -2) + 1;
  if (start >= length || end <= start) {
    throw const FormatException('Unsatisfiable range');
  }
  return (start: start, end: end.clamp(start, length));
}

Future<void> serveMediaFile(HttpRequest request, File file, String name) async {
  final response = request.response;
  if (request.method != 'GET' && request.method != 'HEAD') {
    response.statusCode = HttpStatus.methodNotAllowed;
    response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
    return;
  }
  final length = await file.length();
  final rangeValue = request.headers.value(HttpHeaders.rangeHeader);
  late final ({int start, int end}) range;
  try {
    range = parseFileRange(rangeValue, length)!;
  } on FormatException {
    response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
    return;
  }
  response.headers
    ..contentType = ContentType.parse(
      lookupMimeType(name) ?? 'application/octet-stream',
    )
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..set(
      'content-disposition',
      "inline; filename*=UTF-8''${Uri.encodeComponent(name)}",
    )
    ..set('X-Content-Type-Options', 'nosniff');
  response.contentLength = range.end - range.start;
  if (rangeValue != null) {
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${range.start}-${range.end - 1}/$length',
    );
  }
  if (request.method == 'GET' && range.end > range.start) {
    await response.addStream(file.openRead(range.start, range.end));
  }
}
