# Remote privilege bootstrap (local only)

The installed original RustDesk service on this computer runs automatically
as LocalSystem. Localist's administrator manifest and elevated logon task
already grant its host an administrator token, but this is distinct from the
upstream privileged portable helper used for secure desktop capture/input.

The old `--localist-host` argument stayed in RustDesk's parsed command list.
Upstream's Windows quick-support/portable-service bootstrap only runs for an
empty parsed main command. It therefore skipped the helper despite the
elevated process. Localist now launches its retained host with upstream's
`--noinstall` command, which upstream consumes before that decision. The
runner and Dart entrypoint preserve the hidden retained-host role for that
command; service children and session/approval windows retain their roles.

The existing native binary and its authenticated one-time shared-memory IPC
are reused. No UAC policy, connection authorization, passwords, 2FA or original
RustDesk service is modified. Initial Windows elevation remains necessary;
the already-elevated host automatically starts the helper without an additional
per-connection UAC request. A destination configured for manual-only approval
still follows its owner's policy. Password approval with valid credentials
already supports connections without a manual acceptance click.

## Verification

- 192 Flutter tests passed; analyzer reported no issues.
- Windows Release built; executable-pair/camera bundle verification passed.
- All 27 pinned engine/source checks passed; no native rebuild/bridge change.
- A windowless isolated probe loaded the same packaged native DLL. Its own
  unelevated entry refused the test without opening UAC.
- One explicitly announced Windows UAC approval ran both native cases:
  old command: elevated=true, systemHelperStable=false;
  upstream command: elevated=true, systemHelperStable=true.
- The SYSTEM helper was identified by its exact isolated executable path and
  Windows LocalSystem SID, and remained alive for six seconds.
- The native log also recorded `Got portable service ipc connection`, confirming
  the authenticated helper handshake, rather than merely finding a process.
- The probe stopped only its own helper; no probe processes or portable pipe
  remained. The original RustDesk service remained Running under LocalSystem.

No fresh end-to-end session through the user's other computer is claimed.
Both the receiving Localist installation and the authorized Windows bootstrap
must be present on the destination for the improved behavior there.

Logs/results: `.runlogs/remote-privilege-qa` (not committed).
No push, tag, release or Action was performed for this change.
