#include <windows.h>
#include <string>

// PE resources must remain identical for the native executable-pair IPC trust.
// Hide the helper through metadata, without changing any binary bytes.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2 && argc != 3) return 1;
  const bool unhide = argc == 3 && std::wstring(argv[1]) == L"--unhide";
  const wchar_t* path = argv[argc - 1];
  const DWORD attributes = GetFileAttributesW(path);
  if (attributes == INVALID_FILE_ATTRIBUTES) return 2;
  return SetFileAttributesW(path, unhide ? attributes & ~FILE_ATTRIBUTE_HIDDEN : attributes | FILE_ATTRIBUTE_HIDDEN) ? 0 : 3;
}
