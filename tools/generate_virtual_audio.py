"""Generate Localist-owned identities and bounded transport from pinned miniports."""
from pathlib import Path
import hashlib,json,re,shutil,sys
ROOT=Path(__file__).resolve().parent.parent
reference=ROOT/'third_party/virtual_audio'
manifest=json.loads((reference/'UPSTREAM.json').read_text(encoding='utf-8'))
for name,digest in manifest['files'].items():
 if hashlib.sha256((reference/'upstream'/name).read_bytes()).hexdigest()!=digest:
  raise RuntimeError('Pinned virtual audio source changed: '+name)
license_file=reference/'MICROSOFT-SAMPLE-LICENSE'
if hashlib.sha256(license_file.read_bytes()).hexdigest()!=manifest['microsoft_sample_license']['sha256']:
 raise RuntimeError('Microsoft sample license changed')
out=Path(sys.argv[1]).resolve()
if not out.is_relative_to(ROOT/'build'):
 raise RuntimeError('Only generate under the workspace build root')
source=out/'Source'; source.mkdir(parents=True,exist_ok=True)
shutil.copytree(reference/'upstream/Source',source,dirs_exist_ok=True)
def modify(name, transform):
 p=source/name; original=p.read_text(encoding='utf-8-sig');changed=transform(original)
 if changed==original:
  raise RuntimeError('Source adaptation was not applied: '+str(name))
 p.write_text(changed,encoding='utf-8')
def adapter(s):
 s=s.replace('#include "minipairs.h"','#include "minipairs.h"\n#include <wdmsec.h>\nextern "C" NTSTATUS UserPcmBuffer_Init(ULONG);\nextern "C" VOID UserPcmBuffer_Term();\nextern "C" NTSTATUS LocalistAudioRequest(PIRP);\nextern "C" NTSTATUS LocalistAudioOpenClose(PIRP);')
 s=s.replace('MICY','LocalistAudioControl').replace('MicyAudio','LocalistAudioControl')
 start=s.index('extern "C" {\n    typedef struct _USER_PCM_RING_BUFFER')
 end=s.index('//-----------------------------------------------------------------------------\n// Functions',start)
 s=s[:start]+s[end:]
 # Use an ACL-checked control node, separate from standard audio endpoints.
 a=s.index('    ntStatus = IoCreateDevice('); b=s.index('    IF_FAILED_ACTION_JUMP(',a)
 s=s[:a]+'''    UNICODE_STRING acl;
    RtlInitUnicodeString(&acl, L"D:P(A;;GA;;;SY)(A;;GA;;;BA)");
    static const GUID controlClass = {0x8ac764ef,0x7c7c,0x470c,{0x99,0x62,0x4e,0x82,0xb8,0xa6,0x96,0xe2}};
    ntStatus = UserPcmBuffer_Init(0);
    if (!NT_SUCCESS(ntStatus)) goto Done;
    ntStatus = IoCreateDeviceSecure(DriverObject,0,&ntUnicodeString,FILE_DEVICE_UNKNOWN,
        FILE_DEVICE_SECURE_OPEN,FALSE,&acl,&controlClass,&deviceObject);
    if (NT_SUCCESS(ntStatus)) g_ControlDeviceObject = deviceObject;

'''+s[b:]
 s=s.replace('    (void)UserPcmBuffer_Init(7680 * 4);','')
 a=s.index('\nNTSTATUS\nDeviceControlHandler\n');b=s.index('//=============================================================================\n#pragma code_seg("PAGE")\nNTSTATUS\nControlDeviceCreateClose',a)
 s=s[:a]+'''
NTSTATUS DeviceControlHandler(PDEVICE_OBJECT object, PIRP irp) {
    if (object != g_ControlDeviceObject) return PcDispatchIrp(object,irp);
    return LocalistAudioRequest(irp);
}

'''+s[b:]
 a=s.index('\nNTSTATUS\nControlDeviceCreateClose\n')
 s=s[:a]+'''
NTSTATUS ControlDeviceCreateClose(PDEVICE_OBJECT object, PIRP irp) {
    if (object == g_ControlDeviceObject) return LocalistAudioOpenClose(irp);
    auto major=IoGetCurrentIrpStackLocation(irp)->MajorFunction;
    auto original=major==IRP_MJ_CREATE ? g_OriginalCreateHandler : g_OriginalCloseHandler;
    return original ? original(object,irp) : PcDispatchIrp(object,irp);
}
'''
 return s
