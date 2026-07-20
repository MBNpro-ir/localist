#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "windows_native_bridge.h"

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  method_channel_ = CreateLocalistMethodChannel(
      flutter_controller_->engine()->messenger(), GetHandle());
  // Receive files dropped onto any part of the native window and forward their
  // paths to the same Quick Send import stream used by Android Sharesheet.
  ::DragAcceptFiles(GetHandle(), TRUE);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ::DragAcceptFiles(GetHandle(), FALSE);
  if (flutter_controller_) {
    method_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DROPFILES) {
    const HDROP drop = reinterpret_cast<HDROP>(wparam);
    const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    flutter::EncodableList files;
    for (UINT index = 0; index < count; ++index) {
      const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
      if (length == 0) {
        continue;
      }
      std::wstring path(length + 1, L'\0');
      ::DragQueryFileW(drop, index, path.data(), length + 1);
      path.resize(length);
      flutter::EncodableMap file;
      file[flutter::EncodableValue("path")] =
          flutter::EncodableValue(WideToUtf8(path));
      const size_t separator = path.find_last_of(L"\\/");
      file[flutter::EncodableValue("name")] = flutter::EncodableValue(
          WideToUtf8(separator == std::wstring::npos ? path
                                                       : path.substr(separator + 1)));
      files.emplace_back(file);
    }
    ::DragFinish(drop);
    if (!files.empty() && method_channel_) {
      method_channel_->InvokeMethod(
          "quickSendSharedFiles",
          std::make_unique<flutter::EncodableValue>(files));
    }
    return 0;
  }

  if (message == kLocalistApplyUpdateMessage) {
    // The updater already has a private copy of itself. Closing the window
    // terminates this process so it can atomically replace the bundle.
    ::DestroyWindow(hwnd);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
