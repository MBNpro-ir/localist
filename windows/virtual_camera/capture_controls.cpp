#include "capture_controls.h"
#include "virtualcam-filter.hpp"
#include <ocidl.h>
#include <cstdio>
#include <string>
#include <cstring>
#include <utility>
extern HINSTANCE dll_inst;
extern volatile long locks;

STDMETHODIMP VCamFilter::QueryInterface(REFIID iid, void** out) {
  if (!out) return E_POINTER;
  if (iid == IID_IAMCameraControl) *out = static_cast<IAMCameraControl*>(this);
  else if (iid == IID_ISpecifyPropertyPages) *out = static_cast<ISpecifyPropertyPages*>(this);
  else return OutputFilter::QueryInterface(iid, out);
  AddRef(); return S_OK;
}
STDMETHODIMP VCamFilter::GetPages(CAUUID* pages) {
  if (!pages) return E_POINTER;
  pages->cElems = 0; pages->pElems = static_cast<GUID*>(CoTaskMemAlloc(sizeof(GUID)));
  if (!pages->pElems) return E_OUTOFMEMORY;
  pages->pElems[0] = CLSID_LocalistControls; pages->cElems = 1; return S_OK;
}
STDMETHODIMP VCamFilter::GetRange(long property, long* minimum, long* maximum, long* step, long* initial, long* flags) {
  if (!minimum || !maximum || !step || !initial || !flags) return E_POINTER;
  if (property != CameraControl_Zoom) return E_PROP_ID_UNSUPPORTED;
  LocalistCaptureState state; ReadLocalistCaptureState(state);
  *minimum = 100; *maximum = state.max_zoom; *step = 1; *initial = 100; *flags = CameraControl_Flags_Manual; return S_OK;
}
STDMETHODIMP VCamFilter::Get(long property, long* value, long* flags) {
  if (!value || !flags) return E_POINTER;
  if (property != CameraControl_Zoom) return E_PROP_ID_UNSUPPORTED;
  LocalistCaptureState state;
  if (!ReadLocalistCaptureState(state)) return VFW_E_NOT_CONNECTED;
  *value = state.zoom; *flags = CameraControl_Flags_Manual; return S_OK;
}
STDMETHODIMP VCamFilter::Set(long property, long value, long flags) {
  if (property != CameraControl_Zoom) return E_PROP_ID_UNSUPPORTED;
  LocalistCaptureState state;
  if (!ReadLocalistCaptureState(state) || !state.enabled) return VFW_E_NOT_CONNECTED;
  if (flags != CameraControl_Flags_Manual || value < 100 || value > state.max_zoom) return E_INVALIDARG;
  char json[80]; sprintf_s(json, "{\"zoom\":%.2f}", value / 100.0);
  return SubmitLocalistCaptureCommand(json) ? S_OK : E_FAIL;
}

namespace {
class ControlsPage : public IPropertyPage {
  long refs = 1;
  bool persian = false;
  const wchar_t* Text(const wchar_t* fa, const wchar_t* en) const { return persian ? fa : en; }
  IPropertyPageSite* site = nullptr;
  HWND window = nullptr, resolution = nullptr, fps = nullptr, bitrate = nullptr, zoom = nullptr;
  HWND noise = nullptr, echo = nullptr, gain = nullptr, torch = nullptr, microphone = nullptr, message = nullptr, apply = nullptr;
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT event, WPARAM w, LPARAM l) {
    auto* page = reinterpret_cast<ControlsPage*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (event == WM_NCCREATE) { page = static_cast<ControlsPage*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams); SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(page)); }
    if (page && event == WM_COMMAND && LOWORD(w) == 100) { page->Apply(); return 0; }
    if (page && event == WM_TIMER) {
      LocalistCaptureState state;
      if (!ReadLocalistCaptureState(state)) { SetWindowTextW(page->message,page->Text(L"گیرندهٔ لوکالیست در دسترس نیست.",L"Localist receiver is unavailable.")); EnableWindow(page->apply,FALSE); }
      else if (state.message[0]) SetWindowTextW(page->message,state.message);
      else { SetWindowTextW(page->message,page->Text(L"برای خواندن تنظیمات فعلی، پنل را دوباره باز کنید. وضوح و نرخ فریم خروجی در Properties تنظیم می‌شوند.",L"Read current settings by reopening this panel. Output resolution/FPS is set in OBS Properties.")); EnableWindow(page->apply,state.enabled); }
      return 0;
    }
    return DefWindowProcW(hwnd, event, w, l);
  }
  HWND Control(const wchar_t* type, const wchar_t* text, DWORD style, int x, int y, int width, int height, int id = 0) {
    HWND result = CreateWindowExW(0, type, text, WS_CHILD | WS_VISIBLE | style, x, y, width, height, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    SendMessageW(result, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE); return result;
  }
  void Label(const wchar_t* text, int y) { Control(L"STATIC", text, 0, 12, y + 3, 172, 22); }
  HWND Combo(int y) { return Control(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, 190, y, 240, 200); }
  void Option(HWND combo, const wchar_t* label, LPARAM value) { const auto index = SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(label)); SendMessageW(combo, CB_SETITEMDATA, index, value); }
  void Select(HWND combo, LPARAM value) { const auto count = SendMessageW(combo, CB_GETCOUNT, 0, 0); for (int i = 0; i < count; ++i) if (SendMessageW(combo, CB_GETITEMDATA, i, 0) == value) { SendMessageW(combo, CB_SETCURSEL, i, 0); return; } SendMessageW(combo, CB_SETCURSEL, 0, 0); }
  int Value(HWND combo) { return static_cast<int>(SendMessageW(combo, CB_GETITEMDATA, SendMessageW(combo, CB_GETCURSEL, 0, 0), 0)); }