modify(Path('Main/adapter.cpp'),adapter)
def stream(s):
 a=s.index('extern "C" {');b=s.index('//=============================================================================',a)
 s=s[:a]+'extern "C" ULONG LocalistReadAudio(ULONG slot,UCHAR* target,ULONG bytes);\nextern "C" VOID LocalistClearAudio(ULONG slot);\n\n'+s[b:]
 a=s.index('    ULONG bufferOffset = ',s.index('VOID CMiniportWaveRTStream::WriteBytes'))
 b=s.index('//=============================================================================',a)
 s=s[:a]+'''    ULONG offset = static_cast<ULONG>(m_ullLinearPosition % m_ulDmaBufferSize);
    while (ByteDisplacement) {
        const ULONG bytes=min(ByteDisplacement,m_ulDmaBufferSize-offset);
        LocalistReadAudio(m_pMiniport->LocalistSlot(),m_pDmaBuffer+offset,bytes);
        offset=(offset+bytes)%m_ulDmaBufferSize;
        ByteDisplacement-=bytes;
    }
}

'''+s[b:]
 return s.replace('UserPcmBuffer_Clear()', 'LocalistClearAudio(m_pMiniport->LocalistSlot())')
modify(Path('Main/minwavertstream.cpp'),stream)
modify(Path('Main/minwavert.h'),lambda s:s.replace('public:\n    NTSTATUS EventHandler_PinCapsChange','public:\n    ULONG LocalistSlot() const { const auto name=m_pMiniportPair->WaveName; const auto digit=name[wcslen(name)-1]; return digit>=L\'1\' && digit<=L\'4\' ? digit-L\'1\' : 0; }\n    NTSTATUS EventHandler_PinCapsChange'))
def pairs(s):
 a=s.index('static\nENDPOINT_MINIPAIR MicArray1Miniports');b=s.index('//=============================================================================',a)
 template=s[a:b]
 copies='\n'.join(template.replace('MicArray1Miniports',f'LocalistMic{i}Miniports').replace('L"TopologyMicArray1"',f'L"TopologyMicArray{i}"').replace('L"WaveMicArray1"',f'L"WaveMicArray{i}"') for i in range(1,5))
 s=s[:a]+copies+s[b:]
 s=s.replace('    &MicArray1Miniports,','\n'.join(f'    &LocalistMic{i}Miniports,' for i in range(1,5)))
 return s
modify(Path('Filters/minipairs.h'),pairs)
def formats(s):
 s=s.replace('MICARRAY_RAW_CHANNELS                   2','MICARRAY_RAW_CHANNELS                   1').replace('MICARRAY_DEVICE_MAX_CHANNELS            2','MICARRAY_DEVICE_MAX_CHANNELS            1').replace('MICARRAY_32_BITS_PER_SAMPLE_PCM         32','MICARRAY_32_BITS_PER_SAMPLE_PCM         16')
 s=s.replace('                2,\n                48000,','                1,\n                48000,').replace('48000 * 2 * 4','48000 * 2').replace('2 * 4,','2,').replace('                32,','                16,').replace('            32,','            16,').replace('KSAUDIO_SPEAKER_STEREO','KSAUDIO_SPEAKER_MONO')
 s=s.replace('STATIC_AUDIO_SIGNALPROCESSINGMODE_RAW,', 'STATIC_AUDIO_SIGNALPROCESSINGMODE_DEFAULT,')
 return s
modify(Path('Filters/micarraywavtable.h'),formats)
for item in ['driver_transport.cpp','audio_protocol.h','pcm_ring.h']:
 shutil.copyfile(ROOT/'windows/virtual_audio'/item,source/'Main'/item)
print('LOCALIST_AUDIO_SOURCE_READY',source)
