# Localist 6.0.2 validation

Version: `6.0.2+64`.

- The Windows bridge now caches its single generated RustDesk FFI instance and
  retains the initialization Future after an error. This prevents a second
  `RustdeskPlatform` constructor and the resulting RPC singleton exception.
- A fresh Windows Debug build started the embedded `LocalistRemote.exe` host;
  its status file reported `ready=true` and an active status. The page itself
  was not driven with Computer Use, as requested.
- Flutter analyzer and the targeted Remote Control/address-book/theme/clipboard
  tests pass. The full 6.0.1 suite had 78 passing tests before this two-file UI
  and bridge patch.
- The new attribution is a Flutter UI text change. Native RustDesk runtime
  files remain checksum-pinned and unchanged.

The running host still logs optional IPv6/STUN and HTTP 21114 heartbeat warnings
when those services are unavailable; session relay uses the configured native
relay path and these optional status requests do not change the FFI fix.
