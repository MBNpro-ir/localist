#pragma once
#ifndef LOCALIST_CAMERA_SLOT
#define LOCALIST_CAMERA_SLOT 0
#endif
#ifdef LOCALIST_CAMERA_TEST_IDENTITY
#define LOCALIST_CAMERA_GUID_OFFSET 0x100
#define LOCALIST_CAMERA_LABEL L"Localist QA Camera "
#else
#define LOCALIST_CAMERA_GUID_OFFSET 0
#define LOCALIST_CAMERA_LABEL L"Localist Camera "
#endif
#if LOCALIST_CAMERA_SLOT == 0
#define LOCALIST_CAMERA_NAME LOCALIST_CAMERA_LABEL L"1"
#elif LOCALIST_CAMERA_SLOT == 1
#define LOCALIST_CAMERA_NAME LOCALIST_CAMERA_LABEL L"2"
#elif LOCALIST_CAMERA_SLOT == 2
#define LOCALIST_CAMERA_NAME LOCALIST_CAMERA_LABEL L"3"
#else
#define LOCALIST_CAMERA_NAME LOCALIST_CAMERA_LABEL L"4"
#endif
#ifdef __cplusplus
extern "C" {
#endif
void localist_set_queue_slot(int slot);
#ifdef __cplusplus
}
#endif
#ifdef LOCALIST_QUEUE_IMPLEMENTATION
static __declspec(thread) int localist_slot = LOCALIST_CAMERA_SLOT;
void localist_set_queue_slot(int slot) { if (slot >= 0 && slot < 4) localist_slot = slot; }
static const wchar_t* localist_video_name(void) {
  static const wchar_t* names[] = { L"Local\\LocalistVirtualCameraVideo-v2-1", L"Local\\LocalistVirtualCameraVideo-v2-2", L"Local\\LocalistVirtualCameraVideo-v2-3", L"Local\\LocalistVirtualCameraVideo-v2-4" };
#ifdef LOCALIST_CAMERA_TEST_IDENTITY
  static const wchar_t* qa[] = {L"Local\\LocalistCameraQA-v2-1",L"Local\\LocalistCameraQA-v2-2",L"Local\\LocalistCameraQA-v2-3",L"Local\\LocalistCameraQA-v2-4"};
  return qa[localist_slot];
#else
  return names[localist_slot];
#endif
}
#define VIDEO_NAME localist_video_name()
#endif
