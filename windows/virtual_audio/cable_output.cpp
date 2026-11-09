#include "cable_output.h"
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#include <wrl/client.h>
#include <avrt.h>
#include <algorithm>
#include <chrono>
#include <cwctype>
#include <set>

using Microsoft::WRL::ComPtr;
namespace {
struct Apartment {
  HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ~Apartment() { if (SUCCEEDED(result)) CoUninitialize(); }
};
std::wstring Property(IPropertyStore* store, const PROPERTYKEY& key) {
  PROPVARIANT value; PropVariantInit(&value); std::wstring text;
  if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR && value.pwszVal) text = value.pwszVal;
  PropVariantClear(&value); return text;
}
bool CableName(std::wstring name) {
  std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return name.find(L"vb-audio") != std::wstring::npos && name.find(L"cable") != std::wstring::npos;
}
}
std::vector<LocalistCableEndpoint> LocalistCableEndpoints(bool recording, bool all) {
  Apartment apartment;
  std::vector<LocalistCableEndpoint> result;
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) return result;
  ComPtr<IMMDeviceCollection> collection;
  if (FAILED(enumerator->EnumAudioEndpoints(recording ? eCapture : eRender, DEVICE_STATE_ACTIVE, &collection))) return result;
  UINT count = 0; collection->GetCount(&count);
  std::set<std::wstring> interfaces;
  for (UINT i = 0; i < count; ++i) {
    ComPtr<IMMDevice> device; ComPtr<IPropertyStore> store;
    if (FAILED(collection->Item(i, &device)) || FAILED(device->OpenPropertyStore(STGM_READ, &store))) continue;
    const auto name = Property(store.Get(), PKEY_Device_FriendlyName);
    const auto interfaceName=Property(store.Get(),PKEY_DeviceInterface_FriendlyName);
    // The 16-channel render alias feeds the SAME base recording endpoint.
    // It must not be advertised as another independent microphone.
    auto normalized=name;
    std::transform(normalized.begin(),normalized.end(),normalized.begin(),[](wchar_t c){return static_cast<wchar_t>(towlower(c));});
    normalized.erase(std::remove_if(normalized.begin(),normalized.end(),[](wchar_t c){return iswspace(c)!=0;}),normalized.end());
    if (normalized.find(L"16ch") != std::wstring::npos) continue;
    // Interface identity remains useful if the user renames the endpoint.
    if (!all && !CableName(interfaceName) && !CableName(name)) continue;
    // A renamed multi-channel alias is still part of the same vendor interface.
    if(!all && !interfaceName.empty() && !interfaces.insert(interfaceName).second)continue;
    LPWSTR id = nullptr;
    if (SUCCEEDED(device->GetId(&id))) { result.push_back({id, name}); CoTaskMemFree(id); }
  }
  std::sort(result.begin(), result.end(), [](const auto& a, const auto& b) { return a.name < b.name; });
  return result;
}
std::vector<LocalistCableEndpoint> LocalistConfiguredCableEndpoints() {
  auto endpoints=LocalistCableEndpoints();
  wchar_t path[32768]{};GetModuleFileNameW(nullptr,path,32768);
  std::wstring ini(path);ini=ini.substr(0,ini.find_last_of(L"\\/"))+L"\\capture-devices.ini";
  const auto count=std::clamp(GetPrivateProfileIntW(L"Devices",L"Microphones",4,ini.c_str()),1u,4u);
  if(endpoints.size()>count)endpoints.resize(count);
  return endpoints;
}
std::wstring LocalistDefaultPlaybackEndpoint() {
  Apartment apartment;ComPtr<IMMDeviceEnumerator> enumerator;ComPtr<IMMDevice> device;
  if(FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumerator)))||
      FAILED(enumerator->GetDefaultAudioEndpoint(eRender,eConsole,&device)))return {};
  LPWSTR id=nullptr;if(FAILED(device->GetId(&id)))return {};
  std::wstring result(id);CoTaskMemFree(id);return result;
}
bool LocalistCableOutput::Start(const std::wstring& endpointId, const LocalistAudioRenderOptions& options) {
  Stop(); frames_ = 0; error_ = 0; started_ = false; queue_.Clear();
  options_=options;
  queue_.Configure(options.minimum_ms,options.maximum_ms,options.gain_db);
  endpoint_id_ = endpointId;
  stop_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!stop_) { error_ = GetLastError(); return false; }
  worker_ = std::thread([this] { Run(); });
  std::unique_lock<std::mutex> lock(ready_lock_);
  if (!ready_.wait_for(lock, std::chrono::seconds(4), [this] { return started_; })) {
    error_ = ERROR_TIMEOUT; lock.unlock(); Stop(); return false;
  }
  return error_ == 0;
}
void LocalistCableOutput::Stop() {
  if (stop_) SetEvent(stop_);
  if (worker_.joinable()) worker_.join();
  if (stop_) CloseHandle(stop_);
  stop_ = nullptr;
  std::lock_guard<std::mutex> lock(queue_lock_); queue_.Clear();
}
void LocalistCableOutput::Push(const int16_t* samples, size_t frames) {
  std::lock_guard<std::mutex> lock(queue_lock_); queue_.Push(samples, frames);
}
LocalistAudioQueueStatus LocalistCableOutput::QueueStatus() {
  std::lock_guard<std::mutex> lock(queue_lock_);
  return {queue_.Buffered(),queue_.Dropped(),queue_.Underruns(),queue_.Clipped()};
}
void LocalistCableOutput::Run() {
  Apartment apartment;
  ComPtr<IMMDeviceEnumerator> enumerator; ComPtr<IMMDevice> device;
  ComPtr<IAudioClient> client; ComPtr<IAudioRenderClient> render;
  HANDLE tick = nullptr; HANDLE priority = nullptr;
  HRESULT status = apartment.result;
  const auto finishStart = [this](HRESULT result) {
    std::lock_guard<std::mutex> lock(ready_lock_);
    error_ = FAILED(result) ? static_cast<unsigned long>(result) : 0;
    started_ = true; ready_.notify_one();
  };
  do {
    if (FAILED(status)) break;
    const auto endpoints = LocalistCableEndpoints(false,options_.playback);
    if (endpoints.empty()) { status = HRESULT_FROM_WIN32(ERROR_NOT_FOUND); break; }
    status = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    if (FAILED(status)) break;
    auto endpoint = std::find_if(endpoints.begin(), endpoints.end(), [this](const auto& e) {
      return e.id == endpoint_id_;
    });
    if (endpoint == endpoints.end()) { status=HRESULT_FROM_WIN32(ERROR_NOT_FOUND);break; }
    status = enumerator->GetDevice(endpoint->id.c_str(), &device); if (FAILED(status)) break;
    status = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, &client); if (FAILED(status)) break;
    WAVEFORMATEX format{}; format.wFormatTag = WAVE_FORMAT_PCM; format.nChannels = 1;
    format.nSamplesPerSec = 48000; format.wBitsPerSample = 16;
    format.nBlockAlign = 2; format.nAvgBytesPerSec = 96000;
    status = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
      (options_.event_sync ? AUDCLNT_STREAMFLAGS_EVENTCALLBACK : 0) | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
      300000, 0, &format, nullptr); if (FAILED(status)) break;
    tick = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!tick) { status = HRESULT_FROM_WIN32(GetLastError()); break; }
    if (options_.event_sync) { status = client->SetEventHandle(tick); if (FAILED(status)) break; }
    status = client->GetService(IID_PPV_ARGS(&render)); if (FAILED(status)) break;
    UINT32 capacity = 0; status = client->GetBufferSize(&capacity); if (FAILED(status)) break;
    status = client->Start(); if (FAILED(status)) break;
    DWORD task = 0; priority = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task);
    finishStart(S_OK);
    const HANDLE waits[] = {stop_, tick};
    while (true) {
      const auto wait = options_.event_sync ? WaitForMultipleObjects(2, waits, FALSE, 2000) : WaitForSingleObject(stop_,5);
      if (wait == WAIT_OBJECT_0) break;
      if (options_.event_sync ? wait != WAIT_OBJECT_0 + 1 : wait != WAIT_TIMEOUT) { status = HRESULT_FROM_WIN32(wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError()); break; }
      UINT32 padding = 0; status = client->GetCurrentPadding(&padding); if (FAILED(status)) break;
      if (padding >= capacity) continue;
      const UINT32 available = capacity - padding;
      BYTE* buffer = nullptr; status = render->GetBuffer(available, &buffer); if (FAILED(status)) break;
      auto* pcm = reinterpret_cast<int16_t*>(buffer);
      { std::lock_guard<std::mutex> lock(queue_lock_); queue_.Pull(pcm, available); }
      status = render->ReleaseBuffer(available, 0); if (FAILED(status)) break;
      frames_ += available;
    }
    client->Stop();
  } while (false);
  if (FAILED(status)) error_ = static_cast<unsigned long>(status);
  // The startup caller must always be released, including missing endpoints.
  { std::lock_guard<std::mutex> lock(ready_lock_); if (!started_) { started_ = true; ready_.notify_one(); } }
  if (priority) AvRevertMmThreadCharacteristics(priority);
  if (tick) CloseHandle(tick);
}
