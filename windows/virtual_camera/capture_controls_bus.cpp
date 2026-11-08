#include "capture_controls.h"
#include <sddl.h>
#include <cstring>
#include <mutex>
#include <vector>

namespace {
struct Shared {
  uint32_t version;
  ULONGLONG heartbeat;
  LocalistCaptureState state;
  uint32_t requested, consumed;
  char command[1024];
};
struct Bus {
  HANDLE mapping = nullptr, mutex = nullptr;
  Shared* data = nullptr;
  Bus() {
    // Only this Windows account and SYSTEM may access the session-local bus.
    // Medium integrity permits OBS to control an elevated Localist receiver.
    HANDLE token = nullptr; DWORD bytes = 0;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return;
    GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
    std::vector<BYTE> storage(bytes);
    if (!GetTokenInformation(token, TokenUser, storage.data(), bytes, &bytes)) { CloseHandle(token); return; }
    CloseHandle(token);
    LPWSTR sid = nullptr;
    if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(storage.data())->User.Sid, &sid)) return;
    const std::wstring acl = L"D:P(A;;GA;;;SY)(A;;GA;;;" + std::wstring(sid) + L")S:(ML;;NW;;;ME)";
    LocalFree(sid);
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(acl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) return;
    SECURITY_ATTRIBUTES security{sizeof(security), descriptor, FALSE};
    mutex = CreateMutexW(&security, FALSE, L"Local\\LocalistCameraControlsMutex-v1");
    mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, &security, PAGE_READWRITE, 0, sizeof(Shared), L"Local\\LocalistCameraControls-v1");
    LocalFree(descriptor);
    if (mapping && mutex) data = static_cast<Shared*>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Shared)));
  }
  ~Bus() { if (data) UnmapViewOfFile(data); if (mapping) CloseHandle(mapping); if (mutex) CloseHandle(mutex); }
};
Bus& bus() { static Bus value; return value; }
struct Lock {
  Bus& value = bus(); bool held = false;
  Lock() { if (value.data && value.mutex) { const auto status = WaitForSingleObject(value.mutex, 100); held = status == WAIT_OBJECT_0 || status == WAIT_ABANDONED; } }
  ~Lock() { if (held) ReleaseMutex(value.mutex); }
};
bool Fresh(const Shared* data) { return data->version == 1 && GetTickCount64() - data->heartbeat < 3000; }
}
bool PublishLocalistCaptureState(const LocalistCaptureState& state) {
  Lock lock; if (!lock.held) return false;
  auto* data = lock.value.data;
  if (!Fresh(data) || !state.enabled) data->consumed = data->requested;
  data->state = state; data->version = 1; data->heartbeat = GetTickCount64(); return true;
}
bool ReadLocalistCaptureState(LocalistCaptureState& state) {
  Lock lock; if (!lock.held || !Fresh(lock.value.data)) return false;
  state = lock.value.data->state; return true;
}
bool SubmitLocalistCaptureCommand(const char* json) {
  if (!json || strlen(json) >= sizeof(Shared::command)) return false;
  Lock lock; if (!lock.held) return false;
  auto* data = lock.value.data;
  if (!Fresh(data) || !data->state.enabled || data->requested != data->consumed) return false;
  strcpy_s(data->command, json); ++data->requested; return true;
}
bool TakeLocalistCaptureCommand(char* json, size_t size) {
  Lock lock; if (!lock.held) return false;
  auto* data = lock.value.data;
  if (!Fresh(data) || !data->state.enabled || data->requested == data->consumed) return false;
  if (strcpy_s(json, size, data->command)) return false;
  data->consumed = data->requested; return true;
}
