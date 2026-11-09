# Windows microphone integration: verified signing research

Checked on 2026-11-09 following the request to investigate applications that
appear to create microphones without Microsoft signing.

## What was verified directly

The user's existing drivers were inspected read-only. No installer was executed,
certificate imported, boot policy changed, device renamed, or driver replaced.

| Installed product | Actual audio module | Embedded signer | SignTool `/kp` |
| --- | --- | --- | --- |
| DroidCam | `droidcamaudio.sys` | Microsoft Windows Hardware Compatibility Publisher | Passed |
| Iriun | `iriuna0.sys` | Microsoft Windows Hardware Compatibility Publisher | Passed |
| VB-Audio | `vbaudio_cable64_win10.sys` | Microsoft Windows Hardware Compatibility Publisher | Embedded-only check failed; not an unsigned-driver example |

All three audio driver catalogs also report a valid Microsoft Windows Hardware
Compatibility Publisher signature. VB-Audio's embedded-only kernel check is
recorded separately: this is not a complete catalog/member/OS-compatibility test.
Unsigned application EXEs and signed audio drivers can coexist in one product.
End users do not need a signing certificate; the driver publisher handles signing.

Evidence: `.runlogs/localist-microphone/signing-research`. The installed-audio
audit can be repeated with `tools/Inspect-WindowsAudioDrivers.ps1`; it reports
signatures and optionally runs the SDK's SignTool, without changing devices.
The audit's default PnP query includes currently reported devices only; the
DroidCam module was additionally found via its installed driver service.

## Candidate binaries were checked, not accepted by their README claims

The official VirtualDrivers/Virtual-Audio-Driver releases API returned no public
releases at this check. Its current README explicitly describes a beta/test-sign
build. Cached search snippets mentioning an older signed 25.7.14 release are not
evidence that a suitable package is presently available.

DeckX's official v1.0.17 SYS/INF/CAT were downloaded for verification only.
Its catalog passes ordinary Authenticode `/pa` verification with a SignPath
Foundation publisher. The same catalog fails kernel-policy `/kp` verification:
`Signing Cert does not chain to a Microsoft Root Cert`. The supplied SYS has a
self-signed DeckX certificate, and SYS membership verification against the
catalog fails. Its INF also targets build 22000+, not Windows 10. This exact
download is unsuitable for the requested Win10/11 public Setup. These findings
apply to the checked release, not every project using SignPath.

SynchronousAudioRouter also documents that modern Windows Secure Boot is not
supported; its latest v0.13.2 release says the driver is unsigned and requires
permanent test-signing. It is not an acceptable replacement for ordinary end users.

## User-mode and inbox alternatives

- WASAPI manages streams to/from existing endpoints. It does not provide a
  supported public factory for a new system-wide microphone.
- A DirectShow audio source is usable by DirectShow consumers, but does not
  automatically become an MMDevice/WASAPI input that Discord, browsers and
  TeamSpeak can all enumerate. This cannot satisfy the full requested feature.
- Media Foundation's software virtual-camera API creates cameras, not the
  requested general recording endpoints. Current Localist cameras already use
  their own user-mode components; this signing issue concerns the microphone.
- Remote Desktop Services AudioEndpoint interfaces are explicitly for Remote
  Desktop scenarios, not general client applications.
- The inbox USB Audio driver supports compatible USB Audio hardware. A normal
  Wi-Fi/WebRTC stream or Android USB-tether network interface is not such a USB
  Audio device. An Android app cannot generally change a phone's firmware USB
  functions to UAC on every supported phone.
- Newer ACX audio drivers still use KMDF, not UMDF. Changing from PortCls to ACX
  does not remove kernel signing requirements.

## Routes that preserve normal Windows security

1. Keep Localist's own four-channel source and obtain a production driver
   signature through the publisher's Hardware Program account or a suitable
   authorized development/signing partner. The user need not necessarily buy
   their own EV certificate, but a valid driver-signing arrangement is still
   needed. No provider, free service or approval has been obtained here.
2. Integrate an existing properly signed driver with redistribution rights.
   This can avoid requiring users to install a separate application, while
   retaining a third-party driver dependency. No checked free candidate above
   meets the current four-independent-microphone and compatibility requirements.
3. License a branded OEM driver/SDK. VAC and Thesycon officially offer custom
   names and application/installer integration. This is a commercial dependency
   needing its own agreement; it is not independently owned Localist source.

SignPath Foundation offers open-source code signing subject to eligibility and
approval. An ordinary Authenticode signature alone is not proof of Windows
kernel-policy acceptance, as the real downloaded catalog demonstrates. There is
no basis to promise free Microsoft production signing from that program.

The previous wording suggesting the maintainer must personally own EV was too
narrow. The remaining constraint is a valid trusted driver package, not a
certificate on every user's computer. No generally supported way was found to
deliver the fully independent new microphone driver unsigned on stock secure
Windows 10/11.

## Implementation correction prompted by this review

Microsoft's submission instructions require PDB symbols and one subdirectory per
driver package inside the CAB. The earlier Localist CAB omitted the PDB and used
the root directory. The build now emits a full optimized-driver PDB with a
filename-only CodeView reference; the CAB contains SYS/INF/CAT/PDB under
`LocalistAudio/`. Its actual member table is verified after MakeCab. This is an
unsigned input for an eventual approved signing workflow, not an installable
public release. It still requires external signing and actual driver acceptance
tests before release.

Validation of this correction: MSVC rebuilt SYS/PDB successfully; Inf2Cat passed
for Win10/Win11 x64 with no warnings/errors; the actual CAB contains exactly the
four required members in its subdirectory. The SYS CodeView reference points to
`LocalistAudio.pdb` without an absolute build path; the PDB MSF7 header and all
manifest hashes were checked. The unsigned package is still correctly rejected
by the production signing gate. Flutter/runtime code did not change in this
research pass, so application test suites were not repeated.

## Primary sources

- [Microsoft driver signing policy](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)
- [Hardware Program registration](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/hardware-program-register)
- [Attestation submission format, PDB and signatures](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-attestation)
- [WASAPI](https://learn.microsoft.com/en-us/windows/win32/coreaudio/wasapi)
- [User-mode endpoint question and Microsoft staff response](https://learn.microsoft.com/en-us/answers/questions/1622324/how-to-use-iaudioendpoint-and-connect-it-to-audio)
- [RDS AudioEndpoint scope](https://learn.microsoft.com/en-us/windows/win32/termserv/terminal-services-audioendpoint-api-reference)
- [MFCreateVirtualCamera scope](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera)
- [ACX uses KMDF](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/acx-audio-class-extensions-overview)
- [Inbox USB Audio 2.0](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/usb-2-0-audio-drivers)
- [VirtualDrivers source and current beta warning](https://github.com/VirtualDrivers/Virtual-Audio-Driver)
- [DeckX inspected release](https://github.com/DeckX-Development/DeckX-Virtual-Audio-Driver/releases/tag/v1.0.17)
- [SAR system requirements](https://github.com/eiz/SynchronousAudioRouter)
- [SAR v0.13.2 signing caveat](https://github.com/eiz/SynchronousAudioRouter/releases/tag/v0.13.2)
- [SignPath Foundation conditions](https://signpath.org/terms.html)
- [VAC custom driver offerings](https://vac.muzychenko.net/en/customversion.htm)
- [Thesycon TVirtAudio SDK](https://www.thesycon.de/eng/virtual_audiodriver.shtml)
