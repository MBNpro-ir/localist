import 'dart:math' as math;

class CaptureMode {
  const CaptureMode(this.width, this.height, this.minFps, this.maxFps);
  final int width, height, minFps, maxFps;
  String get key => '${width}x$height';
  String get label => '$width × $height';
  List<int> get frameRates => {
    minFps,
    maxFps,
    ...[
      10,
      15,
      24,
      25,
      30,
      50,
      60,
      90,
      120,
      144,
      240,
    ].where((v) => v >= minFps && v <= maxFps),
  }.toList()..sort();
  Map<String, int> toJson() => {
    'width': width,
    'height': height,
    'minFps': minFps,
    'maxFps': maxFps,
  };
}

class CaptureCapabilities {
  const CaptureCapabilities({
    this.modes = const [],
    this.minBitrate = 0,
    this.maxBitrate = 0,
    this.codecs = '',
  });
  final List<CaptureMode> modes;
  final int minBitrate, maxBitrate;
  final String codecs;
  bool get hasBitrateRange => minBitrate > 0 && maxBitrate >= minBitrate;
  factory CaptureCapabilities.fromMap(Map<dynamic, dynamic> data) {
    int number(Map row, String key, [int fallback = 0]) =>
        row[key] is num && (row[key] as num).isFinite
        ? (row[key] as num).toInt()
        : fallback;
    final modes = <String, CaptureMode>{};
    for (final row
        in data['modes'] is List
            ? (data['modes'] as List).take(256)
            : const []) {
      if (row is! Map) continue;
      final w = number(row, 'width'), h = number(row, 'height');
      final maxFps = number(row, 'maxFps');
      final minFps = number(row, 'minFps', 1).clamp(1, 240);
      if (w < 2 ||
          h < 2 ||
          w > 8192 ||
          h > 8192 ||
          w.isOdd ||
          h.isOdd ||
          maxFps < minFps) {
        continue;
      }
      final mode = CaptureMode(w, h, minFps, maxFps.clamp(minFps, 240));
      final old = modes[mode.key];
      if (old == null || old.maxFps < mode.maxFps) modes[mode.key] = mode;
    }
    final sorted = modes.values.toList()
      ..sort((a, b) => (a.width * a.height).compareTo(b.width * b.height));
    final min = number(data, 'minBitrateKbps');
    final max = number(data, 'maxBitrateKbps');
    return CaptureCapabilities(
      modes: sorted,
      minBitrate: min > 0 ? min : 0,
      maxBitrate: max >= min && max <= 1000000 ? max : 0,
      codecs: '${data['codecs'] ?? ''}',
    );
  }
  CaptureMode? choose({int width = 1280, int height = 720}) {
    for (final mode in modes) {
      if (mode.width == width && mode.height == height) return mode;
    }
    if (modes.isEmpty) return null;
    return modes.reduce(
      (a, b) =>
          (a.width * a.height - width * height).abs() <=
              (b.width * b.height - width * height).abs()
          ? a
          : b,
    );
  }

  int recommendedBitrate(CaptureMode mode, int fps) {
    final target = (mode.width * mode.height * fps * 0.10 / 1000).round();
    return hasBitrateRange
        ? target.clamp(minBitrate, maxBitrate)
        : math.max(1, target);
  }

  Map<String, dynamic> toJson() => {
    'modes': modes.map((m) => m.toJson()).toList(),
    'minBitrateKbps': minBitrate,
    'maxBitrateKbps': maxBitrate,
    'codecs': codecs,
  };
}
