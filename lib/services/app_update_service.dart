import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'native_bridge_service.dart';

const _localistRepoOwner = 'MBNpro-ir';
const _localistRepoName = 'localist';
const _latestReleaseApi =
    'https://api.github.com/repos/$_localistRepoOwner/$_localistRepoName/releases/latest';
const localistLatestReleaseUrl =
    'https://github.com/$_localistRepoOwner/$_localistRepoName/releases/latest';

class AppUpdateService {
  AppUpdateService({NativeBridgeService? bridge})
    : _bridge = bridge ?? NativeBridgeService.instance;

  final NativeBridgeService _bridge;

  Future<AppUpdateCheck> checkForUpdate() async {
    final current = await AppVersion.current();
    final release = await _fetchLatestRelease();
    final supportedAbis = await _bridge.getAndroidSupportedAbis();
    final androidAsset = release.pickAndroidAsset(supportedAbis);
    return AppUpdateCheck(
      current: current,
      release: release,
      androidAsset: androidAsset,
      supportedAbis: supportedAbis,
    );
  }

  Future<File> downloadAndroidUpdate(
    UpdateAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(asset.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: Uri.parse(asset.downloadUrl),
        );
      }
      final updatesDir = Directory('${Directory.systemTemp.path}/updates');
      if (!updatesDir.existsSync()) {
        updatesDir.createSync(recursive: true);
      }
      final file = File('${updatesDir.path}/${asset.name}');
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close(force: true);
    }
  }

  Future<AppRelease> _fetchLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseApi));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Localist updater');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: Uri.parse(_latestReleaseApi),
        );
      }
      final decoded = jsonDecode(body) as Map<String, Object?>;
      return AppRelease.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.current,
    required this.release,
    required this.androidAsset,
    required this.supportedAbis,
  });

  final AppVersion current;
  final AppRelease release;
  final UpdateAsset? androidAsset;
  final List<String> supportedAbis;

  bool get updateAvailable => release.version.compareTo(current) > 0;
  bool get canInstallOnThisDevice => androidAsset != null;
}

class AppRelease {
  const AppRelease({
    required this.name,
    required this.tagName,
    required this.htmlUrl,
    required this.version,
    required this.assets,
  });

  final String name;
  final String tagName;
  final String htmlUrl;
  final AppVersion version;
  final List<UpdateAsset> assets;

  factory AppRelease.fromJson(Map<String, Object?> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final name = json['name'] as String? ?? tagName;
    return AppRelease(
      name: name.isEmpty ? tagName : name,
      tagName: tagName,
      htmlUrl: json['html_url'] as String? ?? localistLatestReleaseUrl,
      version:
          AppVersion.tryParse(tagName) ??
          AppVersion.tryParse(name) ??
          AppVersion.zero,
      assets:
          (json['assets'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>()
              .map(UpdateAsset.fromJson)
              .where((asset) => asset.downloadUrl.isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  UpdateAsset? pickAndroidAsset(List<String> supportedAbis) {
    final apkAssets = assets
        .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
        .toList(growable: false);
    for (final abi in supportedAbis) {
      final token = switch (abi) {
        'arm64-v8a' => 'android-arm64-v8a',
        'armeabi-v7a' => 'android-armeabi-v7a',
        'x86_64' => 'android-x86_64',
        _ => '',
      };
      if (token.isEmpty) {
        continue;
      }
      for (final asset in apkAssets) {
        if (asset.name.toLowerCase().contains(token)) {
          return asset;
        }
      }
    }
    return null;
  }
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;

  factory UpdateAsset.fromJson(Map<String, Object?> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
    );
  }
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion({required this.parts, required this.build});

  final List<int> parts;
  final int build;

  static const zero = AppVersion(parts: [0, 0, 0], build: 0);

  static Future<AppVersion> current() async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    for (final line in pubspec.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('version:')) {
        return tryParse(trimmed.substring('version:'.length).trim()) ?? zero;
      }
    }
    return zero;
  }

  static AppVersion? tryParse(String value) {
    final match = RegExp(
      r'v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+(\d+))?',
    ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    return AppVersion(
      parts: [
        int.parse(match.group(1)!),
        int.tryParse(match.group(2) ?? '') ?? 0,
        int.tryParse(match.group(3) ?? '') ?? 0,
      ],
      build: int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (var index = 0; index < 3; index++) {
      final comparison = parts[index].compareTo(other.parts[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return build.compareTo(other.build);
  }

  @override
  String toString() {
    final version = parts.join('.');
    return build > 0 ? '$version+$build' : version;
  }
}
