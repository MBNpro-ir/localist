# Localist 6.0.8 validation

Validation was run on Windows with the bundled Debug engine and on the
`localist-api35-qa` Android 15 x86_64 emulator. The emulator is a repeatable
test device; it is not physical Android 8–10, iPhone, TV, console or Miracast
acceptance.

## Automated checks

- `flutter test --no-pub`: **133 tests passed**.
- `flutter analyze --no-pub`: **No issues found**.
- `python tools/verify_remote_runtime.py`: **25 pinned engine, dependency and
  source hashes matched**.
- Windows Debug build: `build/windows/x64/runner/Debug/Localist.exe`.
- Android x86_64 Debug build: `build/app/outputs/flutter-apk/app-debug.apk`.
- Native host guard fixture: **17 checks passed** with warnings treated as
  errors.

## Remote Control and recovery

The previous failure was a watchdog race: a five-second heartbeat delay could
make the app retire a live RustDesk host while it was opening a session. The
new path checks the actual `LocalistRemote.exe` image, creation time, user and
Windows session and never terminates a verified live process during a stale
heartbeat.

With the private relay configured in the app, the following were exercised with
real service instances and native sessions:

- Windows Localist → Android Localist: authenticated session, screen image
  received at 540×1170 using VP8 (about 21–30 FPS), remote input changed the
  Android Localist theme, and the session closed normally.
- Android Localist → Windows Localist: authenticated session and a decoded
  Windows desktop image in the Android engine; Android Back returned to the
  Localist main page without a blank screen.
- Window close/reopen stress: three fresh connections each received an image,
  kept the same host PID, and completed in 5.98 s, 6.27 s and 6.15 s.
- Bidirectional 1 MiB file transfer: both directions completed and SHA-256
  matched; the Android upload was published below `Download/Localist/` in its
  per-file folder.
- Incoming Android request: the Localist consent dialog exposed Accept
  connection and Decline, one-time-password sharing and permanent-password
  guidance. Both the decline path and an authorized screen session were
  exercised.
- Printer enumeration returned five native printer names. Physical printing,
  UAC elevation, camera/audio, terminal, tunnel, RDP, 2FA and driver
  installation were not claimed as hardware acceptance tests.

## Official RustDesk interoperability

The official RustDesk Android client was configured with the same private ID and
relay server and its per-peer **Always connect via relay** option was enabled.
Using a newly generated one-time password, it connected to the Localist Windows
engine and displayed the Windows desktop. The earlier direct-path attempt that
reported port 21116 failed because the official peer was not forcing relay;
that was a client route setting, not an API-port failure.

## Android permissions

After reinstalling a Debug APK, Android correctly required fresh screen-sharing
consent. The Localist permission explanation was shown first, followed by the
Android system recording dialog; after **START**, the Windows→Android image test
passed. This is expected Android consent behavior and is not silently bypassed.

## UI and connection-card checks

The final Android launch showed the Remote Control page, one `This device`
heading, and the `Powered by RustDesk` label. The destination card uses the
`Connect` heading. Navigation transition tests cover narrow displays and avoid
the former outgoing-label overflow.

## Limits

No physical iPhone, Android 8–10 handset, television, console, Miracast or
wireless-display receiver was available. Hardware codecs, audio routing,
printer output, camera, UAC, terminal/tunnel transport and every upstream
RustDesk peripheral path still need device-specific acceptance. The embedded
engine uses the receiver's supported codecs and the configured relay/direct
network path.
