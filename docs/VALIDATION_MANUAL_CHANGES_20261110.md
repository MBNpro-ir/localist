# Manual changes review — 2026-11-10

Baseline: `6d6e523` on `codex/localist-nov08-fixes` (Localist 7.3.1+2078).
Scope: review and validate the existing manual app changes, fix regressions, and
commit locally. No version bump, push, release, deployment, or installation.
The pre-existing untracked `site/` directory is excluded.

## Reviewed changes

- Persian/English UI and error messages across file transfer, VPN sharing,
  camera/audio sharing, Stream, permissions, settings, and Remote Control.
- Embedded remote-engine language initialization and synchronization with the
  app's language, including system-locale changes.
- Browser transfer and capture-viewer language selection, including explicit
  `?lang=fa` and `?lang=en` overrides.
- Debug traces for service lifecycles, discovery, transfers, media, updates,
  native calls, and remote IPC, with payload redaction and native debug gating.
- Confirmation before enabling verbose debug logging.

## Corrections made during review

1. Set the debug-toggle guard before awaiting confirmation. Rapid callbacks
   previously opened duplicate dialogs. The regression test failed before the
   correction and now verifies that only one dialog exists.
2. Native bridge exception logs now retain exception type and stack without raw
   exception messages/details. A regression test reproduced a synthetic secret
   and private-path leak before the correction and verifies their absence now.
3. Handle an empty system-locale list without reading its first element.
4. Synchronize Android's native debug flag even when the Dart debug flag already
   matches, so reinitialization can explicitly turn native logging off.

## Validation

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | Passed; no issues |
| `flutter test --no-pub` | Passed; 234 tests |
| `flutter build windows --release --no-pub` | Passed; x64 Release |
| `flutter build apk --debug --no-pub --target-platform android-arm64` | Passed; ARM64 Debug |
| `node --check tools/test_browser_transfer.cjs` | Passed |
| `node tools/test_browser_transfer.cjs` | Passed |
| `node tools/test_stream_web.cjs` | Passed |
| `git diff --check` | Passed |

The new browser harness runs the real Dart web-transfer host with synthetic
fixtures and two isolated headless Chrome clients. It verifies browser-to-browser
file relay, host downloads, exact file contents, explicit language overrides
against opposite browser locales, language switching, and 320/390/1280px layouts.
It also verifies localized capture-viewer controls and the missing-link error
without starting a camera or microphone. No page errors were recorded.

The Stream browser test verifies gallery search/filter/sort, grid/list views,
video/audio playback controls, image controls, unsupported-media recovery,
native fallback, persisted theme/language, and 320/390/768/1920px layouts.
It recorded no page errors, external requests, or CSP violations.

Windows emitted an existing plugin CMake development warning; Android emitted
plugin/Kotlin migration warnings. Both final build commands exited successfully.

## Evidence and limits

Evidence root: `.runlogs/manual-review-20261110/` (ignored by Git), including the
original manual-change snapshot, final analysis/test/build logs, and browser
results. Stream artifacts are in `.runlogs/stream-web-qa/`.

This review did not repeat physical-device, Windows 10, UAC, real remote-session,
camera/microphone hardware, or virtual-driver acceptance tests. Automated tests
and successful builds do not establish those device-specific results. The native
debug-off reinitialization edge case was reviewed in code, not on a real device.
