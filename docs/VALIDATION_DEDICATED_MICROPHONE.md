# Dedicated microphone preproduction validation — 2026-11-09

Public version remains **7.2.1+76**. These changes are local and **not a released
microphone-enabled Setup**. The candidate driver metadata is 7.3.0.77.

## Observed results

- Flutter analyzer: no issues. All 205 Flutter tests pass, including per-peer
  track identity, four independent slots, stop/detach, missing-driver throttling,
  native rejection, driver-handle recovery and preservation of video when the
  microphone driver is missing.
- Normal Windows Release and the isolated Windows QA host compile. Bundle
  validation confirms identical main/helper executables and eight camera modules.
  Binary checks confirm the QA pipe name is absent from the production WebRTC
  plugin and present only in the QA plugin.
- Android Debug also builds. An initial Google Maven 403 was resolved with the
  user-specified local proxy; no persistent Gradle/proxy settings were changed.
- Native ABI/ring/converter probe passes 100,000 mutated packets and 20,000
  randomized ring operations checked against independent deque models. Tests
  check guard samples, wraparound, drop-oldest overflow, silence underflow and
  five sample rates. The actual transport code runs under a user-mode IRP shim:
  four threads write/read 4,000 packets with distinct contents; wrong-owner writes
  fail, malformed requests fail, close releases ownership and clears buffered PCM.
  This shim does not emulate Windows kernel IRQL/PnP/PortCls behavior.
- Four real browser WebRTC producers send simultaneous independent video/audio
  to four Windows receive sessions. Raw native audio remains nonzero while
  speaker playback volume is zero. Measured tones are220,330,440,550Hz in the
  correct slots, RMS above 23,000, and 131,520–132,480 retained samples per slot.
  All four detach/reset and reconnect successfully. Video still decodes 320x240.
  This verifies native PCM transport to QA named pipes, **not WASAPI endpoints**.
- The x64 SYS compiles against WDK 10.0.26100.6584/KMDF 1.15. Inf2Cat signability
  checks for 10_VB_X64 and 10_CO_X64 pass without errors or warnings. The unsigned
  CAB and SHA-256 member manifest are generated under
  `build/localist-virtual-audio`.
- SignTool kernel-policy preflight rejects that unsigned package with
  `No signature found`. The native installer also rejects the same unsigned
  fixture before device changes. A non-owning uninstall call preserves the
  existing driver/device state. No test-signing/security-policy changes occur.
- The isolated QA Setup passes real install, headless update, repair, native
  updater handoff/relaunch, downgrade rejection, removal and user-file
  preservation. Its separate identity skips machine-wide integration; this
  does **not** validate signed-driver installation or removal.

Evidence is under `.runlogs/localist-microphone`, excluded from source commits.
The harness closes its browser/receiver and named pipes; it does not register
production microphones or alter system playback defaults.

## Website delivery

The live `https://localist.mbnpro.ir/` serves the tested 7.2.1 Setup and official
Android assets. Setup-only downloads replace portable ZIP controls. The scoped
deployment manifest records 13 updated files and 20 unchanged files belonging to
other websites. A fresh HTTPS fetch confirms the Setup link and content-hashed
release loader. Backups and private deployment reports remain in the maintained
landing project's `outputs/localist-20261109` directory.

## Release blockers

The maintainer has no Hardware Partner Center account/EV certificate. Microsoft's
required production driver signing is not available. Actual driver load,
restart/update/removal, HLK/Driver Verifier, four WASAPI endpoints and consumer
acceptance in OBS/Discord/TeamSpeak/browser remain unverified. Do not publish a
new Setup claiming working dedicated microphones until those requirements pass.
