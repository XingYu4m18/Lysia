#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <commdlg.h>
#include "resource.h"
#include "audio_decode.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

namespace {
constexpr UINT kTray = WM_APP + 10;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
std::wstring WideText(const std::string& s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring text(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), text.data(), n);
  return text;
}
std::string NarrowText(const wchar_t* s) {
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
  std::string text(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s, -1, text.data(), n, nullptr, nullptr);
  if (!text.empty()) text.pop_back();
  return text;
}
}

void FlutterWindow::UpdateTray(const std::wstring& text) {
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon); icon.hWnd = GetHandle(); icon.uID = 1;
  icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  icon.uCallbackMessage = kTray;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon.szTip, listening_ ? L"聆汐 · 自动识曲中" : L"聆汐 · 已暂停");
  if (!text.empty()) {
    icon.uFlags |= NIF_INFO;
    wcsncpy_s(icon.szInfo, text.c_str(), _TRUNCATE);
    wcscpy_s(icon.szInfoTitle, L"聆汐 · 识别到歌曲");
    icon.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
  }
  tray_added_ = Shell_NotifyIconW(tray_added_ ? NIM_MODIFY : NIM_ADD, &icon) != FALSE;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      flutter_controller_->engine()->messenger(), "tingjian/native", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<Value>& call, std::unique_ptr<flutter::MethodResult<Value>> result) {
    const auto& method = call.method_name();
    if (method == "devices") {
      flutter::EncodableList list;
      for (const auto& device : AudioCapture::Devices()) list.push_back(Value(Map{{Value("id"), Value(device.id)}, {Value("name"), Value(device.name)}}));
      result->Success(Value(list));
    } else if (method == "captureStart") {
      const auto* id = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      capture_.Start(id ? *id : ""); result->Success();
    } else if (method == "captureStop") {
      capture_.Stop(); result->Success();
    } else if (method == "captureStatus") {
      auto state = capture_.State();
      result->Success(Value(Map{{Value("running"), Value(state.running)}, {Value("samples"), Value(state.samples)},
        {Value("level"), Value(state.level)}, {Value("error"), Value(state.error)}, {Value("device"), Value(state.device)},
        {Value("sequence"), Value(static_cast<int64_t>(state.sequence))}}));
    } else if (method == "snapshot") {
      auto bytes = capture_.Snapshot(6); result->Success(Value(bytes));
    } else if (method == "setListening") {
      const auto* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      listening_ = value && *value; UpdateTray(); result->Success();
    } else if (method == "notify") {
      const auto* text = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (text) UpdateTray(WideText(*text)); result->Success();
    } else if (method == "openUrl") {
      const auto* url = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (url && url->rfind("https://", 0) == 0) {
        auto status = reinterpret_cast<INT_PTR>(ShellExecuteW(GetHandle(), L"open", WideText(*url).c_str(), nullptr, nullptr, SW_SHOWNORMAL));
        if (status > 32) result->Success(); else result->Error("OPEN_FAILED", "无法打开浏览器");
      } else result->Error("URL", "仅支持 HTTPS 链接");
    } else if (method == "decodeAudio") {
      const auto* path = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!path || decode_result_) { result->Error("BUSY", "音频解码器正在忙碌"); return; }
      if (decode_worker_.joinable()) decode_worker_.join();
      const auto file = WideText(*path);const HWND window=GetHandle();
      decode_result_=std::move(result);decoded_audio_.clear();decode_error_.clear();
      decode_worker_=std::thread([this,file,window](){
        try {decoded_audio_=DecodeAudioFile(file);} catch(const std::exception& e){decode_error_=e.what();}
        PostMessage(window,WM_APP+11,0,0);
      });
    } else if (method == "chooseAudio") {
      wchar_t path[32768]{};
      OPENFILENAMEW dialog{}; dialog.lStructSize = sizeof(dialog); dialog.hwndOwner = GetHandle();
      dialog.lpstrFilter = L"音频文件\0*.wav;*.mp3;*.flac;*.ogg;*.oga;*.aac;*.m4a;*.wma;*.mp4\0所有文件\0*.*\0\0"; dialog.lpstrFile = path; dialog.nMaxFile = 32768;
      dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
      if (GetOpenFileNameW(&dialog)) result->Success(Value(NarrowText(path))); else result->Success();
    } else if (method == "quit") {
      force_quit_ = true; result->Success(); PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else result->NotImplemented();
  });
  UpdateTray();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (decode_worker_.joinable()) decode_worker_.join();
  decode_result_=nullptr;
  capture_.Stop();
  NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = GetHandle(); icon.uID = 1;
  Shell_NotifyIconW(NIM_DELETE, &icon);
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_APP+11) {
    if (decode_worker_.joinable()) decode_worker_.join();
    if (decode_result_) {
      if (decode_error_.empty()) decode_result_->Success(Value(decoded_audio_));
      else decode_result_->Error("DECODE",decode_error_);
      decode_result_=nullptr;decoded_audio_.clear();
    }
    return 0;
  }
  if (message == WM_CLOSE && !force_quit_) { ShowWindow(hwnd, SW_HIDE); return 0; }
  if (message == WM_GETMINMAXINFO) {
    auto info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize = {900, 640};
    return 0;
  }
  if (message == RegisterWindowMessageW(L"TaskbarCreated")) { tray_added_ = false; UpdateTray(); }
  if (message == kTray) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK || lparam == NIN_BALLOONUSERCLICK) {
      ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd);
    } else if (lparam == WM_RBUTTONUP) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, 1, L"打开聆汐");
      AppendMenuW(menu, MF_STRING, 2, listening_ ? L"暂停自动识曲" : L"开始自动识曲");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr); AppendMenuW(menu, MF_STRING, 3, L"退出");
      POINT point; GetCursorPos(&point); SetForegroundWindow(hwnd);
      int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (selected == 1) { ShowWindow(hwnd, SW_RESTORE); SetForegroundWindow(hwnd); }
      if (selected == 2 && channel_) channel_->InvokeMethod("trayToggle", nullptr);
      if (selected == 3) { force_quit_ = true; PostMessage(hwnd, WM_CLOSE, 0, 0); }
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
