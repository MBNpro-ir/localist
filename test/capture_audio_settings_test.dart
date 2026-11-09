import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/capture_audio_settings.dart';
import 'package:localist/services/live_capture_service.dart';

void main() {
  test('system audio never silently starts a camera capture', () {
    expect(
      () => const LiveCaptureOptions(audioSource: 'system').validate(),
      throwsFormatException,
    );
    expect(
      () => const LiveCaptureOptions(
        audioSource: 'system',
        camera: false,
      ).validate(),
      returnsNormally,
    );
    expect(
      const LiveCaptureOptions(
        microphoneId: 'old',
      ).copyWith(clearMicrophoneId: true).microphoneId,
      isNull,
    );
  });
  test('audio preferences round trip and preset buffers stay bounded', () {
    for (final gain in [-30.0, 0.0, 40.0]) {
      expect(CaptureAudioSettings.fromMap({'audioGainDb': gain}).gainDb, gain);
    }
    for (final mode in ['low', 'medium', 'high', 'custom']) {
      final settings = CaptureAudioSettings(
        bufferMode: mode,
        minBufferMs: 20,
        maxBufferMs: 250,
        gainDb: 6,
      );
      expect(
        CaptureAudioSettings.fromMap(settings.toMap()).toMap(),
        settings.toMap(),
      );
      expect(
        settings.effectiveMinBufferMs,
        lessThanOrEqualTo(settings.effectiveMaxBufferMs),
      );
    }
    for (final invalid in <Map<String, dynamic>>[
      {'audioGainDb': double.nan},
      {'audioGainDb': 41},
      {'audioGainDb': -30.01},
      {'audioMaxBuffer': 1001},
      {'audioMinBuffer': 500},
      {'audioOutputMode': 'system-default-change'},
      {'audioBitrate': 999},
    ]) {
      expect(
        () => CaptureAudioSettings.fromMap(invalid),
        throwsFormatException,
      );
    }
  });
  test(
    'Opus quality modifies only audio and keeps existing negotiated parameters',
    () {
      const sdp =
          'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 VP8/90000\r\n';
      final actual = configureCaptureAudioSdp(
        sdp,
        const CaptureAudioSettings(bitrateKbps: 256),
      );
      expect(actual, contains('maxaveragebitrate=256000'));
      expect(actual, contains('usedtx=0'));
      expect(actual, contains('minptime=10'));
      expect(actual, contains('useinbandfec=1'));
      expect(actual.split('m=video')[1], sdp.split('m=video')[1]);
    },
  );
  test(
    'uncompressed packets validate format, bounded sizes and frame counts',
    () {
      final bytes = Uint8List(20 + 960 * 2);
      final view = ByteData.sublistView(bytes);
      view.setUint32(0, 0x4143504c, Endian.little);
      view.setUint16(4, 1, Endian.little);
      view.setUint16(6, 1, Endian.little);
      view.setUint32(8, 48000, Endian.little);
      view.setUint32(12, 960, Endian.little);
      expect(validCapturePcm(bytes), true);
      view.setUint32(12, 1000000, Endian.little);
      expect(validCapturePcm(bytes), false);
      expect(validCapturePcm(Uint8List(100000)), false);
    },
  );
}
