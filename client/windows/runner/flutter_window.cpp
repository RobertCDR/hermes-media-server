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

  desktop_window_ = std::make_unique<HermesDesktopWindow>(GetHandle());
  desktop_window_->InitializeFrame();

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    desktop_window_->Shutdown();
    desktop_window_.reset();
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  smtc_bridge_ = std::make_unique<HermesSmtcBridge>(
      GetHandle(), flutter_controller_->engine()->messenger());
  desktop_window_->AttachChannel(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (desktop_window_) {
    desktop_window_->Shutdown();
    desktop_window_.reset();
  }
  if (smtc_bridge_) {
    smtc_bridge_->Shutdown();
    smtc_bridge_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (desktop_window_) {
    bool handled = false;
    LRESULT desktop_result = desktop_window_->HandleWindowMessage(
        hwnd, message, wparam, lparam, &handled);
    if (handled) {
      return desktop_result;
    }
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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case HermesSmtcBridge::kWmButtonPressed:
      if (smtc_bridge_) {
        smtc_bridge_->HandleWindowMessage(wparam);
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
