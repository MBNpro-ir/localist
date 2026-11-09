// Localist's kernel transport; reference miniports remain pinned separately.
#ifdef LOCALIST_AUDIO_TRANSPORT_QA
#include "../../tools/virtual_audio_kernel_shim.h"
#else
#include <ntddk.h>
#endif
#include "audio_protocol.h"
#include "pcm_ring.h"

static LocalistPcmRing rings[LOCALIST_AUDIO_SLOTS];
static KSPIN_LOCK locks[LOCALIST_AUDIO_SLOTS];
static PFILE_OBJECT writers[LOCALIST_AUDIO_SLOTS]{};
extern "C" NTSTATUS UserPcmBuffer_Init(ULONG) {
  for (ULONG slot=0; slot<LOCALIST_AUDIO_SLOTS; ++slot) { KeInitializeSpinLock(&locks[slot]); rings[slot].Clear(); }
  return STATUS_SUCCESS;
}
extern "C" VOID UserPcmBuffer_Term() {}
extern "C" VOID LocalistClearAudio(ULONG slot) {
  if (slot>=LOCALIST_AUDIO_SLOTS) return;
  KIRQL irql; KeAcquireSpinLock(&locks[slot],&irql); rings[slot].Clear(); KeReleaseSpinLock(&locks[slot],irql);
}
extern "C" ULONG LocalistReadAudio(ULONG slot, UCHAR* target, ULONG bytes) {
  if (slot>=LOCALIST_AUDIO_SLOTS || (bytes % sizeof(int16_t))) { RtlZeroMemory(target,bytes); return 0; }
  KIRQL irql; KeAcquireSpinLock(&locks[slot],&irql);
  const auto frames=rings[slot].Pull(reinterpret_cast<int16_t*>(target),bytes/sizeof(int16_t));
  KeReleaseSpinLock(&locks[slot],irql);
  return static_cast<ULONG>(frames*sizeof(int16_t));
}
extern "C" NTSTATUS LocalistAudioRequest(PIRP irp) {
  auto stack=IoGetCurrentIrpStackLocation(irp);
  NTSTATUS result=STATUS_INVALID_DEVICE_REQUEST;
  if (stack->Parameters.DeviceIoControl.IoControlCode==LOCALIST_AUDIO_WRITE_IOCTL &&
      LocalistValidAudioPacket(irp->AssociatedIrp.SystemBuffer, stack->Parameters.DeviceIoControl.InputBufferLength)) {
    const auto packet=static_cast<const LocalistAudioPacket*>(irp->AssociatedIrp.SystemBuffer);
    const ULONG slot=packet->header.slot;
    KIRQL irql; KeAcquireSpinLock(&locks[slot],&irql);
    if (writers[slot] && writers[slot]!=stack->FileObject) result=STATUS_DEVICE_BUSY;
    else {
      writers[slot]=stack->FileObject;
      if (packet->header.flags==LOCALIST_AUDIO_RESET) { rings[slot].Clear(); writers[slot]=nullptr; }
      else rings[slot].Push(packet->samples,packet->header.frames);
      result=STATUS_SUCCESS;
    }
    KeReleaseSpinLock(&locks[slot],irql);
  }
  irp->IoStatus.Status=result; irp->IoStatus.Information=0;
  IoCompleteRequest(irp,IO_NO_INCREMENT); return result;
}
extern "C" NTSTATUS LocalistAudioOpenClose(PIRP irp) {
  auto stack=IoGetCurrentIrpStackLocation(irp);
  if (stack->MajorFunction==IRP_MJ_CLOSE) {
    for (ULONG slot=0;slot<LOCALIST_AUDIO_SLOTS;++slot) {
      KIRQL irql; KeAcquireSpinLock(&locks[slot],&irql);
      if (writers[slot]==stack->FileObject) { rings[slot].Clear(); writers[slot]=nullptr; }
      KeReleaseSpinLock(&locks[slot],irql);
    }
  }
  irp->IoStatus.Status=STATUS_SUCCESS; irp->IoStatus.Information=0;
  IoCompleteRequest(irp,IO_NO_INCREMENT); return STATUS_SUCCESS;
}
