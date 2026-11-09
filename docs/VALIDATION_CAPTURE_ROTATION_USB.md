# Local capture rotation and USB handshake fixes

Scope: local changes only, following 7.1.0+74. No release, tag, push or Action
is requested for this fix. The preexisting untracked `site/` is excluded.

Later update: the user subsequently authorized release 7.2.0+75. The final
rotation choices and device-specific settings are documented in
`VALIDATION_CAPTURE_DEVICE_SETTINGS.md`, which supersedes earlier UI choices.

## Changes

- Android automatic rotation now reads physical orientation through
  OrientationEventListener, independently of the display's auto-rotate lock.
  Front/back facing and camera sensor orientation determine the correct
  quarter-turn. A hysteresis boundary avoids jitter.
- Rotation is applied to the actual I420 pixels with WebRTC's native YuvHelper.
  Width/height swap only when the pixels rotate; there is no stretching and
  outgoing frames have zero residual rotation metadata. Portrait/landscape
  locks retain a consistent frame orientation. Sensor listeners and frame
  processors are removed on stop/service destruction.
- Capture WebSocket signaling explicitly bypasses HTTP proxies and owns a
  bounded-lifetime HTTP client. Handshake errors retain the HTTP status while
  omitting the pairing key from diagnostic messages.
- The hub temporarily avoids failed routes and tries another advertised route
  for the same device. Repeated advertisements and cooldown expiration do not
  tear down a healthy fallback session. USB remains preferred for a new
  connection. Windows adapter descriptions such as Remote NDIS Compatible
  Device are recognized as USB tethering.
- A stalled media handshake is retired after 15 seconds so it can be retried.
  Old socket callbacks cannot stop a replacement session. A socket arriving
  after cancellation is closed instead of resurrecting the session.

## Verification

- Flutter suite: **190 tests passed**; analyzer: **No issues found**.
- Regression servers returned actual HTTP 404 and 501 on the preferred route;
  the hub reconnected through the working route and repeated advertisements
  did not produce reconnect loops. Cooldown expiry preserved that connection.
- An actual HTTP proxy rejected WebSocket requests with 501. The corrected
  capture client connected directly to the local server without using it.
- Android Debug x86_64 and Windows Release x64 builds succeeded. The Windows
  bundle verifier confirmed the executable pair and all camera modules.
- Android device-side instrumentation used asymmetric luma/chroma pixels to
  check rotations 0/90/180/270, front/back sensor direction, orientation locks,
  timestamps, zero rotation metadata and source-buffer ownership. Result:
  `LOCALIST_CAPTURE_ROTATION_OK`.
- A real Android camera/microphone stream reached the headless Chrome receiver
  while the emulator's display was locked in portrait. Changing accelerometer
  values produced 480x640 portrait and 640x480 landscape in both directions.
  Portrait and landscape locks remained fixed while the physical sensor
  changed. Audio/video RTP packets continued arriving.
- Four simultaneous WebRTC receivers still received video/audio; stopping one
  left the other three connected.

The Android tests used the existing isolated API 30 emulator. The physical
phone/cable configuration reporting the problem is not connected to this
workspace, so a physical USB acceptance test is **not claimed**. HTTP error
reproduction verifies the corrected failure paths, not the exact origin of
every error on that phone. Cable networking still requires USB tethering.

Local logs: `.runlogs/capture-rotation-usb-fix`; no private logs are committed.

Commands:

```text
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
flutter build apk --debug --target-platform android-x64 --no-pub
adb -s emulator-5560 shell am instrument -w -e captureRotation true com.prs.localist.test/com.prs.localist.NotificationRegressionRunner
node tools/test_capture_physical_rotation.cjs
node tools/test_capture_multi_runtime.cjs
python tools/verify_windows_bundle.py build/windows-multicapture/x64/runner/Release
```

The VM test helpers accept `LOCALIST_CAPTURE_QA_ROOT` for isolated output and
attach logs. The physical-rotation test restores the emulator's previous
sensor and display settings and stops capture in its cleanup.
