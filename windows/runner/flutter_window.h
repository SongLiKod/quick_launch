#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts a Flutter view and handles WM_HOTKEY messages.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Sets a file path received from command-line args to be processed after
  // the Flutter engine is ready.
  void setPendingFilePath(const std::string& path) { pending_file_path_ = path; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // MethodChannel for forwarding WM_HOTKEY events to the Dart side.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      hotkey_channel_;

  // MethodChannel for receiving settings commands from the Dart side.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      settings_channel_;

  // MethodChannel for forwarding file paths (from WM_COPYDATA) to Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      files_channel_;

  // When true, the close button hides the window instead of closing it.
  bool minimize_to_tray_ = false;

  // When true, skip the initial Show() call on startup.
  bool hide_on_startup_ = false;

  // Handle to the currently set custom icon (for cleanup).
  HICON custom_icon_ = nullptr;

  // File path received from command-line --add-file (processed after engine init).
  std::string pending_file_path_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
