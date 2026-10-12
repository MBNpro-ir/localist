#pragma once

#include <windows.h>
#include <cstdint>
#include <string>

// A stale status PID can have been reused. Only retire a LocalistRemote image
// from the same user/session that was already running at the last heartbeat.
// An unrelated/reused PID is ignored, never terminated.
bool RetireRemoteHostProcess(DWORD process_id, int64_t heartbeat_ms,
                            const std::wstring& expected_path);
bool IsRemoteHostProcessRunning(DWORD process_id, int64_t heartbeat_ms,
                                const std::wstring& expected_path);
