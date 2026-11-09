// A separate WASAPI recording consumer; never selects a hardware microphone.
#include "../windows/virtual_audio/cable_output.h"
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <wrl/client.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>
#include <cmath>
using Microsoft::WRL::ComPtr;
int wmain(int argc, wchar_t** argv) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const auto endpoints=LocalistCableEndpoints(true);
  for (const auto& endpoint:LocalistCableEndpoints()) std::wcout << L"PLAYBACK " << endpoint.name << L"\n";
  for (const auto& endpoint:endpoints) std::wcout << L"MICROPHONE " << endpoint.name << L"\n";
  if(argc<4 || endpoints.empty()) return endpoints.empty()?2:0;
  ComPtr<IMMDeviceEnumerator> enumerator;ComPtr<IMMDevice> device;
  ComPtr<IAudioClient> client;ComPtr<IAudioCaptureClient> capture;
  HRESULT hr=CoCreateInstance(__uuidof(MMDeviceEnumerator),nullptr,CLSCTX_ALL,IID_PPV_ARGS(&enumerator));
  auto selected=endpoints.begin();for(auto it=endpoints.begin();it!=endpoints.end();++it)
    if(it->name.find(L"CABLE Output (")!=std::wstring::npos){selected=it;break;}
  if(SUCCEEDED(hr))hr=enumerator->GetDevice(selected->id.c_str(),&device);
  if(SUCCEEDED(hr))hr=device->Activate(__uuidof(IAudioClient),CLSCTX_ALL,nullptr,&client);
  WAVEFORMATEX* format=nullptr;if(SUCCEEDED(hr))hr=client->GetMixFormat(&format);
  if(SUCCEEDED(hr))hr=client->Initialize(AUDCLNT_SHAREMODE_SHARED,0,1000000,0,format,nullptr);
  if(SUCCEEDED(hr))hr=client->GetService(IID_PPV_ARGS(&capture));
  if(SUCCEEDED(hr))hr=client->Start();
  if(FAILED(hr)){std::cerr << "CAPTURE_ERROR " << std::hex << hr;return 3;}
  std::ofstream output(argv[2],std::ios::binary);
  const bool floating=format->wFormatTag==WAVE_FORMAT_IEEE_FLOAT ||
    (format->wFormatTag==WAVE_FORMAT_EXTENSIBLE && reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat==KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
  std::wcout << L"CAPTURE_READY rate=" << format->nSamplesPerSec << L" channels=" << format->nChannels << L" bits=" << format->wBitsPerSample << std::endl;
  std::wofstream metadata(std::wstring(argv[2])+L".json");
  metadata << L"{\"rate\":" << format->nSamplesPerSec << L",\"channels\":" << format->nChannels << L"}";metadata.close();
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(60);
  while(std::chrono::steady_clock::now()<deadline && GetFileAttributesW(argv[3])==INVALID_FILE_ATTRIBUTES){
    UINT32 frames=0;hr=capture->GetNextPacketSize(&frames);if(FAILED(hr))break;
    while(frames){
      BYTE* data=nullptr;DWORD flags=0;hr=capture->GetBuffer(&data,&frames,&flags,nullptr,nullptr);if(FAILED(hr))break;
      for(UINT32 i=0;i<frames;++i){
        float value=0;const BYTE* p=(flags&AUDCLNT_BUFFERFLAGS_SILENT)?nullptr:data+i*format->nBlockAlign;
        if(p){
          if(floating && format->wBitsPerSample==32)value=*reinterpret_cast<const float*>(p);
          else if(format->wBitsPerSample==16)value=*reinterpret_cast<const int16_t*>(p)/32768.0f;
          else if(format->wBitsPerSample==32)value=*reinterpret_cast<const int32_t*>(p)/2147483648.0f;
          else { capture->ReleaseBuffer(frames);return 4; }
        }
        output.write(reinterpret_cast<const char*>(&value),sizeof(value));
      }
      capture->ReleaseBuffer(frames);hr=capture->GetNextPacketSize(&frames);if(FAILED(hr))break;
    }
    if(FAILED(hr))break;
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  client->Stop();CoTaskMemFree(format);return FAILED(hr)?5:0;
}
