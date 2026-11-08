#include <windows.h>
#include <string>
namespace DShow {
std::wstring ConvertHRToEnglish(HRESULT error) {
  wchar_t* message = nullptr;
  const DWORD size = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, static_cast<DWORD>(error), MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US),
      reinterpret_cast<LPWSTR>(&message), 0, nullptr);
  std::wstring result = size && message ? std::wstring(message, size) : L"DirectShow error";
  if (message) LocalFree(message);
  return result;
}
}
