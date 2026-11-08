# Localist 7.1.0+74 validation

Date: 2026-11-08. This report distinguishes tested behavior from hardware and
driver coverage that remains outstanding. Private user logs and credentials
are excluded. The preexisting untracked `site/` directory is excluded.

## Windows Remote Control

The supplied diagnostic identifies Localist 7.0.0+73 on Windows 10 Pro build
19045 and confirms the helper process launched. The embedded native IPC patch
requires Localist.exe and LocalistRemote.exe to be same-directory,
byte-identical siblings, in addition to the existing user/session checks.
The old helper icon-removal step changed PE resources and violated that rule.

The build now copies the main executable without modifying its bytes, verifies
the pair's SHA256 and hides the helper through file attributes. Runtime
preparation reports a mismatched installation directly. The existing native
IPC authorization remains intact. Ready also requires a nonempty local ID.

The final Windows Release bundle passed `tools/verify_windows_bundle.py`:
identical executables, all eight versioned x86/x64 webcam modules and required
runtime assets. `tools/verify_remote_runtime.py` passed all 27 pinned engine,
dependency and source checks. A fresh native remote session on the reported
Windows 10 computer has **not** been performed; the packaging defect is fixed,
but that machine's recovery still requires user verification.

## Automated checks and builds

- `flutter test --no-pub --reporter expanded`: **187 passed**.
- `flutter analyze --no-pub`: **No issues found**.
- Windows Release x64, version 7.1.0+74: built and verified.
- Android Debug x86_64: built, installed and run on the isolated API 30 emulator.
- Windows Setup: compiled from the final Release bundle.
- Installer lifecycle with an isolated product/registry namespace: install,
  upgrade, repair, downgrade rejection, branded uninstall and preservation of
  user files passed. Installed helper exists, is hidden and matches the app's
  SHA256. No production installation or running user app was replaced.
- ZIP packaging uses .NET ZipFile so hidden helper inclusion does not depend
  on Compress-Archive behavior.

## Four independent media receivers

`tools/test_capture_multi_runtime.cjs` connected four independent headless
Chrome WebRTC senders to the final Android APK. Each stream had one video and
one audio track, connected state, decoded 320x240 video and nonzero RTP bytes.
Stopping receiver 1 left receivers 2, 3 and 4 connected. The test uses adb
reverse and injects discovery advertisements because the emulator NAT is not
a physical multicast LAN. Actual UDP decoding/source-address handling is
covered separately by the Dart transport test.

Saved per-device enable/audio/video settings and preferred output slots persist
across app restarts. Tests cover four-device capacity, self exclusion, independent
switches, offline session retirement/reconnection, malformed advertisements,
USB priority without Wi-Fi oscillation, route refresh after launch and cable
candidate filtering. WebRTC initialization is serialized before creating
multiple renderer textures, fixing a real concurrent native initialization hang.

## Android sending, orientation and current-LAN transfer

`tools/test_capture_sender_runtime.cjs` used the emulator's camera and mic with
the actual local browser receiver. Video dimensions were:

| Mode | Received dimensions |
| --- | --- |
| Portrait lock | 480 x 640 |
| Landscape lock | 640 x 480 |
| Auto, device portrait | 480 x 640 |
| Auto, device landscape | 640 x 480 |

Both audio and video RTP bytes arrived. The new current-network iPhone web
transfer mode served the real HTTP state endpoint with managedHotspot=false
and manualHotspotRequired=false. The device's hotspot state was unchanged.
No physical iPhone test is claimed.

## Windows virtual devices and OBS

Four isolated QA camera COM identities, shared queues and control buses avoid
touching the user's registered cameras. Tests unregister their own fixtures.

- `tools/test_multi_virtual_camera.py`: four concurrent FFmpeg DirectShow
  consumers each received eight color-checked frames.
- `tools/test_multi_camera_browser.cjs`: Chrome enumerated all four devices
  and captured each simultaneously, with correct independent colors.
- `tools/test_multi_camera_obs.py`: libobs enumerated all four cameras and
  received real frames at 640x480/30, 1280x720/15, 480x640/24 and 1920x1080/15.
  Four independent native configuration buses passed.
- The per-device camera controls require sender opt-in. Receiver discovery
  itself never starts that device's own camera or microphone.

## Remaining limitations

- Four independent virtual microphone **input endpoints** are not implemented.
  Four audio streams can be received and muted independently; other Windows
  applications can use the mixed audio output through an installed virtual
  audio driver such as VB-CABLE. The original explicit driver install and
  output selection remain available.
- DirectShow, Chrome and OBS are tested. Every application and applications
  using only Media Foundation are not verified. Microsoft MFCreateVirtualCamera
  requires Windows 11 build 22000 or newer, so it cannot replace the Windows 10
  path universally.
- Physical four-phone sessions, cable/Wi-Fi failover and the original Windows
  10 system remain hardware acceptance tests. Cable transport here means USB
  tethering; charge-only USB does not create a usable IP interface.

References:

- [Microsoft virtual camera API requirements](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera)
- [Microsoft SysVAD virtual audio driver sample](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/sysvad-virtual-audio-device-driver-sample/)

Detailed local test output is grouped under `.runlogs/multicapture-qa` and is
not committed. CI retains package/signature integrity checks; Flutter tests and
analysis are run locally as requested.
