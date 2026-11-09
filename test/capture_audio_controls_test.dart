import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/services/capture_audio_settings.dart';
import 'package:localist/widgets/capture_audio_controls.dart';

void main() {
  for (final width in [360.0, 1100.0]) {
    testWidgets('gain and continuous audio stay visible at width $width', (
      tester,
    ) async {
      tester.view.reset();
      tester.view.physicalSize = Size(width, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var settings = const CaptureAudioSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => CaptureAudioControls(
                  settings: settings,
                  sender: true,
                  onEffects: (_) {},
                  onChanged: (value) => update(() => settings = value),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Advanced audio settings'), findsNothing);
      final automatic = tester.getTopLeft(find.text('Automatic gain')).dy;
      final continuous = tester
          .getTopLeft(find.text('Continuous audio through silence'))
          .dy;
      expect(continuous, greaterThan(automatic));
      expect(continuous - automatic, lessThan(90));
      final slider = find.byType(Slider);
      await tester.drag(slider, Offset(-width, 0));
      await tester.pumpAndSettle();
      expect(settings.gainDb, -30);
      await tester.drag(slider, Offset(width, 0));
      await tester.pumpAndSettle();
      expect(settings.gainDb, 40);
      expect(tester.takeException(), isNull);
    });
  }
}
