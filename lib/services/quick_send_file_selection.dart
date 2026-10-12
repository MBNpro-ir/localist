import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_bridge_service.dart';

/// Expands dropped folders while preserving their relative paths for transfer.
/// Bounds the whole selection, including files selected before this drop.
Future<List<QuickSendSharedFile>> expandQuickSendSharedFiles(
  Iterable<QuickSendSharedFile> files, {
  Iterable<String> existingPaths = const [],
  int maxFiles = 5000,
}) async {
  String pathKey(String path) {
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  final seen = {for (final path in existingPaths) pathKey(path)};
  final expanded = <QuickSendSharedFile>[];
  void addFile(String path, String name) {
    if (seen.length < maxFiles && seen.add(pathKey(path))) {
      expanded.add(QuickSendSharedFile(path: path, name: name));
    }
  }

  for (final shared in files) {
    if (seen.length >= maxFiles) break;
    final path = shared.path.trim();
    if (path.isEmpty) continue;
    final name = shared.name.trim().isEmpty
        ? p.basename(p.normalize(path))
        : shared.name.trim();
    if (await File(path).exists()) {
      addFile(path, name);
      continue;
    }
    final directory = Directory(path);
    if (!await directory.exists()) continue;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: path)
            .replaceAll('\\', '/');
        addFile(entity.path, p.posix.join(name, relative));
        if (seen.length >= maxFiles) break;
      }
    } on FileSystemException {
      // Keep readable items when one folder cannot be enumerated.
    }
  }
  return expanded;
}
