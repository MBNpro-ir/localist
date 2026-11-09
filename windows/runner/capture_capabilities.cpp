#include "capture_capabilities.h"
#include <windows.h>
#include <dshow.h>
#include <dvdmedia.h>
#include <wrl/client.h>
#include <algorithm>
#include <set>
#include <tuple>
#include <vector>

using Microsoft::WRL::ComPtr;
using flutter::EncodableList; using flutter::EncodableMap; using flutter::EncodableValue;
namespace {
std::wstring Wide(const std::string& text) {
  const int n = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (n <= 1) return {};
  std::wstring result(n, 0); MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, result.data(), n);
  result.resize(n-1); return result;
}
std::wstring Property(IPropertyBag* bag, const wchar_t* name) {
  VARIANT value; VariantInit(&value); std::wstring result;
  if (SUCCEEDED(bag->Read(name, &value, nullptr)) && value.vt == VT_BSTR) result = value.bstrVal;
  VariantClear(&value); return result;
}
void FreeType(AM_MEDIA_TYPE* type) {
  if (!type) return;
  if (type->cbFormat) CoTaskMemFree(type->pbFormat);
  if (type->pUnk) type->pUnk->Release();
  CoTaskMemFree(type);
}
}

flutter::EncodableMap GetWindowsCaptureCapabilities(const std::string& device_id) {
  EncodableList modes;
  ComPtr<ICreateDevEnum> devices; ComPtr<IEnumMoniker> monikers;
  if (FAILED(CoCreateInstance(CLSID_SystemDeviceEnum, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&devices))) ||
      devices->CreateClassEnumerator(CLSID_VideoInputDeviceCategory, &monikers, 0) != S_OK) return {{EncodableValue("modes"), EncodableValue(modes)}};
  const auto wanted = Wide(device_id);
  ComPtr<IMoniker> moniker;
  while (monikers->Next(1, &moniker, nullptr) == S_OK) {
    ComPtr<IPropertyBag> bag;
    if (FAILED(moniker->BindToStorage(nullptr, nullptr, IID_PPV_ARGS(&bag)))) { moniker.Reset(); continue; }
    const auto path = Property(bag.Get(), L"DevicePath"), friendly = Property(bag.Get(), L"FriendlyName");
    if (_wcsicmp(path.c_str(), wanted.c_str()) && _wcsicmp(friendly.c_str(), wanted.c_str())) { moniker.Reset(); continue; }
    ComPtr<IBaseFilter> filter; ComPtr<IEnumPins> pins;
    if (FAILED(moniker->BindToObject(nullptr, nullptr, IID_PPV_ARGS(&filter))) || FAILED(filter->EnumPins(&pins))) break;
    std::set<std::tuple<int,int,int,int>> seen;
    ComPtr<IPin> pin;
    while (pins->Next(1, &pin, nullptr) == S_OK) {
      ComPtr<IAMStreamConfig> config; PIN_DIRECTION direction;
      if (FAILED(pin->QueryDirection(&direction)) || direction != PINDIR_OUTPUT || FAILED(pin.As(&config))) { pin.Reset(); continue; }
      int count=0, size=0;
      if (FAILED(config->GetNumberOfCapabilities(&count, &size)) || size < sizeof(VIDEO_STREAM_CONFIG_CAPS)) { pin.Reset(); continue; }
      std::vector<BYTE> data(size);
      for (int i=0; i<std::min(count, 1024); ++i) {
        AM_MEDIA_TYPE* type=nullptr;
        if (FAILED(config->GetStreamCaps(i, &type, data.data())) || !type) continue;
        BITMAPINFOHEADER* bitmap = nullptr;
        if (type->formattype == FORMAT_VideoInfo && type->cbFormat >= sizeof(VIDEOINFOHEADER)) bitmap = &reinterpret_cast<VIDEOINFOHEADER*>(type->pbFormat)->bmiHeader;
        if (type->formattype == FORMAT_VideoInfo2 && type->cbFormat >= sizeof(VIDEOINFOHEADER2)) bitmap = &reinterpret_cast<VIDEOINFOHEADER2*>(type->pbFormat)->bmiHeader;
        if (bitmap) {
          const auto* caps = reinterpret_cast<VIDEO_STREAM_CONFIG_CAPS*>(data.data());
          const int width=bitmap->biWidth, height=abs(bitmap->biHeight);
          const int min_fps=caps->MaxFrameInterval>0?std::max(1,static_cast<int>(10000000/caps->MaxFrameInterval)):1;
          const int max_fps=caps->MinFrameInterval>0?std::min(240,static_cast<int>(10000000/caps->MinFrameInterval)):0;
          if (width>=2 && height>=2 && width<=8192 && height<=8192 && max_fps>=min_fps && seen.emplace(width,height,min_fps,max_fps).second)
            modes.emplace_back(EncodableMap{{EncodableValue("width"),EncodableValue(width)},{EncodableValue("height"),EncodableValue(height)},
              {EncodableValue("minFps"),EncodableValue(min_fps)},{EncodableValue("maxFps"),EncodableValue(max_fps)}});
        }
        FreeType(type);
      }
      pin.Reset();
    }
    break;
  }
  return {{EncodableValue("modes"),EncodableValue(modes)}};
}
