# Embedded Remote Control

Localist 6.0.0 packages the RustDesk 1.5.0 native engine, generated Flutter Rust
Bridge, session UI and platform services. Remote Control and its Settings section
are available in Windows and Android Debug and Release builds. Neither platform
uses an installed RustDesk client or its URL handler to launch sessions.

## Runtime layout

- Android: `RemoteActivity` runs the retained `remoteMain` Dart entry point inside
  the Localist APK. JNI engines are packaged for arm64-v8a, armeabi-v7a and x86_64,
  with the matching C++ runtime and platform TLS verifier. Capture, audio,
  accessibility input, clipboard, foreground service and boot receivers are
  included. Screen capture and accessibility still require user permission.
- Windows: the Localist runner also produces `LocalistRemote.exe`, which loads
  `librustdesk.dll` and the same Flutter assets/plugins. Native command dispatch,
  the connection manager and multi-window desktop/file/camera/terminal/tunnel
  sessions use this executable. Windows native config, IPC and service names use
  `LocalistRemote`, isolating the installed official client's identity.
- All exposed engine preferences live in Localist Settings → Remote Control and are applied by the hidden bundled host automatically. No standalone engine settings window or engine chooser is used. Server import/export controls are above the editable server fields.
  The supplied ID/relay address and public key are the initial profile; users
  can edit them. Official clients using compatible servers remain interoperable.
- Normal product branding is Localist. Original source, licenses, protocol/JNI
  identifiers and signed third-party driver names retain their attribution.

## Included features and platform limits

The upstream engine includes remote desktop, file transfer, camera viewing,
clipboard, chat, audio, session recording, device lists, LAN discovery, password
and approval policies, Windows connection manager, TCP tunnels/RDP, terminal,
virtual displays, privacy mode and printer integration. Availability follows
upstream platform support, OS permissions, drivers and server capabilities.
Features requiring upstream commercial server capabilities still require a
compatible server; bundling the engine does not supply those server services.

Windows service installation, elevated input, virtual-display and printer driver
installation are explicit upstream actions. They are not performed merely by
opening Localist. Portable interactive sessions work without installing the
official application. Driver installation, unattended access, Android capture
and every remote feature require additional device acceptance testing.

## Source and rebuilding

`third_party/localist_remote/UPSTREAM.json` pins the source, matching bridge,
native binaries and dependency checksums. `native-source.tar.gz` includes the
corresponding native source, submodules and generated Rust bridge; the vendored
Flutter/Kotlin integration and Localist runner are also in this repository.
`patches/localist-native-namespace.patch` records the native integration changes.

Use `python tools/verify_remote_runtime.py` before packaging and
`python tools/verify_remote_apk.py <apk ...>` afterwards. Rebuild the Windows DLL
with Rust 1.75.0, the pinned vcpkg baseline, libclang and
`tools/build_remote_windows.ps1`. Use short source/Cargo/vcpkg paths on Windows:
some upstream codec scripts do not support spaces and libgit2 has path limits.
The Windows DLL is built with `flutter` and uses software codecs; hardware-codec/VRAM acceleration is not compiled into this DLL. Android keeps its upstream hardware-codec ABIs. The checked-in
lockfile is used for both.

See [6.0.0 validation](VALIDATION_6.0.0.md) for actual test evidence and limits.
Upstream: [pinned source](https://github.com/rustdesk/rustdesk/tree/4411d10f450a514c01c83e4f8af7151836300abb),
[AGPL license](../third_party/localist_remote/LICENSE).


## Localist theme and first-run permissions

All embedded session and connection-manager isolates read the light/dark palette and mode published by Localist. Open windows refresh it without restarting the engine. The remote preferences do not offer a separate theme.

Welcome requests notifications, battery exemption and Downloads storage with one action. All other permissions are optional, and Welcome can be skipped. Missing access is explained and requested again at the feature that needs it. Android Settings → Permissions includes individual capture, accessibility input, file transfer, audio, clipboard and camera controls, plus system permission status. Special access uses the corresponding Android settings screen; status refreshes on return. Restricted accessibility guidance explains App info → Allow restricted settings for sideloaded APKs.

The Android listening host is separate from MediaProjection. It can receive incoming requests before capture is granted. Localist shows Accept, Decline and one-time-password sharing, then asks for capture/camera before authorizing the requested feature. Input permission remains optional for viewing. MediaProjection is not persisted. Exiting the final session route closes only the session Activity and returns to the existing Localist Activity.

Windows starts unelevated. VPN routing uses a scoped elevated worker while the original Localist process and page stay open. The upstream connection manager retains its explicit elevation action for privileged remote input. Startup registration checks and repairs both the Run entry and Windows StartupApproved state when the user enables startup.

See [6.0.3 validation](VALIDATION_6.0.3.md) for verification and remaining device acceptance checks.

Android remote uploads remain confined to the upstream app workspace. Completed `.download` renames are published through MediaStore to unique folders in `Download/Localist` and imported into the received gallery/history. Partial or rejected transfers are not published. The engine cannot enumerate arbitrary public storage.
