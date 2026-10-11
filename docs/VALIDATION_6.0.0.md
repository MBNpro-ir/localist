# Localist 6.0.0 validation

Version: `6.0.0+62`. Tested on Windows 11 and a headless Android 15 API 35
x86_64 emulator (`localist-api35-qa`). The installed official Windows client
was not replaced, reconfigured, stopped or used as a fallback engine.

## Server configuration and actual interoperability

The supplied export and official-client screenshot specify ID server and Relay
server `81.30.108.248`, the supplied public key, and an **empty API server**.
Localist uses that configuration. Upstream's optional sysinfo/heartbeat HTTP
requests can infer 21114; their failure is not evidence that session protocols
are unavailable. No server configuration was changed during this validation.

- Localist Windows → official RustDesk Android 1.5.0: authenticated file session,
  real directory listing and a completed 46-byte upload. SHA256 at both endpoints:
  `b90fc55faf295436e1ee67444109bcb4dc0ddfba155a6efcebd644f3b2705d0a`.
- Official Android → Localist Windows: authenticated remote desktop session;
  the Android client rendered the actual Windows desktop. Only the session and
  incoming connection manager were visible; the engine Home remained hidden.
- Localist Windows → Localist Android: native `connection_ready`, `peer_info`,
  `file_dir`, `job_progress` and `job_done`. Upload to the app workspace completed.
  The new completion publisher copied that file to
  `Download/Localist/localist-engine-qa_bd676f99/localist-engine-qa.txt`; its
  SHA256 matched the source above. Publication uses the final native rename,
  not a progress percentage or a partially written file.
- Upload directly to an arbitrary Android public path was rejected by the
  upstream scoped-storage validator. This remains deliberate. The publication
  bridge does not grant peers unrestricted public-storage access.

Temporary credentials were used only for QA and are not stored in this report,
source control, native status files or profile settings.

## Automated checks

- Flutter analyzer: no issues.
- Flutter tests on Windows: 63 passed, including native FFI version/translation, protocol
  settings, transfer acknowledgement, browser transfer, gallery/filtering,
  responsive Stream, the shared light/dark remote palette and live palette
  updates followed by a brightness switch in an already open remote window.
- Native IPC regression test passed for matching sibling executables and
  rejection of different names, different directories, changed contents and
  the service channel.
- Runtime/source verification: 25 pinned files; bridge exports: 317, none missing.
- Debug builds use the real `lib/main.dart`, not the ignored QA probe target.
- Windows Debug and Release and Android Debug plus split Release APKs
  (ARM32, ARM64 and x86_64) built successfully. All four Android packages passed
  embedded engine/JNI verification.
- Version 6 Welcome was inspected on Windows and Android API 35. The emulator
  granted camera, microphone and nearby-device requests; the remaining optional
  feature tiles were visible, and entry worked without granting all of them.
- Windows Stream's Web player and Settings were inspected in light/dark mode.

## Regression surface

- Native `src/ipc/auth.rs`: permits only the same-user/session, same-directory,
  identical Localist executable pair on the main LocalistRemote pipe. Arbitrary
  executable peers and service-pipe exceptions remain rejected.
- Native `src/core_main.rs` and `src/platform/windows.rs`: percent-encode
  session passwords and avoid logging URI/credential contents.
- Runner/embedded bootstrap: hides the host's first frame, keeps its link
  listener alive and waits for IPC before applying settings. Session and
  approval windows preserve the native implementation.
- Embedded `MyTheme` and palette-dependent controls: replace fixed accent
  colors with Localist's shared light/dark palette. Window/isolate initialization
  starts the palette reader; one-second refresh also covers open sessions.
  Chat bubbles, file-transfer selection/progress, floating input and toolbar
  controls use matching foreground/background colors. Remote video pixels,
  terminal content, QR contrast and semantic warning colors retain their purpose.
- Welcome/native status bridge: enumerates feature permissions, reads OS state
  and requests access only through the relevant button/runtime dialog. Optional
  remote, camera, microphone, root and administrator access do not block entry.
- Android application/publisher: observes completed engine download renames
  inside canonical app storage, publishes through MediaStore, and records
  received history. The native peer-path restriction is unchanged.
- Existing Quick Send/web/history/startup paths: receipt acknowledgements,
  partial-file commits, category filters, previews, batch sounds and per-file
  Downloads folders address the reported behavior. Their existing automated
  checks pass; unrelated user changes were preserved.

## Device and feature limits

Emulator observations are not physical Android/iPhone/TV/console acceptance.
Windows hardware-codec/VRAM acceleration is not compiled into this DLL; it uses
software codecs. Android has the pinned upstream ABIs. AirPlay, Chromecast and
media transcoding are not implemented. DLNA/browser playback depends on the
receiver's supported media formats. Hosted Wi-Fi requires adapter/driver AP
support; Miracast requires compatible hardware. Driver/service installation,
unattended elevated control, 2FA, printing, camera/audio, terminal and tunnels
need their own device acceptance tests; not every upstream feature has been
exercised. Android screen capture requires fresh OS consent for each session.
