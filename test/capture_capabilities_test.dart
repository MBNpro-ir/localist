import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/capture_capabilities.dart';
import 'package:localist/services/live_capture_service.dart';

void main() {
  test(
    'camera modes retain hardware sizes above 1080p and their own frame rates',
    () {
      final caps = CaptureCapabilities.fromMap({
        'modes': [
          {'width': 3840, 'height': 2160, 'minFps': 15, 'maxFps': 60},
          {'width': 1920, 'height': 1440, 'minFps': 10, 'maxFps': 30},
          {'width': 3840, 'height': 2160, 'minFps': 15, 'maxFps': 30},
        ],
        'minBitrateKbps': 100,
        'maxBitrateKbps': 160000,
      });
      expect(caps.modes.length, 2);
      final high = caps.choose(width: 3840, height: 2160)!;
      expect(high.maxFps, 60);
      expect(high.frameRates, containsAll([15, 30, 60]));
      expect(caps.modes.first.frameRates, isNot(contains(60)));
      expect(caps.recommendedBitrate(high, 60), 49766);
      const LiveCaptureOptions(
        width: 3840,
        height: 2160,
        fps: 60,
        bitrateKbps: 60000,
      ).validate();
      validateCaptureControl({'width': 1920, 'height': 1440, 'bitrate': 40000});
    },
  );
  test(
    'encoder rate ranges differ by device and survive receiver serialization',
    () {
      final first = CaptureCapabilities.fromMap({
        'minBitrateKbps': 128,
        'maxBitrateKbps': 5000,
      });
      final second = CaptureCapabilities.fromMap({
        'minBitrateKbps': 64,
        'maxBitrateKbps': 160000,
      });
      const mode = CaptureMode(3840, 2160, 1, 60);
      expect(first.recommendedBitrate(mode, 60), 5000);
      expect(second.recommendedBitrate(mode, 60), greaterThan(12000));
      expect(CaptureCapabilities.fromMap(second.toJson()).maxBitrate, 160000);
    },
  );
  test(
    'missing or malformed capabilities do not invent camera modes or bitrate limits',
    () {
      final caps = CaptureCapabilities.fromMap({
        'modes': [
          null,
          {},
          {'width': 'bad'},
          {'width': 99999, 'height': 480, 'maxFps': 30},
        ],
        'minBitrateKbps': 'bad',
      });
      expect(caps.modes, isEmpty);
      expect(caps.choose(), isNull);
      expect(caps.hasBitrateRange, false);
      expect(
        CaptureCapabilities.fromMap({
          'minBitrateKbps': 100,
          'maxBitrateKbps': 20,
        }).hasBitrateRange,
        false,
      );
    },
  );
  test('capture has background, receiver controls and landscape defaults', () {
    const options = LiveCaptureOptions(
      cameraId: 'front-camera',
      microphoneId: 'built-in-mic',
    );
    expect(options.orientation, 'landscape');
    expect(options.background && options.receiverControls, true);
    expect(
      (options.constraints['video'] as Map).containsKey('facingMode'),
      false,
    );
  });
}
