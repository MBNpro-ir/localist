#include <windows.h>
#include <fstream>
#include <algorithm>
#include "capture_capabilities.h"

int wmain(int argc, wchar_t** argv) {
  if (argc != 2 || FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 2;
  const auto result = GetWindowsCaptureCapabilities("Localist QA Camera 1");
  const auto found = result.find(flutter::EncodableValue("modes"));
  if (found == result.end()) return 3;
  const auto* modes = std::get_if<flutter::EncodableList>(&found->second);
  if (!modes || modes->empty()) return 4;
  bool full_hd = false; int max_width = 0;
  for (const auto& value : *modes) {
    const auto& mode = std::get<flutter::EncodableMap>(value);
    const auto width = std::get<int>(mode.at(flutter::EncodableValue("width")));
    const auto height = std::get<int>(mode.at(flutter::EncodableValue("height")));
    const auto fps = std::get<int>(mode.at(flutter::EncodableValue("maxFps")));
    if (width == 1920 && height == 1080 && fps > 0) full_hd = true;
    max_width = std::max(width, max_width);
  }
  std::ofstream output(argv[1]);
  output << "{\"modes\":" << modes->size() << ",\"maxWidth\":" << max_width << ",\"fullHD\":" << (full_hd?"true":"false") << "}";
  CoUninitialize();
  return full_hd ? 0 : 5;
}
