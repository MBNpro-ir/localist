# Capture device settings and stability — 7.2.0+75

Validated locally on 2026-11-09. User authorization was updated to publish a new
release after the fixes. Private logs, endpoint tokens and the preexisting
untracked `site/` are excluded from commits.

## Final behavior

- Camera and microphone have explicit selected device IDs; no Automatic entry
  or separate Rear camera switch. Selected inputs remain visible while sharing.
- Android Camera2/WebRTC enumerates supported capture formats. Windows uses
  DirectShow IAMStreamConfig on the selected device. No fixed four-resolution
  list is presented as hardware capability. Presets select among actual modes.
- Android encoder ranges are queried for the requested size/FPS across usable
  H.264/VP8/VP9/AV1 platform encoders; the UI uses their usable intersection.
  These are encoder capability limits, not a guarantee of actual network rate
  or of a particular codec being negotiated. Windows drivers without encoder
  rate bounds use a clearly labeled target-rate input, not fabricated limits.
- The selected mode and bitrate bounds reach each receiver and its independent
  OBS Configure Video control bus. The control bus namespace is versioned to
  avoid mixing incompatible structures with a running older application.
- Background sharing and paired receiver controls are enabled at capture
  startup. Automatic reception is enabled on hub startup, including migration
  from an old saved off state. Per-device enable/video/audio controls remain.
- Latest user clarification supersedes the earlier request to remove rotation:
  retain Automatic, Portrait and Landscape; default Landscape. Automatic rotates
  physical pixels and both preview/output follow their actual dimensions.
  Locked modes keep a fixed canvas while fitting upright content without
  stretching. The display's own orientation lock is independent.
- Android Input permission action is hidden when the live input model reports
  permission; grant/revocation updates are observed immediately.

## Crash causes fixed

1. Reproduced Android RemoteServiceException: stopping a foreground-service
   startup before startForeground completed could trigger Android's delayed
   fatal deadline. Stop now acknowledges completed service destruction; a
   pending startup enters foreground before its queued stop is completed.
2. A previous service's onDestroy callback could stop a new capture. Intentional
   stops do not emit that late callback, and restart waits for destruction.
3. Compiled stress reproduced capture revival after simultaneous start/stop.
   Removed the unconditional initial await and added generation checks across
   asynchronous capture acquisition and server startup.
4. Capture reconfiguration/switch operations are serialized before asynchronous
   capability queries. Old socket/session callbacks cannot affect replacements.
5. Frame processing catches Java runtime/allocation failures, releases temporary
   frame references and asks the owner to stop with an actionable error.
   This does not claim recovery from arbitrary native driver faults or every
   OEM-specific crash.

## Evidence

- `flutter test --no-pub --reporter expanded`: **197 passing tests**.
- `flutter analyze --no-pub`: **No issues found**.
- Layout checks: English/Persian, desktop/mobile and larger text. No obsolete
  input/background/receiver switches. 4K-capable fixture uses 3840x2160 and a
  bitrate above the old fixed 12000 kbps cap.
- Android capability instrumentation: actual camera formats included 160x120,
  176x144, 320x240, 640x480, 1280x720 and 1856x1392 on the emulator; reported
  encoder range 1–20000 kbps. No claim that these are another phone's limits.
- Device-side rotation instrumentation checks asymmetric Y/U/V pixels, all
  quarter-turns, front/back orientation, fixed canvases and source references.
  Injected allocation failure invokes one error callback without escaping.
- Device-side service test: five rapid start/stop cycles plus stop during
  startup, then six seconds past Android's foreground deadline; no crash.
- Compiled acceptance app (`test/capture_runtime_app.dart`): eight actual
  camera+microphone sessions with local RTC preview, orientation changes,
  reconfiguration and competing control requests; five cancelled starts.
  Result `ok=true`, `busy=false`, `active=false`, zero Flutter errors.
- Real Android WebRTC sender and Chrome receiver: Automatic portrait/landscape
  changed both local RTC preview and remote decoded dimensions together.
  Landscape/Portrait locks remained fixed across physical sensor changes.
  Remote changes to a supported 1280x720 mode kept video flowing.
- Native Windows capability probe enumerated 35 advertised QA DirectShow modes
  and found 1920x1080 with valid FPS. No user camera was opened for this test.
- OBS/libobs acceptance: four isolated QA cameras, four independent native
  configuration buses including 4K sender mode/rate metadata, and actual
  frames at four output formats; QA registrations removed in cleanup.
- Native remote privilege acceptance is recorded separately in
  `VALIDATION_REMOTE_PRIVILEGE.md` (same packaged native engine).

Logs are local under `.runlogs/capture-device-capabilities`. Android checks use
the existing API 30 AVD. Physical USB/phone/OEM acceptance remains outstanding.
The ordinary Localist APK is rebuilt after the separate QA entrypoint so the
test application is never a release artifact.
