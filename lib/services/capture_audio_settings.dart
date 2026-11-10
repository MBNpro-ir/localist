// Audio settings are shared by signaling, native output and the UI.
// Values are validated before crossing a platform/network boundary.
import 'dart:typed_data';
import 'log_service.dart';

class CaptureAudioSettings {
  const CaptureAudioSettings({
    this.bitrateKbps = 96,
    this.gainDb = 0,
    this.bufferMode = 'low',
    this.minBufferMs = 0,
    this.maxBufferMs = 100,
    this.eventSync = true,
    this.continuous = true,
    this.outputMode = 'mic',
    this.outputDevice = '',
    this.focus = 'shared',
    this.lowLatency = true,
    this.uncompressed = false,
    this.outputBackend = 'audiotrack',
    this.outputEffects = false,
  });
  static const bitrates = [10, 24, 32, 64, 96, 128, 256, 450];
  final int bitrateKbps, minBufferMs, maxBufferMs;
  final double gainDb;
  final String bufferMode, outputMode, outputDevice, focus;
  final bool eventSync, continuous, lowLatency, uncompressed;
  final String outputBackend;
  final bool outputEffects;
  int get effectiveMinBufferMs => switch (bufferMode) {
    'medium' => 40,
    'high' => 100,
    'custom' => minBufferMs,
    _ => 0,
  };
  int get effectiveMaxBufferMs => switch (bufferMode) {
    'medium' => 200,
    'high' => 500,
    'custom' => maxBufferMs,
    _ => 100,
  };
  void validate() {
    if (!bitrates.contains(bitrateKbps) ||
        !gainDb.isFinite ||
        gainDb < -30 ||
        gainDb > 40 ||
        !['low', 'medium', 'high', 'custom'].contains(bufferMode) ||
        minBufferMs < 0 ||
        maxBufferMs < 10 ||
        maxBufferMs > 1000 ||
        minBufferMs > maxBufferMs ||
        !['mic', 'playback'].contains(outputMode) ||
        outputDevice.length > 512 ||
        !['exclusive', 'shared', 'calls'].contains(focus) ||
        !['audiotrack', 'opensl'].contains(outputBackend)) {
      throw const FormatException('Invalid audio settings.');
    }
  }

  Map<String, dynamic> toMap() => {
    'audioBitrate': bitrateKbps,
    'audioGainDb': gainDb,
    'audioBufferMode': bufferMode,
    'audioMinBuffer': minBufferMs,
    'audioMaxBuffer': maxBufferMs,
    'audioEventSync': eventSync,
    'audioContinuous': continuous,
    'audioOutputMode': outputMode,
    'audioOutputDevice': outputDevice,
    'audioFocus': focus,
    'audioLowLatency': lowLatency,
    'audioUncompressed': uncompressed,
    'audioOutputBackend': outputBackend,
    'audioOutputEffects': outputEffects,
  };
  Map<String, dynamic> get nativeMap => {
    ...toMap(),
    'audioMinBuffer': effectiveMinBufferMs,
    'audioMaxBuffer': effectiveMaxBufferMs,
  };
  factory CaptureAudioSettings.fromMap(Map map) {
    final settings = CaptureAudioSettings(
      bitrateKbps: (map['audioBitrate'] as num?)?.toInt() ?? 96,
      gainDb: (map['audioGainDb'] as num?)?.toDouble() ?? 0,
      bufferMode: map['audioBufferMode'] as String? ?? 'low',
      minBufferMs: (map['audioMinBuffer'] as num?)?.toInt() ?? 0,
      maxBufferMs: (map['audioMaxBuffer'] as num?)?.toInt() ?? 100,
      eventSync: map['audioEventSync'] as bool? ?? true,
      continuous: map['audioContinuous'] as bool? ?? true,
      outputMode: map['audioOutputMode'] as String? ?? 'mic',
      outputDevice: map['audioOutputDevice'] as String? ?? '',
      focus: map['audioFocus'] as String? ?? 'shared',
      lowLatency: map['audioLowLatency'] as bool? ?? true,
      uncompressed: map['audioUncompressed'] as bool? ?? false,
      outputBackend: map['audioOutputBackend'] as String? ?? 'audiotrack',
      outputEffects: map['audioOutputEffects'] as bool? ?? false,
    );
    settings.validate();
    return settings;
  }
  CaptureAudioSettings withValues(Map<String, dynamic> values) =>
      CaptureAudioSettings.fromMap({...toMap(), ...values});
}

bool validCapturePcm(Uint8List bytes) {
  if (bytes.length < 20 || bytes.length > 3860) return false;
  final view = ByteData.sublistView(bytes);
  final rate = view.getUint32(8, Endian.little);
  final frames = view.getUint32(12, Endian.little);
  return view.getUint32(0, Endian.little) == 0x4143504c &&
      view.getUint16(4, Endian.little) == 1 &&
      view.getUint16(6, Endian.little) == 1 &&
      rate >= 8000 &&
      rate <= 48000 &&
      frames > 0 &&
      frames <= rate ~/ 25 &&
      bytes.length == 20 + frames * 2;
}

/// Apply Opus encoding preferences to audio payloads only. Video and unsupported
/// codecs are preserved. This also works when a browser is the other endpoint.
String configureCaptureAudioSdp(String sdp, CaptureAudioSettings settings) {
  settings.validate();
  final lines = sdp.split('\r\n');
  final payloads = <String>[];
  for (final line in lines) {
    final match = RegExp(
      r'^a=rtpmap:(\d+) opus/48000',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) payloads.add(match[1]!);
  }
  LogService.instance.debug(
    'Capture audio: configuring SDP opusPayloads=${payloads.length} bitrate=${settings.bitrateKbps} uncompressed=${settings.uncompressed} continuous=${settings.continuous}',
  );
  for (final payload in payloads) {
    final index = lines.indexWhere(
      (line) => line.startsWith('a=fmtp:$payload '),
    );
    final values = <String, String>{};
    if (index >= 0) {
      for (final part
          in lines[index].substring('a=fmtp:$payload '.length).split(';')) {
        final at = part.indexOf('=');
        if (at > 0) {
          values[part.substring(0, at).trim()] = part.substring(at + 1).trim();
        }
      }
    }
    values['maxaveragebitrate'] =
        '${settings.uncompressed ? 10000 : settings.bitrateKbps * 1000}';
    values['usedtx'] = settings.continuous && !settings.uncompressed
        ? '0'
        : '1';
    values['useinbandfec'] = '1';
    final line =
        'a=fmtp:$payload ${values.entries.map((e) => '${e.key}=${e.value}').join(';')}';
    if (index >= 0) {
      lines[index] = line;
    } else {
      lines.insert(
        lines.indexWhere((l) => l.startsWith('a=rtpmap:$payload ')) + 1,
        line,
      );
    }
  }
  return lines.join('\r\n');
}
