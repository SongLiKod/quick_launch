#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
