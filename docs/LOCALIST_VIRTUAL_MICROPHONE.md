# Dedicated Localist microphones — pending public signing

This integration is preproduction. Four `Localist Microphone 1–4` capture
endpoints are defined by the Localist WaveRT driver. Each received WebRTC audio
track feeds the corresponding endpoint through a versioned PCM IOCTL; no virtual
cable program, playback-output selection or speaker loopback is used. Windows
playback is muted independently of the raw received track. Video and audio output
errors remain separate from signaling errors.

## Build and trust boundary

The pinned MicyWMD reference and its Microsoft sample notices remain unchanged
under `third_party/virtual_audio`. `generate_virtual_audio.py` checks every pinned
hash and generates adaptations under `build/localist-virtual-audio/generated`.
This is a derived driver, not an independently audited production kernel engine.
The reference adaptation is MIT; Microsoft sample portions retain MS-PL.

`python tools/build_localist_audio.py <extracted WDK c directory>` builds x64
SYS/INF without installing them. This requires MSVC, SDK10.0.26100.0 and the pinned
WDK NuGet10.0.26100.6584. Run WDK `Inf2Cat /driver:<unsigned directory>
/os:10_VB_X64,10_CO_X64 /uselocaltime`, then
`python tools/prepare_audio_submission.py` to prepare an **unsigned** CAB.
The supported driver target begins at Windows10 build19041; ARM64 is not built.

No trusted public driver signature is currently available. The maintainer has
confirmed there is no Hardware Partner Center account or EV certificate.
This does not imply the maintainer must personally purchase EV: an authorized
publisher/development partner can handle an appropriate driver-signing workflow.
The required condition is a trusted driver package. See
`VIRTUAL_MICROPHONE_SIGNING_RESEARCH.md` for direct DroidCam/Iriun signature
evidence and evaluated alternatives; no suitable signing partner is configured.
Do not install this unsigned driver, enable test-signing, disable Secure Boot or
weaken signature enforcement on the user's workstation. For normal public
Windows10/11 distribution, use Microsoft's current signing/submission process.
An EV-signed submission CAB is not the final Microsoft-signed install package.

After Microsoft returns the signed package, place the exact SYS/INF/CAT in
`windows/virtual_audio/runtime` and rerun the production build. Packaging verifies
both members using SignTool `/kp /c`; runtime installation verifies signed
catalog membership and passes the package through SetupAPI policy. QA audio
transport exists only in `LOCALIST_CAPTURE_QA_RUNNER` builds and is never suitable
for distribution.

## Setup lifecycle

Setup invokes `--install-windows-integration`. It stages the trusted INF, creates
only `ROOT\LocalistAudio` when absent, updates that root device, and registers the
four webcams and app-scoped LAN rule. The driver's INF creates capture endpoints;
the app never changes the default system playback or recording device.
Windows may require a restart; code3010 is propagated to Setup's restart handling.

The owning installation path and published OEM INF are recorded in an
administrator-writable HKLM key. Removal checks that owner, removes only matching
Localist hardware IDs and uninstalls that OEM INF without forcing removal of a
package still in use. Another installation's active device is preserved.
Installation/upgrade/removal of the actual driver still require signed-driver
acceptance on supported Windows systems; compiling these paths does not validate
their runtime lifecycle.

## Required release acceptance

- Protocol/ring tests: invalid lengths/slots/formats, bounded overflow, wraparound,
  silence underflow, rate conversion and four-slot isolation.
- Real native WebRTC tests: four distinct received tones, no speaker playback
  dependence, stop/reconnect and independent slot binding.
- **Pending:** signed-driver installation, reboot, update/repair/removal and
  rollback with Driver Verifier/HLK checks in disposable Windows10/11 machines.
- **Pending:** actual WASAPI capture through all four endpoints, microphone
  enumeration and simultaneous use in OBS, browser, Discord and TeamSpeak.

Until those signed-driver checks pass, do not publish a microphone-enabled Setup
or advertise this feature as installed and working. The live website continues
to offer the tested public7.2.1 Setup.

References:
- https://learn.microsoft.com/windows-hardware/drivers/audio/developing-a-wavert-miniport-driver
- https://learn.microsoft.com/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-
- https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-attestation
- https://github.com/Mithronn/MicyWMD/tree/c5d2e11b734fea48d1ebfaf9f450e01fba6634df
- https://github.com/microsoft/Windows-driver-samples/tree/main/audio/sysvad
