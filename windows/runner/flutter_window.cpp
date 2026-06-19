#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"

// Helper: show a Windows balloon notification from the system tray area.
// Uses a temporary NOTIFYICONDATA so it works even when the main window is hidden.
static void ShowBalloon(HWND hwnd, const std::string& title,
                         const std::string& message) {
  // Convert UTF-8 to wide string
  auto toWide = [](const std::string& s) -> std::wstring {
    int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    if (len <= 0) return L"";
    std::wstring ws(len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, ws.data(), len);
    return ws;
  };

  NOTIFYICONDATAW nid = {sizeof(NOTIFYICONDATAW)};
  nid.hWnd = hwnd;
  nid.uID = 9999;
  nid.uFlags = NIF_INFO | NIF_ICON | NIF_MESSAGE;
  nid.uCallbackMessage = WM_APP + 1;
  nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  nid.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
  nid.uTimeout = 3000;

  std::wstring wtitle = toWide(title);
  std::wstring wmsg = toWide(message);
  wcsncpy_s(nid.szInfoTitle, wtitle.c_str(), _TRUNCATE);
  wcsncpy_s(nid.szInfo, wmsg.c_str(), _TRUNCATE);

  Shell_NotifyIconW(NIM_ADD, &nid);
  // Balloon shows automatically on NIM_ADD with NIF_INFO.
  // Remove the temporary icon so it doesn't persist.
  Shell_NotifyIconW(NIM_DELETE, &nid);
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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

  // Create the method channel that forwards WM_HOTKEY to the Dart side.
  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "quick_launch/hotkey",
          &flutter::StandardMethodCodec::GetInstance());

  // Create the method channel for settings commands from the Dart side.
  settings_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "quick_launch/settings",
          &flutter::StandardMethodCodec::GetInstance());

  settings_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto method = call.method_name();
        if (method == "setMinimizeToTray") {
          const auto& args = *call.arguments();
          if (std::holds_alternative<bool>(args)) {
            minimize_to_tray_ = std::get<bool>(args);
          }
          result->Success();
        } else if (method == "setHideOnStartup") {
          const auto& args = *call.arguments();
          if (std::holds_alternative<bool>(args)) {
            hide_on_startup_ = std::get<bool>(args);
          }
          result->Success();
        } else if (method == "showBalloon") {
          const auto& args = *call.arguments();
          if (std::holds_alternative<flutter::EncodableMap>(args)) {
            const auto& map = std::get<flutter::EncodableMap>(args);
            auto title_it = map.find(flutter::EncodableValue("title"));
            auto msg_it = map.find(flutter::EncodableValue("message"));
            if (title_it != map.end() && msg_it != map.end() &&
                std::holds_alternative<std::string>(title_it->second) &&
                std::holds_alternative<std::string>(msg_it->second)) {
              ShowBalloon(GetHandle(),
                          std::get<std::string>(title_it->second),
                          std::get<std::string>(msg_it->second));
            }
          }
          result->Success();
        } else if (method == "setAppIcon") {
          const auto& args = *call.arguments();
          if (std::holds_alternative<std::string>(args)) {
            const auto pathUtf8 = std::get<std::string>(args);
            if (!pathUtf8.empty()) {
              int len = MultiByteToWideChar(CP_UTF8, 0, pathUtf8.c_str(), -1, nullptr, 0);
              if (len > 0) {
                std::wstring wpath(len, L'\0');
                MultiByteToWideChar(CP_UTF8, 0, pathUtf8.c_str(), -1, wpath.data(), len);
                // Try loading at system default size first
                HICON hIcon = static_cast<HICON>(LoadImageW(
                    nullptr, wpath.c_str(), IMAGE_ICON, 0, 0,
                    LR_LOADFROMFILE | LR_DEFAULTSIZE));
                // If that fails, try 32x32 for ICON_BIG
                if (hIcon == nullptr) {
                  hIcon = static_cast<HICON>(LoadImageW(
                      nullptr, wpath.c_str(), IMAGE_ICON, 32, 32,
                      LR_LOADFROMFILE));
                }
                // If still fails, try 16x16 for ICON_SMALL
                if (hIcon == nullptr) {
                  hIcon = static_cast<HICON>(LoadImageW(
                      nullptr, wpath.c_str(), IMAGE_ICON, 16, 16,
                      LR_LOADFROMFILE));
                }
                if (hIcon != nullptr) {
                  HWND hwnd = GetHandle();
                  if (custom_icon_ != nullptr) {
                    DestroyIcon(custom_icon_);
                  }
                  custom_icon_ = hIcon;
                  SendMessage(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(hIcon));
                  SendMessage(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(hIcon));
                  result->Success(flutter::EncodableValue(true));
                  return;
                }
              }
            }
          }
          result->Success(flutter::EncodableValue(false));
        } else if (method == "runAsAdmin") {
          const auto& args = *call.arguments();
          if (std::holds_alternative<std::string>(args)) {
            const auto pathUtf8 = std::get<std::string>(args);
            if (!pathUtf8.empty()) {
              int len = MultiByteToWideChar(CP_UTF8, 0, pathUtf8.c_str(), -1, nullptr, 0);
              if (len > 0) {
                std::wstring wpath(len, L'\0');
                MultiByteToWideChar(CP_UTF8, 0, pathUtf8.c_str(), -1, wpath.data(), len);

                SHELLEXECUTEINFOW sei = {sizeof(SHELLEXECUTEINFOW)};
                sei.hwnd = GetHandle();
                sei.lpVerb = L"runas";
                sei.lpFile = wpath.c_str();
                sei.nShow = SW_SHOWNORMAL;

                if (ShellExecuteExW(&sei)) {
                  result->Success(flutter::EncodableValue(true));
                  return;
                }
              }
            }
          }
          result->Success(flutter::EncodableValue(false));
        } else if (method == "requestExit") {
          // Called from tray "Exit" — force close regardless of minimize setting.
          minimize_to_tray_ = false;
          PostQuitMessage(0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!hide_on_startup_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  // Clean up custom icon handle
  if (custom_icon_ != nullptr) {
    DestroyIcon(custom_icon_);
    custom_icon_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_HOTKEY:
      // Forward the hotkey ID (wParam) to the Dart side via MethodChannel.
      if (hotkey_channel_ != nullptr) {
        hotkey_channel_->InvokeMethod(
            "onHotkey",
            std::make_unique<flutter::EncodableValue>(
                flutter::EncodableValue(static_cast<int>(wparam))));
        return 0;
      }
      break;
    case WM_CLOSE:
      if (minimize_to_tray_) {
        // Hide the window instead of closing it.
        ShowWindow(hwnd, SW_HIDE);
        return 0;  // Prevent default DestroyWindow.
      }
      // Otherwise fall through to default handling (destroy).
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