public:
  ControlsPage() { InterlockedIncrement(&locks); }
  STDMETHODIMP QueryInterface(REFIID iid, void** out) override { if (!out) return E_POINTER; *out = nullptr; if (iid != IID_IUnknown && iid != IID_IPropertyPage) return E_NOINTERFACE; *out = static_cast<IPropertyPage*>(this); AddRef(); return S_OK; }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs); }
  STDMETHODIMP_(ULONG) Release() override { const auto count = InterlockedDecrement(&refs); if (!count) delete this; return count; }
  ~ControlsPage() { Deactivate(); if (site) site->Release(); UnregisterClassW(L"LocalistCameraControls-v1",dll_inst); InterlockedDecrement(&locks); }
  STDMETHODIMP SetPageSite(IPropertyPageSite* value) override { if (site) site->Release(); site = value; if (site) site->AddRef(); return S_OK; }
  STDMETHODIMP Activate(HWND parent, LPCRECT rect, BOOL) override {
    if (!parent || !rect) return E_POINTER;
    LocalistCaptureState state; const bool fresh = ReadLocalistCaptureState(state); persian = state.persian != 0;
    WNDCLASSW cls{}; cls.lpfnWndProc = WindowProc; cls.hInstance = dll_inst; cls.lpszClassName = L"LocalistCameraControls-v1"; cls.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1); RegisterClassW(&cls);
    window = CreateWindowExW(persian ? WS_EX_LAYOUTRTL : 0, cls.lpszClassName, L"Localist Camera", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN, rect->left, rect->top, rect->right-rect->left, rect->bottom-rect->top, parent, nullptr, cls.hInstance, this);
    if (!window) return E_FAIL;
    Control(L"STATIC", Text(L"تنظیمات ضبط دستگاه فرستندهٔ جفت‌شده",L"Phone capture controls (paired Localist sender)"), 0, 12, 10, 430, 22);
    Label(Text(L"وضوح ضبط",L"Capture resolution"), 40); resolution = Combo(40);
    for (const auto& item : {std::pair<int,const wchar_t*>{320,L"320 x 240"},{640,L"640 x 480"},{1280,L"1280 x 720"},{1920,L"1920 x 1080"}}) Option(resolution, item.second, item.first);
    Select(resolution, state.width);
    Label(Text(L"نرخ فریم ضبط",L"Capture FPS"), 75); fps = Combo(75); for (int value : {10,15,24,30,60}) { const auto text = std::to_wstring(value); Option(fps, text.c_str(), value); } Select(fps, state.fps);
    Label(Text(L"بیت‌ریت (250-12000 kbps)",L"Bitrate (250-12000 kbps)"), 110); bitrate = Control(L"EDIT", std::to_wstring(state.bitrate).c_str(), WS_BORDER | ES_NUMBER | WS_TABSTOP, 190, 110, 240, 24);
    Label(Text(L"زوم (100 برابر 1x)",L"Zoom (100 = 1x)"), 145); zoom = Control(L"EDIT", std::to_wstring(state.zoom).c_str(), WS_BORDER | ES_NUMBER | WS_TABSTOP, 190, 145, 240, 24);
    Label(Text(L"میکروفون",L"Microphone"), 180); microphone = Combo(180); Option(microphone, Text(L"حفظ ورودی فعلی",L"Keep current input"), -1); for (int i = 0; i < state.microphones; ++i) Option(microphone, state.microphone_names[i], i); Select(microphone, state.microphone);
    noise = Control(L"BUTTON", Text(L"کاهش نویز",L"Noise reduction"), BS_AUTOCHECKBOX | WS_TABSTOP, 12, 220, 210, 24);
    echo = Control(L"BUTTON", Text(L"حذف اکو",L"Echo cancellation"), BS_AUTOCHECKBOX | WS_TABSTOP, 230, 220, 210, 24);
    gain = Control(L"BUTTON", Text(L"تنظیم خودکار بهرهٔ صدا",L"Automatic gain"), BS_AUTOCHECKBOX | WS_TABSTOP, 12, 250, 210, 24);
    torch = Control(L"BUTTON", Text(L"چراغ دوربین",L"Camera light"), BS_AUTOCHECKBOX | WS_TABSTOP, 230, 250, 210, 24);
    SendMessageW(noise,BM_SETCHECK,state.noise?BST_CHECKED:BST_UNCHECKED,0); SendMessageW(echo,BM_SETCHECK,state.echo?BST_CHECKED:BST_UNCHECKED,0); SendMessageW(gain,BM_SETCHECK,state.gain?BST_CHECKED:BST_UNCHECKED,0); SendMessageW(torch,BM_SETCHECK,state.torch?BST_CHECKED:BST_UNCHECKED,0);
    EnableWindow(torch, state.torch_available && state.enabled); EnableWindow(zoom,state.max_zoom>100 && state.enabled);
    apply = Control(L"BUTTON", Text(L"اعمال روی دستگاه فرستنده",L"Apply to paired sender"), BS_PUSHBUTTON | WS_TABSTOP, 190, 285, 240, 28, 100); EnableWindow(apply, fresh && state.enabled);
    message = Control(L"STATIC", fresh && state.enabled ? Text(L"تغییر کیفیت، ضبط را لحظه‌ای بازآغاز می‌کند؛ اتصال باز می‌ماند.",L"Quality changes briefly restart capture; the connection stays open.") : Text(L"کنترل گیرنده را در فرستنده مجاز کنید، سپس در لوکالیست متصل شوید و خروجی وبکم مجازی را روشن کنید.",L"Enable receiver controls on the sender, connect in Localist and enable virtual webcam output first."), 0, 12, 325, 420, 50);
    SetTimer(window,1,1000,nullptr);
    return S_OK;
  }
  STDMETHODIMP Deactivate() override { if(window) DestroyWindow(window); window=nullptr; return S_OK; }
  STDMETHODIMP GetPageInfo(PROPPAGEINFO* info) override { if(!info) return E_POINTER; *info={}; info->cb=sizeof(*info); const wchar_t title[]=L"Localist Camera"; info->pszTitle=static_cast<LPOLESTR>(CoTaskMemAlloc(sizeof(title))); if(!info->pszTitle)return E_OUTOFMEMORY; memcpy(info->pszTitle,title,sizeof(title)); info->size={450,385}; return S_OK; }
  STDMETHODIMP SetObjects(ULONG, IUnknown**) override { return S_OK; }
  STDMETHODIMP Show(UINT cmd) override { if(window) ShowWindow(window,cmd); return S_OK; }
  STDMETHODIMP Move(LPCRECT r) override { if(!r)return E_POINTER; if(window) MoveWindow(window,r->left,r->top,r->right-r->left,r->bottom-r->top,TRUE); return S_OK; }
  STDMETHODIMP IsPageDirty() override { return S_FALSE; }
  STDMETHODIMP Apply() override {
    if(!window)return S_OK;
    LocalistCaptureState state; if(!ReadLocalistCaptureState(state)||!state.enabled)return E_FAIL;
    wchar_t buffer[32]; GetWindowTextW(zoom,buffer,32); const int zoom_value=_wtoi(buffer); GetWindowTextW(bitrate,buffer,32); const int rate=_wtoi(buffer);
    if(zoom_value<100||zoom_value>state.max_zoom||rate<250||rate>12000){SetWindowTextW(message,Text(L"زوم مجاز و بیت‌ریت بین 250 تا 12000 وارد کنید.",L"Enter a supported zoom and bitrate (250-12000 kbps)."));return E_INVALIDARG;}
    char json[512]; sprintf_s(json,"{\"width\":%d,\"fps\":%d,\"bitrate\":%d,\"zoom\":%.2f,\"noise\":%s,\"echo\":%s,\"gain\":%s,\"torch\":%s,\"microphone\":%d}",Value(resolution),Value(fps),rate,zoom_value/100.0,SendMessageW(noise,BM_GETCHECK,0,0)==BST_CHECKED?"true":"false",SendMessageW(echo,BM_GETCHECK,0,0)==BST_CHECKED?"true":"false",SendMessageW(gain,BM_GETCHECK,0,0)==BST_CHECKED?"true":"false",SendMessageW(torch,BM_GETCHECK,0,0)==BST_CHECKED?"true":"false",Value(microphone));
    const bool sent=SubmitLocalistCaptureCommand(json); SetWindowTextW(message,sent?Text(L"درخواست ارسال شد؛ برای خواندن نتیجه، پنل را دوباره باز کنید.",L"Request sent. Reopen this panel to read the sender's current settings."):Text(L"فرستنده در دسترس نیست یا تغییر دیگری در انتظار است.",L"Sender is unavailable or another change is pending."));return sent?S_OK:E_FAIL;
  }
  STDMETHODIMP Help(LPCOLESTR) override { return E_NOTIMPL; }
  STDMETHODIMP TranslateAccelerator(MSG* msg) override { return window && IsDialogMessageW(window,msg) ? S_OK : S_FALSE; }
};
}
HRESULT CreateLocalistControlsPage(REFIID iid, void** out) { auto* page = new ControlsPage(); const auto hr=page->QueryInterface(iid,out); page->Release(); return hr; }
