# Localist 6.0.7+69 validation

Validated locally on Windows on 2026-10-12. No Computer Use tests were performed.

## Remote Control failure and recovery

The reported settings IPC timeout was reproduced with the installed Localist
process and a retained LocalistRemote host from a different Debug directory.
The native engine log explicitly rejected the caller with `executable mismatch`.
The status file previously identified readiness without checking which bundle
owned the host. The native same-directory, identical-executable authentication
rule remains unchanged.

The new runtime validates status version, advertised path and executable
SHA-256, heartbeat and authenticated loopback ping before adopting a host.
Recovery uses a native process handle to check the actual image path, basename,
creation time, Windows session and user before terminating an obsolete host.
Recent or responsive active sessions block replacement. Status removal retains
the original host identity and will not remove a different command token's file.

Two hidden executable-level probes confirmed settings IPC readiness, a nonempty
ID and a temporary password without printing their values. Native connection
status became `status_num: 1`. The second probe replaced a live host from a
separate copied bundle with the current Debug bundle and successfully read
settings through the primary executable's native bridge. The obsolete process
exited; the replacement remained ready and registered with the configured server.

A separately compiled native guard fixture passed 11 checks under `/W4 /WX`,
including preserving unrelated images, wrong paths and processes created after
the advertised heartbeat, rejecting termination of the caller, and terminating
only the verified test host. Fixture processes were created without windows.

## Web Stream gallery

Multiple image, video and audio selections have generated indexed media routes.
Only selected files are served. Root URLs remain `http://IP:port`; individual
players preserve range/HEAD handling, native browser controls, full player
controls and gallery/previous/next navigation. DLNA uses the chosen item's
stable URL independently of which item a web viewer opens.

Real HTTP tests cover mixed selections, duplicates, Persian pages, independent
byte ranges and HEAD lengths, invalid routes/tokens, obsolete selection URLs,
unsupported methods and selection validation without discarding a live stream.

A headless Chrome check used a generated PNG and three-second H.264 MP4. It
confirmed two gallery cards, a 360px layout without horizontal overflow, decoded
image display, 125% zoom, next-item navigation, video playback, seeking to one
second, volume 0.4, playback speed 1.5, pause and return to the gallery. No script
errors occurred. Image previews load lazily and video previews load metadata
only when their cards approach the viewport; previews never autoplay.

## Local checks and builds

- Flutter analyzer: no issues.
- Full Flutter suite: 128 tests passed, including 12 host lifecycle tests.
- Windows x64 Debug build passed; the final artifact uses the normal app entry.
- Android Debug APK build passed.
- Pinned native runtime/source/dependency verification: all 25 files matched.
- Native Windows bridge export verification: 317 exports, none missing.
- Android APK inspection: native engines, C++ runtime and required JNI types
  present for `armeabi-v7a`, `arm64-v8a` and `x86_64`.

Sanitized command logs and probes are under `.runlogs/`, excluded from Git.
Existing CMake policy and Kotlin migration warnings did not fail the builds.

## Limits

These checks establish local host recovery, genuine settings IPC and browser
playback. A new real two-device remote screen session, physical iPhone/TV
playback, OS sign-in startup and Android 8–10 device behavior were not retested
in this change. The prior interoperability evidence remains documented in
`VALIDATION_6.0.0.md`; readiness is not evidence of a new remote session.
