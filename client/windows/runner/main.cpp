#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

class ScopedComInitializer {
 public:
  ScopedComInitializer()
      : hr_(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ScopedComInitializer() {
    if (SUCCEEDED(hr_)) {
      ::CoUninitialize();
    }
  }
  ScopedComInitializer(const ScopedComInitializer&) = delete;
  ScopedComInitializer& operator=(const ScopedComInitializer&) = delete;

 private:
  HRESULT hr_;
};

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}
  ~ScopedHandle() {
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      ::CloseHandle(handle_);
    }
  }
  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;
  explicit operator bool() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }

 private:
  HANDLE handle_;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ScopedHandle instance_mutex(::CreateMutexW(
      nullptr, TRUE, L"Local\\HermesMediaClient_SingleInstance_v1"));
  if (instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (HWND existing =
            ::FindWindowW(L"HERMES_MEDIA_CLIENT_WINDOW", nullptr)) {
      DWORD existing_pid = 0;
      ::GetWindowThreadProcessId(existing, &existing_pid);
      if (existing_pid != 0) {
        ::AllowSetForegroundWindow(existing_pid);
      }
      const UINT activate_msg = ::RegisterWindowMessageW(
          L"HermesMediaClient_ActivateInstance");
      if (activate_msg != 0) {
        ::PostMessageW(existing, activate_msg, 0, 0);
      }
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ScopedComInitializer com;

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1360, 820);
  if (!window.Create(L"Hermes", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  return EXIT_SUCCESS;
}
