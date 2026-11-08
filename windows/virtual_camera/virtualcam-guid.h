#pragma once
#include <windows.h>
#include <initguid.h>
#include "camera_namespace.h"
// Independent identity: never register, replace or remove OBS's camera.
DEFINE_GUID(CLSID_OBS_VirtualVideo, 0x58bc2225 + LOCALIST_CAMERA_SLOT + LOCALIST_CAMERA_GUID_OFFSET, 0xe9d9, 0x4bb9, 0xa4, 0x60, 0x66, 0x30, 0xc8, 0x2a, 0x53, 0x01);
