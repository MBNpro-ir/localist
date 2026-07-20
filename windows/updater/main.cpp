#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

namespace {

struct UpdateArguments {
  DWORD wait_pid = 0;
  std::wstring archive;
  std::wstring target;
  std::wstring launch;
  std::wstring version;
};

std::wstring QuoteArgument(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

std::wstring JoinPath(const std::wstring& directory, const std::wstring& name) {
  if (directory.empty()) {
    return name;
  }
  const wchar_t last = directory.back();
  return directory + (last == L'\\' || last == L'/' ? L"" : L"\\") + name;
}

bool IsRegularFile(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool IsDirectory(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

void DeleteTree(const std::wstring& directory) {
  if (!IsDirectory(directory)) {
    return;
  }
  WIN32_FIND_DATAW entry{};
  HANDLE find = FindFirstFileW(JoinPath(directory, L"*").c_str(), &entry);
  if (find != INVALID_HANDLE_VALUE) {
    do {
      const std::wstring name(entry.cFileName);
      if (name == L"." || name == L"..") {
        continue;
      }
      const std::wstring child = JoinPath(directory, name);
      if ((entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        DeleteTree(child);
      } else {
        SetFileAttributesW(child.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(child.c_str());
      }
    } while (FindNextFileW(find, &entry));
    FindClose(find);
  }
  RemoveDirectoryW(directory.c_str());
}

bool ParseArguments(UpdateArguments* output) {
  int count = 0;
  LPWSTR* values = CommandLineToArgvW(GetCommandLineW(), &count);
  if (values == nullptr) {
    return false;
  }
  for (int index = 1; index + 1 < count; index += 2) {
    const std::wstring key(values[index]);
    const std::wstring value(values[index + 1]);
    if (key == L"--wait-pid") {
      output->wait_pid = static_cast<DWORD>(_wtoi(value.c_str()));
    } else if (key == L"--archive") {
      output->archive = value;
    } else if (key == L"--target") {
      output->target = value;
    } else if (key == L"--launch") {
      output->launch = value;
    } else if (key == L"--version") {
      output->version = value;
    }
  }
  LocalFree(values);
  return output->wait_pid != 0 && IsRegularFile(output->archive) &&
         IsDirectory(output->target) && !output->launch.empty() &&
         !output->version.empty();
}

bool WaitForApplication(DWORD process_id) {
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, process_id);
  if (process == nullptr) {
    return GetLastError() == ERROR_INVALID_PARAMETER;
  }
  const DWORD result = WaitForSingleObject(process, 120000);
  CloseHandle(process);
  return result == WAIT_OBJECT_0;
}

std::wstring SystemExecutable(const wchar_t* relative_path) {
  wchar_t directory[MAX_PATH];
  const UINT length = GetSystemDirectoryW(directory, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return std::wstring();
  }
  return JoinPath(directory, relative_path);
}

bool RunAndWait(const std::wstring& executable, const std::wstring& arguments,
                DWORD* exit_code) {
  std::wstring command_line = QuoteArgument(executable) + L" " + arguments;
  std::vector<wchar_t> buffer(command_line.begin(), command_line.end());
  buffer.push_back(L'\0');
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  if (!CreateProcessW(executable.c_str(), buffer.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr,
                      nullptr, &startup_info, &process_info)) {
    return false;
  }
  CloseHandle(process_info.hThread);
  const DWORD wait_result = WaitForSingleObject(process_info.hProcess, 120000);
  if (wait_result == WAIT_OBJECT_0) {
    GetExitCodeProcess(process_info.hProcess, exit_code);
  }
  CloseHandle(process_info.hProcess);
  return wait_result == WAIT_OBJECT_0;
}

std::wstring PowerShellLiteral(const std::wstring& value) {
  std::wstring escaped;
  escaped.reserve(value.size() + 2);
  for (const wchar_t character : value) {
    if (character == L'\'') {
      escaped += L"''";
    } else {
      escaped.push_back(character);
    }
  }
  return L"'" + escaped + L"'";
}

std::wstring FindBundleDirectory(const std::wstring& staging) {
  if (IsRegularFile(JoinPath(staging, L"Localist.exe"))) {
    return staging;
  }
  WIN32_FIND_DATAW entry{};
  HANDLE find = FindFirstFileW(JoinPath(staging, L"*").c_str(), &entry);
  if (find == INVALID_HANDLE_VALUE) {
    return std::wstring();
  }
  std::wstring bundle;
  do {
    if ((entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        wcscmp(entry.cFileName, L".") == 0 ||
        wcscmp(entry.cFileName, L"..") == 0) {
      continue;
    }
    const std::wstring candidate = JoinPath(staging, entry.cFileName);
    if (IsRegularFile(JoinPath(candidate, L"Localist.exe"))) {
      bundle = candidate;
      break;
    }
  } while (FindNextFileW(find, &entry));
  FindClose(find);
  return bundle;
}

bool LaunchUpdatedApplication(const std::wstring& executable,
                              const std::wstring& version) {
  std::wstring command_line = QuoteArgument(executable) + L" --updated-to=" +
                              QuoteArgument(version);
  std::vector<wchar_t> buffer(command_line.begin(), command_line.end());
  buffer.push_back(L'\0');
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  PROCESS_INFORMATION process_info{};
  if (!CreateProcessW(executable.c_str(), buffer.data(), nullptr, nullptr, FALSE,
                      CREATE_UNICODE_ENVIRONMENT, nullptr, nullptr, &startup_info,
                      &process_info)) {
    return false;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return true;
}

int Fail(const std::wstring& message) {
  MessageBoxW(nullptr, message.c_str(), L"Localist update",
              MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
  return 1;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  UpdateArguments arguments;
  if (!ParseArguments(&arguments)) {
    return Fail(L"The update request was incomplete or the downloaded package is missing.");
  }
  if (!WaitForApplication(arguments.wait_pid)) {
    return Fail(L"Localist did not close in time. Please close it and try the update again.");
  }

  wchar_t temp_path[MAX_PATH];
  const DWORD temp_length = GetTempPathW(MAX_PATH, temp_path);
  if (temp_length == 0 || temp_length >= MAX_PATH) {
    return Fail(L"A temporary directory could not be prepared for the update.");
  }
  const std::wstring staging = std::wstring(temp_path) + L"Localist-update-" +
                               std::to_wstring(GetCurrentProcessId()) + L"-" +
                               std::to_wstring(GetTickCount64());
  if (!CreateDirectoryW(staging.c_str(), nullptr)) {
    return Fail(L"A temporary update directory could not be created.");
  }

  const std::wstring powershell =
      SystemExecutable(L"WindowsPowerShell\\v1.0\\powershell.exe");
  DWORD extraction_exit_code = 1;
  const std::wstring extraction_command =
      L"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " +
      QuoteArgument(L"$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath " +
                    PowerShellLiteral(arguments.archive) + L" -DestinationPath " +
                    PowerShellLiteral(staging) + L" -Force");
  if (powershell.empty() || !RunAndWait(powershell, extraction_command,
                                        &extraction_exit_code) ||
      extraction_exit_code != 0) {
    DeleteTree(staging);
    return Fail(L"The downloaded Localist update could not be unpacked.");
  }

  const std::wstring bundle = FindBundleDirectory(staging);
  if (bundle.empty()) {
    DeleteTree(staging);
    return Fail(L"The update package does not contain Localist.exe.");
  }
  const std::wstring robocopy = SystemExecutable(L"robocopy.exe");
  DWORD copy_exit_code = 16;
  const std::wstring copy_arguments =
      QuoteArgument(bundle) + L" " + QuoteArgument(arguments.target) +
      L" /MIR /R:3 /W:1 /NFL /NDL /NJH /NJS /NP /XF debug.log localist-update.log";
  if (robocopy.empty() || !RunAndWait(robocopy, copy_arguments, &copy_exit_code) ||
      copy_exit_code > 7) {
    DeleteTree(staging);
    return Fail(L"Localist files could not be replaced. Please try again with administrator access.");
  }

  DeleteFileW(arguments.archive.c_str());
  DeleteTree(staging);
  if (!LaunchUpdatedApplication(arguments.launch, arguments.version)) {
    return Fail(L"The update was installed, but Localist could not be restarted.");
  }
  return 0;
}
