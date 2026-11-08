#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include "webrtc_virtual_camera.h"
#include "capture_controls.h"
#include "virtualcam-guid.h"
#include <ocidl.h>
extern "C" int LocalistVirtualCameraSetTexture(int64_t, int);
extern "C" uint64_t LocalistVirtualCameraFrames();
extern "C" int LocalistVirtualCameraSetSlot(int,int64_t,int);
extern "C" uint64_t LocalistVirtualCameraSlotFrames(int);

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) return 1;
  const std::wstring command = argv[1];
  if (command == L"--controls-four") {
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    for(int slot=0;slot<4;++slot) {
      LocalistCaptureState state;state.enabled=1;state.max_zoom=1000+slot*100;
      if(!PublishLocalistCaptureState(state,slot)) return 20;
      CLSID cls=CLSID_OBS_VirtualVideo;cls.Data1+=slot;
      IBaseFilter* filter=nullptr;
      if(FAILED(CoCreateInstance(cls,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&filter))))return 21;
      IAMCameraControl* control=nullptr;
      if(FAILED(filter->QueryInterface(IID_PPV_ARGS(&control)))){filter->Release();return 22;}
      long min=0,max=0,step=0,initial=0,flags=0;
      const bool valid=SUCCEEDED(control->GetRange(CameraControl_Zoom,&min,&max,&step,&initial,&flags)) && max==1000+slot*100 &&
        SUCCEEDED(control->Set(CameraControl_Zoom,200+slot*100,CameraControl_Flags_Manual));
      control->Release();filter->Release();
      char command[1024]={};
      if(!valid || !TakeLocalistCaptureCommand(command,sizeof(command),slot))return 23;
      for(int other=0;other<4;++other)if(other!=slot && TakeLocalistCaptureCommand(command,sizeof(command),other))return 24;
    }
    std::ofstream output(argv[2]);output<<"{\"independentControls\":4}";
    CoUninitialize();return 0;
  }
  if (command == L"--controls") {
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    LocalistCaptureState state; state.enabled=1; state.max_zoom=1000; state.microphones=1; state.persian=1;
    wcscpy_s(state.microphone_names[0],L"QA microphone");
    if(!PublishLocalistCaptureState(state))return 10;
    IBaseFilter* filter=nullptr;
    if(FAILED(CoCreateInstance(CLSID_OBS_VirtualVideo,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&filter))))return 11;
    IAMCameraControl* camera=nullptr; ISpecifyPropertyPages* pages=nullptr;
    bool success=SUCCEEDED(filter->QueryInterface(IID_PPV_ARGS(&camera))) && SUCCEEDED(filter->QueryInterface(IID_PPV_ARGS(&pages)));
    long min=0,max=0,step=0,initial=0,flags=0;
    success=success&&SUCCEEDED(camera->GetRange(CameraControl_Zoom,&min,&max,&step,&initial,&flags))&&min==100&&max==1000;
    success=success&&FAILED(camera->Set(CameraControl_Zoom,1001,CameraControl_Flags_Manual));
    success=success&&SUCCEEDED(camera->Set(CameraControl_Zoom,200,CameraControl_Flags_Manual));
    char request[1024]={};success=success&&TakeLocalistCaptureCommand(request,sizeof(request))&&std::string(request).find("2.00")!=std::string::npos;
    CAUUID ids{}; if(pages)success=success&&SUCCEEDED(pages->GetPages(&ids))&&ids.cElems==1;
    IPropertyPage* page=nullptr;
    if(ids.cElems)success=success&&SUCCEEDED(CoCreateInstance(ids.pElems[0],nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&page)));
    HWND parent=CreateWindowExW(0,L"STATIC",L"Localist QA",0,0,0,480,420,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    RECT rect{0,0,450,385};PROPPAGEINFO info{};
    if(page){success=success&&SUCCEEDED(page->GetPageInfo(&info))&&info.pszTitle&&SUCCEEDED(page->SetObjects(1,reinterpret_cast<IUnknown**>(&filter)))&&SUCCEEDED(page->Activate(parent,&rect,FALSE));
      success=success&&SUCCEEDED(page->Apply())&&TakeLocalistCaptureCommand(request,sizeof(request))&&std::string(request).find("\"width\":640")!=std::string::npos;
      const auto child=GetWindow(parent,GW_CHILD);success=success&&child&&(GetWindowLongPtrW(child,GWL_EXSTYLE)&WS_EX_LAYOUTRTL)!=0;
      page->Deactivate();page->Release();CoTaskMemFree(info.pszTitle);CoTaskMemFree(info.pszDocString);CoTaskMemFree(info.pszHelpFile);
    }else success=false;
    DestroyWindow(parent);CoTaskMemFree(ids.pElems);
    state.enabled=0;PublishLocalistCaptureState(state);success=success&&!SubmitLocalistCaptureCommand("{\"zoom\":2}");
    if(pages)pages->Release();if(camera)camera->Release();filter->Release();CoUninitialize();
    std::ofstream output(argv[2]);output<<"{\"propertyPageActivated\":"<<(success?"true":"false")<<",\"cameraControlZoom\":"<<(success?"true":"false")<<",\"permissionRevocation\":"<<(success?"true":"false")<<"}";
    return success?0:12;
  }
  if (command.find(L"--register") == 0 || command.find(L"--unregister") == 0) {
    const bool registering = command.find(L"--register") == 0;
    const int slot = command.back() >= L'1' && command.back() <= L'4' ? command.back()-L'1' : 0;
    wchar_t camera_key[100];
    swprintf_s(camera_key,L"CLSID\\{58BC%04X-E9D9-4BB9-A460-6630C82A5301}",0x2225+slot+LOCALIST_CAMERA_GUID_OFFSET);
    // QA uses HKCU only; production registration is independently exercised by
    // the elevated app. Never override an existing per-user Localist filter.
    HKEY classes = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes", 0, nullptr, 0,
        KEY_ALL_ACCESS, nullptr, &classes, nullptr) != ERROR_SUCCESS) return 2;
    HKEY existing = nullptr;
    if (registering && RegOpenKeyExW(classes,
        camera_key, 0, KEY_READ, &existing) == ERROR_SUCCESS) {
      RegCloseKey(existing); RegCloseKey(classes); return 3;
    }
    if (RegOverridePredefKey(HKEY_CLASSES_ROOT, classes) != ERROR_SUCCESS) { RegCloseKey(classes); return 4; }
    HMODULE dll = LoadLibraryW(argv[2]);
    if (!dll) { RegOverridePredefKey(HKEY_CLASSES_ROOT, nullptr); RegCloseKey(classes); return 5; }
    using Registration = HRESULT(STDAPICALLTYPE*)();
    const auto entry = reinterpret_cast<Registration>(GetProcAddress(dll,
        registering ? "DllRegisterServer" : "DllUnregisterServer"));
    const HRESULT result = entry ? entry() : E_FAIL;
    FreeLibrary(dll); RegOverridePredefKey(HKEY_CLASSES_ROOT, nullptr); RegCloseKey(classes);
    return SUCCEEDED(result) ? 0 : 6;
  }
  if (command == L"--produce-four") {
    const int yuv[4][3] = {{81,90,240},{145,54,34},{41,240,110},{235,128,128}};
    std::vector<libwebrtc::scoped_refptr<libwebrtc::RTCVideoFrame>> frames;
    for(int slot=0;slot<4;++slot) {
      std::vector<uint8_t> y(640*480,yuv[slot][0]),u(640*480/4,yuv[slot][1]),v(640*480/4,yuv[slot][2]);
      frames.push_back(libwebrtc::RTCVideoFrame::Create(640,480,y.data(),640,u.data(),320,v.data(),320));
      if(!frames.back() || LocalistVirtualCameraSetSlot(slot,42+slot,30)!=1) return 15;
    }
    for(int i=0;i<900;++i) {
      for(int slot=0;slot<4;++slot) LocalistVirtualCameraFrame(42+slot,frames[slot]);
      Sleep(33);
    }
    std::ofstream output(argv[2]); output << "{\"frames\":[";
    for(int slot=0;slot<4;++slot) { if(slot)output<<",";output<<LocalistVirtualCameraSlotFrames(slot);LocalistVirtualCameraSetSlot(slot,-1,30); }
    output << "]}"; return 0;
  }
  if (command != L"--produce") return 7;
  const int width = 640, height = 480;
  std::vector<uint8_t> y(width * height, 81), u(width * height / 4, 90), v(width * height / 4, 240);
  auto frame = libwebrtc::RTCVideoFrame::Create(width, height, y.data(), width, u.data(), width / 2, v.data(), width / 2);
  if (!frame || LocalistVirtualCameraSetTexture(42, 30) != 1) return 8;
  for (int i = 0; i < 450; ++i) { LocalistVirtualCameraFrame(42, frame); Sleep(33); }
  const auto count = LocalistVirtualCameraFrames();
  LocalistVirtualCameraSetTexture(-1, 30);
  std::ofstream output(argv[2]); output << "{\"publishedFrames\":" << count << ",\"stopped\":true}";
  return count > 400 ? 0 : 9;
}
