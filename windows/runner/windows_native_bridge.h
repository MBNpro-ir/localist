#ifndef RUNNER_WINDOWS_NATIVE_BRIDGE_H_
#define RUNNER_WINDOWS_NATIVE_BRIDGE_H_

#include <windows.h>

#include <memory>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

constexpr UINT kLocalistApplyUpdateMessage = WM_APP + 73;

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLocalistMethodChannel(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_WINDOWS_NATIVE_BRIDGE_H_
