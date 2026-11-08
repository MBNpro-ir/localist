#include <windows.h>
#include <string>
#include <vector>

namespace {
struct Resource { WORD type, id, language; bool numeric; std::wstring name; };
BOOL CALLBACK Language(HMODULE, LPCWSTR type, LPCWSTR name, WORD language, LONG_PTR data) {
  auto& resources = *reinterpret_cast<std::vector<Resource>*>(data);
  resources.push_back({static_cast<WORD>(reinterpret_cast<ULONG_PTR>(type)),
      IS_INTRESOURCE(name) ? static_cast<WORD>(reinterpret_cast<ULONG_PTR>(name)) : WORD(0),
      language, IS_INTRESOURCE(name), IS_INTRESOURCE(name) ? L"" : name});
  return TRUE;
}
BOOL CALLBACK Name(HMODULE module, LPCWSTR type, LPWSTR name, LONG_PTR data) {
  return EnumResourceLanguagesW(module, type, name, Language, data);
}
}
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 1;
  HMODULE module = LoadLibraryExW(argv[1], nullptr, LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
  if (!module) return 2;
  std::vector<Resource> resources;
  for (LPCWSTR type : {RT_GROUP_ICON, RT_ICON}) {
    if (!EnumResourceNamesW(module, type, Name, reinterpret_cast<LONG_PTR>(&resources)) &&
        GetLastError() != ERROR_RESOURCE_TYPE_NOT_FOUND) { FreeLibrary(module); return 3; }
  }
  FreeLibrary(module);
  if (resources.empty()) return 0;
  HANDLE update = BeginUpdateResourceW(argv[1], FALSE);
  if (!update) return 4;
  for (const auto& resource : resources) {
    if (!UpdateResourceW(update, MAKEINTRESOURCEW(resource.type),
        resource.numeric ? MAKEINTRESOURCEW(resource.id) : resource.name.c_str(),
        resource.language, nullptr, 0)) { EndUpdateResourceW(update, TRUE); return 5; }
  }
  return EndUpdateResourceW(update, FALSE) ? 0 : 6;
}
