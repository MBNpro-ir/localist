// User-mode IRP/lock shim for executing transport logic. Never part of the SYS.
#pragma once
#include <cstdint>
#include <cstring>
#include <mutex>
using NTSTATUS = long;
using ULONG = unsigned long;
using UCHAR = unsigned char;
using VOID = void;
using KIRQL = unsigned char;
using KSPIN_LOCK = std::mutex;
struct FILE_OBJECT { int id; };
using PFILE_OBJECT = FILE_OBJECT*;
constexpr NTSTATUS STATUS_SUCCESS = 0;
constexpr NTSTATUS STATUS_INVALID_DEVICE_REQUEST = static_cast<long>(0xc0000010);
constexpr NTSTATUS STATUS_DEVICE_BUSY = static_cast<long>(0x80000011);
constexpr unsigned char IRP_MJ_CLOSE = 2;
constexpr int IO_NO_INCREMENT = 0;
struct IO_STACK_LOCATION {
  struct { struct { unsigned long IoControlCode, InputBufferLength; } DeviceIoControl; } Parameters;
  PFILE_OBJECT FileObject;
  unsigned char MajorFunction;
};
struct IRP {
  struct { void* SystemBuffer; } AssociatedIrp;
  struct { NTSTATUS Status; uintptr_t Information; } IoStatus;
  IO_STACK_LOCATION stack;
};
using PIRP = IRP*;
inline IO_STACK_LOCATION* IoGetCurrentIrpStackLocation(PIRP irp) { return &irp->stack; }
inline void IoCompleteRequest(PIRP, int) {}
inline void KeInitializeSpinLock(KSPIN_LOCK*) {}
inline void KeAcquireSpinLock(KSPIN_LOCK* lock, KIRQL* irql) { *irql = 0; lock->lock(); }
inline void KeReleaseSpinLock(KSPIN_LOCK* lock, KIRQL) { lock->unlock(); }
inline void RtlZeroMemory(void* data, size_t bytes) { memset(data, 0, bytes); }
