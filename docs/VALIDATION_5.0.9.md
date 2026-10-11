# Localist 5.0.9+59 — development validation

This is a local debug build, not a published release. The requested full embedded
RustDesk implementation is **not complete**. This report distinguishes automated
checks from device acceptance.

## Request coverage

| Request | Implemented behavior | Evidence / remaining acceptance |
|---|---|---|
| 1. Windows startup | `asInvoker`, absolute Flutter data path, quoted Run command with `--startup`, silent duplicate startup, clean Windows shutdown marker, on-demand elevation handoff | Debug build launched from `C:\Windows\System32` with `--startup`; visible responding Localist window. Duplicate invocation exited 0 without affecting it. Actual sign-in and UAC handoff still need testing. |
| 2. Multi-device browser transfers | Named browser tabs, peer credentials, host/native-app/web destinations, relay inboxes, multiple files, receive confirmation and cancellation | Real local HTTP/socket test: Alice/Bob/Charlie, two-file relay, inbox privacy, exact bytes and receipts. No real iPhone test yet. |
| 3. Stream | HTTP Range/HEAD, audio/video/image browser player, QR/local URLs, an open local web port, browser play/pause/seek/volume/speed/fullscreen/PiP controls, SSDP DLNA AVTransport Play/Pause/Stop, OS screen-mirroring entry point | Exact HTTP 206/HEAD tests, player HTML-control tests and media metadata tests. Real TV/console/Miracast acceptance pending. No AirPlay, Chromecast or transcoding. |
| 4. RustDesk | Remote page/settings in all Windows/Android builds; bundled verified 1.5.0 Windows portable engine, ID/IP connections, session modes, recents, relay/password and selected engine permissions | Windows no longer requires a separate RustDesk installation, but the session UI is still a separate bundled engine window. Full Android native engine/capture-service port remains pending. |
| 5. Windows network fallback | Hosted WLAN soft AP creation with random credentials and stop handle; usable local-adapter filtering | Windows native compilation, adapter-filter test. AP support required. No physical hotspot/connectivity/DHCP test performed. Unsupported adapters produce an explanation and alternatives. |
| 6. Progress/time/bytes | Stream backpressure, periodic byte/rate reporting, stable start time, progress below 100% until committed/acknowledged, partial files and session timeout cleanup | Native socket batch test preserves old file on failed upload; exact browser receipt and range-byte tests. Browser receipt confirms bytes in the browser, not persistent disk saving. |
| 7. Android navigation | Inactive icons, active label, minimum 48px targets, horizontal fallback for very narrow displays | Five-destination Persian RTL test at large text size and 320px width. |
| 8. History | Photo gallery, native video thumbnails, categories, search, date/status filters, size/name/date/device sorting, date-grouped list, open/resend actions | Filter/sort tests and narrow gallery widget test. Actual Windows/Android video thumbnail extraction and real file opening need device tests. History clearing retains files. |
| 9. Android destination | Default `Download/Localist/<category>/<file-stem>/<safe-file-path>`; custom paths preserved | Code and sanitization checks; Android storage-permission and real filesystem acceptance pending. Existing received files are not moved. |
| 10. Receive sounds | One completion signal per successful native/browser batch | Two-file native/browser tests confirm one signal. A failed/incomplete batch does not sound complete. |
| 11. Older Windows chrome | Opaque toolbar/sidebar surfaces and explicit text/icon colors | Native compilation and existing widget tests. No old-GPU system tested; a separate graphics-driver fault may still need logs. |

## Completed checks

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **57 tests passed**.
- `flutter build windows --debug --no-pub`: succeeded.
- Running Windows debug executable: `build/windows/x64/runner/Debug/Localist.exe`,
  product version **5.0.9+59**, responding window named **Localist**.
- Sign-in-style invocation used an unrelated working directory and `--startup`.
  Second `--startup` invocation exited successfully; original window stayed alive.
- Debug boot/startup logs generated beside the executable. No native crash was
  observed in this launch. Windows VPN and administrator operations were not run.
- Android debug build succeeded with the requested proxy and Flutter mirror:
  `build/app/outputs/flutter-apk/app-debug.apk` (104,191,444 bytes). This
  verifies the Localist Android app; it does not verify the pending embedded
  RustDesk native engine.

Build downloads use the requested proxy `127.0.0.1:10808`. Google Maven returned
404 and Flutter's Google Storage returned 403 in this environment. The build uses
the project's Google Maven fallback plus a local Gradle init script for Flutter's
included build, and the Flutter China storage mirror. No proxy setting was added
to the app or user-wide Gradle configuration.

## Manual test sequence

1. Test Windows launch after sign-out/sign-in using **App behavior → Start with
   Windows**. In debug builds this preference is not silently registered on boot.
2. Join two iPhones/browser devices to the same router or supported host hotspot.
   Open the host QR on both, name the devices, send a multi-file batch A → B,
   download from B's inbox, then repeat B → A and web ↔ native Android.
3. Try a large file, slow connection and cancellation. Check byte counts, the
   pending/complete states, elapsed time, failed retry and one receive sound.
   Safari buffers the download for its save UI; very large files are limited by
   device/browser memory. Relay storage is bounded and cleared on server stop.
4. On Android grant storage access and verify photos/videos/music/documents below
   **Download/Localist**. Open history, apply filters/sorts, open and resend files.
5. In Stream test MP4 H.264/AAC, an audio file and a photo in a destination
   browser. Test seeking, DLNA discovery/controls and the OS mirroring panel on
   compatible hardware. Unsupported codecs should be tested explicitly.
6. Remote is experimental. Check installed RustDesk detection, then use an
   authorized test peer for a session. Engine settings changes can request UAC.
   Full Remote feature parity is an outstanding implementation project.

## Primary research sources

- [RustDesk source](https://github.com/rustdesk/rustdesk), including Cargo/native
  build, Flutter bridge/deep links and hbb_common configuration defaults.
- [RustDesk 1.5.0 release](https://github.com/rustdesk/rustdesk/releases/tag/1.5.0).
- [Microsoft media casting](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/media-casting).
- [Microsoft Hosted Network](https://learn.microsoft.com/en-us/windows/win32/nativewifi/about-the-wireless-hosted-network).
- [WlanHostedNetworkStartUsing](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlanhostednetworkstartusing).

Further RustDesk integration requirements are tracked in
[RUSTDESK_INTEGRATION.md](RUSTDESK_INTEGRATION.md).
