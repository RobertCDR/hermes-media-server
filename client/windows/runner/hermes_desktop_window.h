#ifndef RUNNER_HERMES_DESKTOP_WINDOW_H_
#define RUNNER_HERMES_DESKTOP_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// Native Windows desktop integration over "hermes.window/control":
// - Frameless Windows 11 window chrome (rounded corners, Aero Snap, DPI-aware borders)
// - True borderless monitor fullscreen
// - System tray icon with quick playback menu & close-to-tray
// - Mouse4/Mouse5 hardware Back/Forward navigation
// - Subtle always-on-top no-activate media flyout
class HermesDesktopWindow {
 public:
  static constexpr UINT kWmTrayIcon = WM_APP + 0x102;

  HermesDesktopWindow(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~HermesDesktopWindow();

  HermesDesktopWindow(const HermesDesktopWindow&) = delete;
  HermesDesktopWindow& operator=(const HermesDesktopWindow&) = delete;

  // Intercepts window messages from FlutterWindow. Sets |handled| = true when
  // the message was fully handled and should not pass to DefWindowProc.
  LRESULT HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam, bool* handled) noexcept;

  void Shutdown();

 private:
  struct FlyoutState;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ConfigureFrameStyles();
  void SetCornerPreference(bool rounded);
  void SetFullscreen(bool fullscreen);
  void RestoreFromTray();
  void ShowTrayMenu();
  void AddTrayIcon();
  void UpdateTrayTooltip();
  void RemoveTrayIcon();
  void EmitWindowState();
  void EmitSimpleEvent(const char* method, const std::string& arg);
  flutter::EncodableMap ReadBoundsMap() const;
  bool ApplyBounds(const flutter::EncodableMap& args);

  void EnsureFlyoutWindow();
  void ShowMediaFlyout(const std::string& title, const std::string& artist,
                       bool is_playing, std::vector<uint8_t> art_bgra,
                       int art_width, int art_height);
  void HideMediaFlyout();
  void DestroyFlyoutWindow();

  static LRESULT CALLBACK FlyoutWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam) noexcept;
  LRESULT HandleFlyoutMessage(HWND hwnd, UINT message, WPARAM wparam,
                              LPARAM lparam) noexcept;
  void PaintFlyout(HWND hwnd);

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<FlyoutState> flyout_;

  bool is_fullscreen_ = false;
  bool last_maximized_ = false;
  bool close_to_tray_ = true;
  bool force_quit_ = false;
  bool tray_added_ = false;
  bool tray_is_playing_ = false;
  std::wstring tray_track_label_;

  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};
};

#endif  // RUNNER_HERMES_DESKTOP_WINDOW_H_
