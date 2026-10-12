#include "remote_host_process.h"

#include <cstdint>
#include <vector>

namespace {
bool SameUser(HANDLE process) {
  HANDLE peer_token = nullptr;
  HANDLE own_token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &peer_token)) return false;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &own_token)) {
    CloseHandle(peer_token);
    return false;
  }
  const auto user_sid = [](HANDLE token, std::vector<BYTE>& buffer) {
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    buffer.resize(size);
    return GetTokenInformation(token, TokenUser, buffer.data(), size, &size);
  };
  std::vector<BYTE> peer, own;
  const bool same = user_sid(peer_token, peer) && user_sid(own_token, own) &&
      EqualSid(reinterpret_cast<TOKEN_USER*>(peer.data())->User.Sid,
               reinterpret_cast<TOKEN_USER*>(own.data())->User.Sid);
  CloseHandle(peer_token);
  CloseHandle(own_token);
  return same;
}

std::wstring NormalizePath(std::wstring path) {
  if (path.rfind(L"\\\\?\\", 0) == 0) path.erase(0, 4);
  for (auto& character : path) {
    if (character == L'/') character = L'\\';
  }
  return path;
}
enum class HostIdentity { match, obsolete, unknown };

HostIdentity CheckIdentity(HANDLE process, DWORD process_id, int64_t heartbeat_ms,
                           const std::wstring& expected_path) {
  wchar_t image[32768] = {};
  DWORD size = 32768;
  bool safe = QueryFullProcessImageNameW(process, 0, image, &size) != FALSE;
  if (safe) {
    const auto path = NormalizePath(std::wstring(image, size));
    const auto name = path.substr(path.find_last_of(L"\\") + 1);
    if (_wcsicmp(name.c_str(), L"LocalistRemote.exe") != 0 ||
        (!expected_path.empty() &&
         _wcsicmp(path.c_str(), NormalizePath(expected_path).c_str()) != 0)) {
      return HostIdentity::obsolete;
    }
  }
  FILETIME created{}, exited{}, kernel{}, user{};
  safe = safe && GetProcessTimes(process, &created, &exited, &kernel, &user);
  if (safe) {
    ULARGE_INTEGER ticks{};
    ticks.LowPart = created.dwLowDateTime;
    ticks.HighPart = created.dwHighDateTime;
    const auto started_ms = static_cast<int64_t>(
        (ticks.QuadPart - 116444736000000000ULL) / 10000ULL);
    if (started_ms > heartbeat_ms) {
      return HostIdentity::obsolete;
    }
  }
  DWORD peer_session = 0, own_session = 0;
  safe = safe && ProcessIdToSessionId(process_id, &peer_session) &&
      ProcessIdToSessionId(GetCurrentProcessId(), &own_session) &&
      peer_session == own_session && SameUser(process);
  return safe ? HostIdentity::match : HostIdentity::unknown;
}
}  // namespace

bool IsRemoteHostProcessRunning(DWORD process_id, int64_t heartbeat_ms,
                                const std::wstring& expected_path) {
  if (process_id == 0 || heartbeat_ms <= 0 || expected_path.empty()) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                               FALSE, process_id);
  if (!process) return false;
  const bool running = WaitForSingleObject(process, 0) == WAIT_TIMEOUT &&
      CheckIdentity(process, process_id, heartbeat_ms, expected_path) == HostIdentity::match;
  CloseHandle(process);
  return running;
}

bool RetireRemoteHostProcess(DWORD process_id, int64_t heartbeat_ms,
                            const std::wstring& expected_path) {
  if (process_id == 0 || process_id == GetCurrentProcessId() ||
      heartbeat_ms <= 0) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION |
                                   PROCESS_TERMINATE | SYNCHRONIZE,
                               FALSE, process_id);
  if (!process) return GetLastError() == ERROR_INVALID_PARAMETER;
  const auto identity = CheckIdentity(process, process_id, heartbeat_ms, expected_path);
  if (identity == HostIdentity::obsolete) {
    CloseHandle(process);
    return true;  // stale PID/path; do not kill the replacement process
  }
  bool retired = WaitForSingleObject(process, 0) == WAIT_OBJECT_0;
  if (!retired && identity == HostIdentity::match && TerminateProcess(process, 0)) {
    retired = WaitForSingleObject(process, 3000) == WAIT_OBJECT_0;
  }
  CloseHandle(process);
  return retired;
}
