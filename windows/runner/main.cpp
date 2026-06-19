#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

// Window class name used by Win32Window (defined in win32_window.cpp).
constexpr const wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Parse command-line args for --add-file <path>
  std::vector<std::string> args = GetCommandLineArguments();
  std::string pendingPath;
  for (size_t i = 0; i + 1 < args.size(); ++i) {
    if (args[i] == "--add-file" && !args[i + 1].empty()) {
      pendingPath = args[i + 1];
      break;
    }
  }

  // Single-instance check via named mutex.
  HANDLE hMutex = CreateMutexW(nullptr, FALSE, L"Global\\QuickLaunch_SingleInstance");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is running. Forward the file path if present.
    if (!pendingPath.empty()) {
      HWND hwnd = FindWindowW(kWindowClass, nullptr);
      if (hwnd != nullptr) {
        // Bring the existing window to foreground.
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);

        // Send the path via WM_COPYDATA.
        COPYDATASTRUCT cds;
        cds.dwData = 0;  // custom identifier
        cds.cbData = static_cast<DWORD>(pendingPath.size() + 1);
        cds.lpData = const_cast<char*>(pendingPath.c_str());
        SendMessage(hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
      }
    }
    CloseHandle(hMutex);
    return 0;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(args));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"quick_launch", origin, size)) {
    CloseHandle(hMutex);
    return EXIT_FAILURE;
  }

  // Store the pending path so the window can handle it after initialization.
  window.setPendingFilePath(pendingPath);

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  CloseHandle(hMutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
