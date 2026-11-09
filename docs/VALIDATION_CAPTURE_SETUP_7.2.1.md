# Camera reception and Setup-only Windows delivery — 7.2.1+76

Validated locally on 2026-11-09. Logs and private pairing credentials are under
`.runlogs/capture-setup-fix` and excluded from commits. The user's preexisting
untracked `site/` remains untouched.

## Reported evidence and causes

The attached 7.2.0 log is from Windows 10 build 19045. It contains bootstrap,
service and network polling but no capture events; it cannot identify the exact
failure on that PC. Capture transitions, peer errors, output startup and native
orientation are now exported without pairing credentials.

A repeated real Windows receive test reproduced an important failure: incoming
RTP reported hundreds of decoded frames while renderer dimensions stayed 0x0.
The Windows WebRTC observer populated remote streams in legacy OnAddStream but
not Unified Plan OnTrack. Localist now registers each OnTrack stream before
notifying Dart. The patched observer is generated from the pinned 1.6.3 source;
the pub cache is not modified. Source-hash drift stops the build for review.

An audio-first stream can also gain video while output synchronization is in
flight. Sync changes are coalesced, video-track identity is checked, and native
renderer rebinding is awaited. The local preview uses ordered binding during
background/resume. Capture cancellation and frame-error guards remain active.

Android rotation uses actual capturer frame metadata plus screen/physical pose
difference. It no longer assumes raw Camera2 SENSOR_ORIENTATION describes pixels
already transformed by Camera1/Camera2/vendor capturers. Landscape/Portrait lock
image orientation and dimensions; the previous portrait letterboxing is removed.

## Distribution and installation

Windows releases publish Setup and its checksum, with no portable ZIP. Setup
registers four webcam identities for both x86/x64 consumers and local-subnet
inbound access scoped to the installed executable, including USB Public profiles.
No system-wide firewall policy is disabled. Camera registration failure rolls
back previous camera registrations; Setup reports an integration error.
Only the current version's camera DLLs are included in a new Setup payload.
Uninstall removes this installation's startup task, webcam entries and LAN rule.

The updater selects the version-matched Setup, validates size/SHA-256 and package
header, then invokes its embedded installer after confirmed normal application
exit. Setup retains the installation/uninstall manifest. ZIP-only updaters through
7.2.0 need one manual Setup upgrade; subsequent updates use Setup automatically.

Camera sharing URLs and related browser/copy-link instructions are removed from
the Camera & Mic UI. Automatic LAN pairing and private signaling remain internal.
The separate Stream media-web feature is unchanged.

## Verification

- **201 Flutter tests passed; analyzer reports No issues found.** New regressions
  cover video arriving during output synchronization, Setup asset selection and
  package mismatch/corruption, and redaction of pairing credentials.
- Android instrumentation checks asymmetric YUV pixel landmarks for front/back
  metadata, all quarter turns, locked modes across screen rotations, buffer
  ownership and contained allocation failure. Lifecycle and capabilities pass.
- A compiled Android sender supplied real WebRTC camera/audio to four independent
  instances of the Windows receive service in a hidden, isolated native host.
  All receivers completed an explicit stop/reconnect cycle. Inbound RTP counters
  confirmed decoded video and received audio; all four reported nonzero preview
  dimensions and enabled virtual-camera output.
- Four simultaneous real DirectShow consumers each captured six nonblank frames
  from Localist QA Cameras 1–4. The installed libobs DirectShow source then
  captured eight real frames per camera at 640x480, 1280x720, 480x640 and 1920x1080.
  These consumers used the actual received media, not the synthetic producer.
- A first simple pipeline run passed, but adding forced reconnect exposed the
  zero-size renderer failure. The repeated failure was not treated as success;
  the native OnTrack fix was added and the full reconnect/consumer run passed.
- Real isolated Setup install, headless update, repair, native updater parent
  wait/Setup handoff/relaunch, downgrade rejection and uninstall all passed.
  User-owned sentinel data remained intact. QA installer identity is separate.
- Normal Windows Release and normal-main Android Debug build successfully.
  Bundle check confirms identical main/helper executables and eight versioned
  camera modules. All 27 remote-engine and 57 camera-source integrity checks pass.

## Limits and cleanup

The Windows receive host ran on Windows 11; the source used the API 30 Android
emulator. The user's physical phone, USB cable and Windows 10 PC were not directly
available. Machine-wide production Setup integration requires normal admin
consent; the lifecycle test uses isolated per-user QA registration. Four virtual
microphone endpoints are unchanged. No physical webcam or user's OBS settings
were used. QA camera registrations, forwarding and owned emulator are removed
at the end. The regular main APK is rebuilt after the separate QA sender.

References reviewed: WebRTC Camera2Session and Android Camera2 preview orientation:
- https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/android/src/java/org/webrtc/Camera2Session.java
- https://developer.android.com/media/camera/camera2/camera-preview
