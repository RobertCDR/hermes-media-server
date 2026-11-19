#include "hermes_desktop_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cstring>
#include <utility>

#include "resource.h"

namespace {

constexpr DWORD kDwmAttrUseImmersiveDarkMode = 20;
constexpr DWORD kDwmAttrCornerPreference = 33;
constexpr DWORD kDwmCornerDoNotRound = 1;
constexpr DWORD kDwmCornerRound = 2;
constexpr DWORD kDwmAttrBorderColor = 34;

constexpr const wchar_t kFlyoutWindowClass[] = L"HERMES_MEDIA_FLYOUT_WND";
constexpr UINT_PTR kFlyoutHideTimerId = 1;
constexpr UINT kFlyoutHideDelayMs = 2800;

constexpr UINT kTrayIconId = 1;
constexpr UINT kMenuTrackHeader = 1000;
constexpr UINT kMenuPlayPause = 1001;
constexpr UINT kMenuNext = 1002;
constexpr UINT kMenuPrevious = 1003;
constexpr UINT kMenuShow = 1004;
constexpr UINT kMenuQuit = 1005;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return L"";
  }
  const int required = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (required <= 0) {
    return L"";
  }
  std::wstring wide(static_cast<size_t>(required), L'\0');
  const int converted = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), wide.data(),
      required);
  if (converted <= 0) {
    return L"";
  }
  return wide;
}

std::string ReadStringArg(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return "";
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return "";
}

bool ReadBoolArg(const flutter::EncodableMap& args, const char* key,
                 bool fallback = false) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return fallback;
}

std::optional<int> ReadIntArg(const flutter::EncodableMap& args,
                              const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::nullopt;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return static_cast<int>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*i64);
  }
  if (const auto* dbl = std::get_if<double>(&it->second)) {
    return static_cast<int>(*dbl);
  }
  return std::nullopt;
}

double GetScaleForHwnd(HWND hwnd) {
  HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    return 1.0;
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
}

int ScalePx(int logical_px, double scale) {
  return static_cast<int>(logical_px * scale + 0.5);
}

int GetDpiMetric(HWND hwnd, int index) {
  using GetSystemMetricsForDpiFn = int(WINAPI*)(int, UINT);
  static auto get_metric_for_dpi = reinterpret_cast<GetSystemMetricsForDpiFn>(
      ::GetProcAddress(::GetModuleHandleW(L"user32.dll"),
                       "GetSystemMetricsForDpi"));
  if (get_metric_for_dpi != nullptr) {
    HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    const UINT dpi = monitor != nullptr
                         ? FlutterDesktopGetDpiForMonitor(monitor)
                         : 96;
    return get_metric_for_dpi(index, dpi > 0 ? dpi : 96);
  }
  return ::GetSystemMetrics(index);
}

struct FlyoutLayout {
  RECT accent{};
  RECT art{};
  RECT title{};
  RECT artist{};
  RECT buttons[3]{};
};

FlyoutLayout BuildFlyoutLayout(int width, int height, double scale) {
  FlyoutLayout layout;
  const int accent_w = (std::max)(2, ScalePx(3, scale));
  layout.accent = {0, 0, accent_w, height};

  const int art_size = ScalePx(48, scale);
  const int art_x = ScalePx(13, scale);
  const int art_y = (height - art_size) / 2;
  layout.art = {art_x, art_y, art_x + art_size, art_y + art_size};

  const int btn_size = ScalePx(26, scale);
  const int btn_gap = ScalePx(4, scale);
  const int right_pad = ScalePx(12, scale);
  const int btn_y = (height - btn_size) / 2;
  const int buttons_total = btn_size * 3 + btn_gap * 2;
  const int btn_start_x = width - right_pad - buttons_total;
  for (int i = 0; i < 3; ++i) {
    const int x = btn_start_x + i * (btn_size + btn_gap);
    layout.buttons[i] = {x, btn_y, x + btn_size, btn_y + btn_size};
  }

  const int text_left = layout.art.right + ScalePx(11, scale);
  const int text_right = (std::max)(text_left + 10, btn_start_x - ScalePx(8, scale));
  layout.title = {text_left, ScalePx(16, scale), text_right, ScalePx(38, scale)};
  layout.artist = {text_left, ScalePx(39, scale), text_right, ScalePx(58, scale)};
  return layout;
}

void DrawPlayIcon(HDC hdc, RECT rect, COLORREF color) {
  const int cx = (rect.left + rect.right) / 2;
  const int cy = (rect.top + rect.bottom) / 2;
  const int half =
      (std::max)(4, static_cast<int>(rect.right - rect.left) / 5);
  POINT pts[3] = {
      {cx - half / 2 - 1, cy - half},
      {cx + half, cy},
      {cx - half / 2 - 1, cy + half},
  };
  HBRUSH brush = ::CreateSolidBrush(color);
  HPEN pen = ::CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_brush = ::SelectObject(hdc, brush);
  HGDIOBJ old_pen = ::SelectObject(hdc, pen);
  ::Polygon(hdc, pts, 3);
  ::SelectObject(hdc, old_brush);
  ::SelectObject(hdc, old_pen);
  ::DeleteObject(brush);
  ::DeleteObject(pen);
}

void DrawPauseIcon(HDC hdc, RECT rect, COLORREF color) {
  const int cx = (rect.left + rect.right) / 2;
  const int cy = (rect.top + rect.bottom) / 2;
  const int bar_h =
      (std::max)(6, static_cast<int>(rect.bottom - rect.top) * 2 / 5);
  const int bar_w = (std::max)(2, bar_h / 3);
  const int gap = (std::max)(2, bar_w);
  HBRUSH brush = ::CreateSolidBrush(color);
  RECT left_bar{cx - gap / 2 - bar_w, cy - bar_h / 2, cx - gap / 2,
                cy + bar_h / 2};
  RECT right_bar{cx + gap / 2, cy - bar_h / 2, cx + gap / 2 + bar_w,
                 cy + bar_h / 2};
  ::FillRect(hdc, &left_bar, brush);
  ::FillRect(hdc, &right_bar, brush);
  ::DeleteObject(brush);
}

void DrawSkipIcon(HDC hdc, RECT rect, COLORREF color, bool next) {
  const int cx = (rect.left + rect.right) / 2;
  const int cy = (rect.top + rect.bottom) / 2;
  const int r = (std::max)(4, static_cast<int>(rect.right - rect.left) / 5);
  const int bar_w = (std::max)(2, r / 2);

  HBRUSH brush = ::CreateSolidBrush(color);
  HPEN pen = ::CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_brush = ::SelectObject(hdc, brush);
  HGDIOBJ old_pen = ::SelectObject(hdc, pen);

  if (next) {
    POINT pts[3] = {
        {cx - r, cy - r + 1},
        {cx + r / 3, cy},
        {cx - r, cy + r - 1},
    };
    ::Polygon(hdc, pts, 3);
    RECT bar{cx + r / 2, cy - r + 1, cx + r / 2 + bar_w, cy + r};
    ::FillRect(hdc, &bar, brush);
  } else {
    RECT bar{cx - r / 2 - bar_w, cy - r + 1, cx - r / 2, cy + r};
    ::FillRect(hdc, &bar, brush);
    POINT pts[3] = {
        {cx + r, cy - r + 1},
        {cx - r / 3, cy},
        {cx + r, cy + r - 1},
    };
    ::Polygon(hdc, pts, 3);
  }

  ::SelectObject(hdc, old_brush);
  ::SelectObject(hdc, old_pen);
  ::DeleteObject(brush);
  ::DeleteObject(pen);
}

}  // namespace

struct HermesDesktopWindow::FlyoutState {
  HWND hwnd = nullptr;
  std::wstring title;
  std::wstring artist;
  bool is_playing = false;
  std::vector<uint8_t> art_bgra;
  int art_width = 0;
  int art_height = 0;
  double scale = 1.0;
  int hover_button = -1;
  bool tracking_leave = false;
};

HermesDesktopWindow::HermesDesktopWindow(HWND hwnd,
                                         flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd), flyout_(std::make_unique<FlyoutState>()) {
  if (messenger != nullptr) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "hermes.window/control",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](
            const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result) { HandleMethodCall(call, std::move(result)); });
  }

  if (hwnd_ != nullptr && ::IsWindow(hwnd_)) {
    last_maximized_ = ::IsZoomed(hwnd_) != FALSE;
    ConfigureFrameStyles();
    AddTrayIcon();
  }
}

HermesDesktopWindow::~HermesDesktopWindow() { Shutdown(); }

void HermesDesktopWindow::Shutdown() {
  DestroyFlyoutWindow();
  RemoveTrayIcon();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
}

void HermesDesktopWindow::ConfigureFrameStyles() {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  BOOL dark = TRUE;
  ::DwmSetWindowAttribute(hwnd_, kDwmAttrUseImmersiveDarkMode, &dark,
                          sizeof(dark));
  SetCornerPreference(true);
  MARGINS margins = {0, 0, 0, 1};
  ::DwmExtendFrameIntoClientArea(hwnd_, &margins);
  ::SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOOWNERZORDER);
}

void HermesDesktopWindow::SetCornerPreference(bool rounded) {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  const DWORD pref = rounded ? kDwmCornerRound : kDwmCornerDoNotRound;
  ::DwmSetWindowAttribute(hwnd_, kDwmAttrCornerPreference, &pref, sizeof(pref));
}

void HermesDesktopWindow::SetFullscreen(bool fullscreen) {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_) || fullscreen == is_fullscreen_) {
    return;
  }

  if (fullscreen) {
    saved_style_ = ::GetWindowLongPtrW(hwnd_, GWL_STYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(hwnd_, &saved_placement_);

    MONITORINFO mi{sizeof(mi)};
    if (::GetMonitorInfoW(
            ::MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST), &mi)) {
      is_fullscreen_ = true;
      SetCornerPreference(false);
      ::SetWindowLongPtrW(
          hwnd_, GWL_STYLE,
          (saved_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW)) |
              WS_POPUP | WS_VISIBLE);
      ::SetWindowPos(hwnd_, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                     mi.rcMonitor.right - mi.rcMonitor.left,
                     mi.rcMonitor.bottom - mi.rcMonitor.top,
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    }
  } else {
    is_fullscreen_ = false;
    const LONG_PTR restore_style =
        saved_style_ != 0
            ? saved_style_
            : static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW | WS_VISIBLE);
    ::SetWindowLongPtrW(hwnd_, GWL_STYLE, restore_style);
    SetCornerPreference(true);
    if (saved_placement_.length == sizeof(WINDOWPLACEMENT)) {
      ::SetWindowPlacement(hwnd_, &saved_placement_);
    }
    ::SetWindowPos(hwnd_, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }

  EmitWindowState();
}

void HermesDesktopWindow::RestoreFromTray() {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  ::ShowWindow(hwnd_, SW_SHOW);
  if (::IsIconic(hwnd_)) {
    ::ShowWindow(hwnd_, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd_);
}

void HermesDesktopWindow::AddTrayIcon() {
  if (tray_added_ || hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kWmTrayIcon;
  nid.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr),
                          MAKEINTRESOURCEW(IDI_APP_ICON));
  ::wcsncpy_s(nid.szTip, L"Hermes", _TRUNCATE);
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &nid) != FALSE;
}

void HermesDesktopWindow::UpdateTrayTooltip() {
  if (!tray_added_ || hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_TIP;
  std::wstring tip =
      tray_track_label_.empty() ? L"Hermes" : (tray_track_label_ + L" — Hermes");
  ::wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);
  ::Shell_NotifyIconW(NIM_MODIFY, &nid);
}

void HermesDesktopWindow::RemoveTrayIcon() {
  if (!tray_added_ || hwnd_ == nullptr) {
    return;
  }
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void HermesDesktopWindow::ShowTrayMenu() {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  if (!tray_track_label_.empty()) {
    ::AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, kMenuTrackHeader,
                  tray_track_label_.c_str());
    ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  }
  ::AppendMenuW(menu, MF_STRING, kMenuPlayPause,
                tray_is_playing_ ? L"Pause" : L"Play");
  ::AppendMenuW(menu, MF_STRING, kMenuNext, L"Next track");
  ::AppendMenuW(menu, MF_STRING, kMenuPrevious, L"Previous track");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuShow, L"Show Hermes");
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit Hermes");

  POINT cursor{};
  ::GetCursorPos(&cursor);
  ::SetForegroundWindow(hwnd_);
  const UINT cmd = static_cast<UINT>(::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, hwnd_, nullptr));
  ::PostMessageW(hwnd_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);

  switch (cmd) {
    case kMenuShow:
      RestoreFromTray();
      break;
    case kMenuPlayPause:
      EmitSimpleEvent("onTrayAction", "playPause");
      break;
    case kMenuNext:
      EmitSimpleEvent("onTrayAction", "next");
      break;
    case kMenuPrevious:
      EmitSimpleEvent("onTrayAction", "previous");
      break;
    case kMenuQuit:
      force_quit_ = true;
      EmitSimpleEvent("onTrayAction", "quit");
      break;
    default:
      break;
  }
}

void HermesDesktopWindow::EmitWindowState() {
  if (!channel_ || hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("isMaximized")] =
      flutter::EncodableValue(::IsZoomed(hwnd_) != FALSE);
  payload[flutter::EncodableValue("isFullscreen")] =
      flutter::EncodableValue(is_fullscreen_);
  channel_->InvokeMethod("onWindowStateChanged",
                         std::make_unique<flutter::EncodableValue>(payload));
}

void HermesDesktopWindow::EmitSimpleEvent(const char* method,
                                          const std::string& arg) {
  if (!channel_) {
    return;
  }
  channel_->InvokeMethod(method,
                         std::make_unique<flutter::EncodableValue>(arg));
}

flutter::EncodableMap HermesDesktopWindow::ReadBoundsMap() const {
  flutter::EncodableMap map;
  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return map;
  }
  WINDOWPLACEMENT wp{sizeof(WINDOWPLACEMENT)};
  if (!::GetWindowPlacement(hwnd_, &wp)) {
    return map;
  }
  const RECT& r = wp.rcNormalPosition;
  map[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int>(r.left));
  map[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int>(r.top));
  map[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int>(r.right - r.left));
  map[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int>(r.bottom - r.top));
  map[flutter::EncodableValue("isMaximized")] =
      flutter::EncodableValue(::IsZoomed(hwnd_) != FALSE);
  return map;
}

bool HermesDesktopWindow::ApplyBounds(const flutter::EncodableMap& args) {
  if (hwnd_ == nullptr || !::IsWindow(hwnd_) || is_fullscreen_) {
    return false;
  }
  const auto x = ReadIntArg(args, "x");
  const auto y = ReadIntArg(args, "y");
  const auto width = ReadIntArg(args, "width");
  const auto height = ReadIntArg(args, "height");
  const bool maximized = ReadBoolArg(args, "isMaximized", false);

  if (x.has_value() && y.has_value() && width.has_value() && height.has_value() &&
      *width >= 600 && *height >= 400) {
    RECT rc{*x, *y, *x + *width, *y + *height};
    if (::MonitorFromRect(&rc, MONITOR_DEFAULTTONULL) != nullptr) {
      ::SetWindowPos(hwnd_, nullptr, rc.left, rc.top, rc.right - rc.left,
                     rc.bottom - rc.top, SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }
  if (maximized) {
    ::ShowWindow(hwnd_, SW_MAXIMIZE);
  }
  EmitWindowState();
  return true;
}

void HermesDesktopWindow::EnsureFlyoutWindow() {
  if (flyout_->hwnd != nullptr && ::IsWindow(flyout_->hwnd)) {
    return;
  }
  static bool registered = false;
  if (!registered) {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = HermesDesktopWindow::FlyoutWndProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kFlyoutWindowClass;
    ::RegisterClassExW(&wc);
    registered = true;
  }

  flyout_->hwnd = ::CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
      kFlyoutWindowClass, L"", WS_POPUP, 0, 0, 304, 74, nullptr, nullptr,
      ::GetModuleHandleW(nullptr), this);

  if (flyout_->hwnd != nullptr) {
    ::SetLayeredWindowAttributes(flyout_->hwnd, 0, 242, LWA_ALPHA);
    const DWORD round_pref = kDwmCornerRound;
    ::DwmSetWindowAttribute(flyout_->hwnd, kDwmAttrCornerPreference,
                            &round_pref, sizeof(round_pref));
    const COLORREF border_color = RGB(52, 52, 62);
    ::DwmSetWindowAttribute(flyout_->hwnd, kDwmAttrBorderColor, &border_color,
                            sizeof(border_color));
  }
}

void HermesDesktopWindow::ShowMediaFlyout(const std::string& title,
                                          const std::string& artist,
                                          bool is_playing,
                                          std::vector<uint8_t> art_bgra,
                                          int art_width, int art_height) {
  EnsureFlyoutWindow();
  if (flyout_->hwnd == nullptr) {
    return;
  }

  flyout_->title = Utf8ToWide(title);
  flyout_->artist = Utf8ToWide(artist);
  flyout_->is_playing = is_playing;
  flyout_->art_bgra = std::move(art_bgra);
  flyout_->art_width = art_width;
  flyout_->art_height = art_height;

  const POINT origin{0, 0};
  HMONITOR monitor = ::MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{sizeof(mi)};
  RECT work{0, 0, 1280, 720};
  if (::GetMonitorInfoW(monitor, &mi)) {
    work = mi.rcWork;
  }
  const UINT dpi = monitor != nullptr ? FlutterDesktopGetDpiForMonitor(monitor) : 96;
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  flyout_->scale = scale;

  const int w = ScalePx(304, scale);
  const int h = ScalePx(74, scale);
  const int x = work.left + ScalePx(22, scale);
  const int y = work.top + ScalePx(22, scale);

  ::SetWindowPos(flyout_->hwnd, HWND_TOPMOST, x, y, w, h,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  ::InvalidateRect(flyout_->hwnd, nullptr, FALSE);
  ::SetTimer(flyout_->hwnd, kFlyoutHideTimerId, kFlyoutHideDelayMs, nullptr);
}

void HermesDesktopWindow::HideMediaFlyout() {
  if (flyout_->hwnd != nullptr && ::IsWindow(flyout_->hwnd)) {
    ::KillTimer(flyout_->hwnd, kFlyoutHideTimerId);
    flyout_->hover_button = -1;
    flyout_->tracking_leave = false;
    ::ShowWindow(flyout_->hwnd, SW_HIDE);
  }
}

void HermesDesktopWindow::DestroyFlyoutWindow() {
  if (flyout_->hwnd != nullptr) {
    ::KillTimer(flyout_->hwnd, kFlyoutHideTimerId);
    ::DestroyWindow(flyout_->hwnd);
    flyout_->hwnd = nullptr;
  }
}

// static
LRESULT CALLBACK HermesDesktopWindow::FlyoutWndProc(HWND hwnd, UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<HermesDesktopWindow*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    return self->HandleFlyoutMessage(hwnd, message, wparam, lparam);
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT HermesDesktopWindow::HandleFlyoutMessage(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) noexcept {
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    case WM_ERASEBKGND:
      return 1;

    case WM_TIMER:
      if (wparam == kFlyoutHideTimerId) {
        HideMediaFlyout();
      }
      return 0;

    case WM_MOUSEMOVE: {
      if (!flyout_->tracking_leave) {
        TRACKMOUSEEVENT tme{sizeof(tme), TME_LEAVE, hwnd, 0};
        ::TrackMouseEvent(&tme);
        flyout_->tracking_leave = true;
        ::KillTimer(hwnd, kFlyoutHideTimerId);
      }
      RECT client{};
      ::GetClientRect(hwnd, &client);
      const FlyoutLayout layout = BuildFlyoutLayout(
          client.right - client.left, client.bottom - client.top, flyout_->scale);
      const POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      int next_hover = -1;
      for (int i = 0; i < 3; ++i) {
        if (::PtInRect(&layout.buttons[i], pt)) {
          next_hover = i;
          break;
        }
      }
      if (next_hover != flyout_->hover_button) {
        flyout_->hover_button = next_hover;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_MOUSELEAVE:
      flyout_->tracking_leave = false;
      if (flyout_->hover_button != -1) {
        flyout_->hover_button = -1;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      ::SetTimer(hwnd, kFlyoutHideTimerId, kFlyoutHideDelayMs, nullptr);
      return 0;

    case WM_LBUTTONUP: {
      RECT client{};
      ::GetClientRect(hwnd, &client);
      const FlyoutLayout layout = BuildFlyoutLayout(
          client.right - client.left, client.bottom - client.top, flyout_->scale);
      const POINT pt{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      for (int i = 0; i < 3; ++i) {
        if (::PtInRect(&layout.buttons[i], pt)) {
          const char* action =
              i == 0 ? "previous" : (i == 1 ? "playPause" : "next");
          EmitSimpleEvent("onFlyoutAction", action);
          if (!flyout_->tracking_leave) {
            ::SetTimer(hwnd, kFlyoutHideTimerId, kFlyoutHideDelayMs, nullptr);
          }
          break;
        }
      }
      return 0;
    }

    case WM_PAINT:
      PaintFlyout(hwnd);
      return 0;
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

void HermesDesktopWindow::PaintFlyout(HWND hwnd) {
  PAINTSTRUCT ps{};
  HDC hdc = ::BeginPaint(hwnd, &ps);
  RECT rc{};
  ::GetClientRect(hwnd, &rc);
  const int width = rc.right - rc.left;
  const int height = rc.bottom - rc.top;
  if (width <= 0 || height <= 0) {
    ::EndPaint(hwnd, &ps);
    return;
  }

  HDC mem_dc = ::CreateCompatibleDC(hdc);
  HBITMAP mem_bmp = ::CreateCompatibleBitmap(hdc, width, height);
  HGDIOBJ old_bmp = ::SelectObject(mem_dc, mem_bmp);

  HBRUSH bg_brush = ::CreateSolidBrush(RGB(19, 19, 24));
  ::FillRect(mem_dc, &rc, bg_brush);
  ::DeleteObject(bg_brush);

  const FlyoutLayout layout = BuildFlyoutLayout(width, height, flyout_->scale);

  // Subtle crimson / neutral status edge strip.
  HBRUSH accent_brush = ::CreateSolidBrush(
      flyout_->is_playing ? RGB(225, 29, 72) : RGB(90, 90, 102));
  ::FillRect(mem_dc, &layout.accent, accent_brush);
  ::DeleteObject(accent_brush);

  // Album art tile or DIB blit.
  const size_t expected_bytes =
      static_cast<size_t>((std::max)(0, flyout_->art_width)) *
      static_cast<size_t>((std::max)(0, flyout_->art_height)) * 4;
  if (flyout_->art_width > 0 && flyout_->art_height > 0 &&
      flyout_->art_bgra.size() >= expected_bytes) {
    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = flyout_->art_width;
    bmi.bmiHeader.biHeight = -flyout_->art_height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    ::SetStretchBltMode(mem_dc, HALFTONE);
    ::StretchDIBits(
        mem_dc, layout.art.left, layout.art.top,
        layout.art.right - layout.art.left, layout.art.bottom - layout.art.top,
        0, 0, flyout_->art_width, flyout_->art_height, flyout_->art_bgra.data(),
        &bmi, DIB_RGB_COLORS, SRCCOPY);
  } else {
    HBRUSH art_brush = ::CreateSolidBrush(RGB(34, 34, 42));
    HPEN art_pen = ::CreatePen(PS_SOLID, 1, RGB(52, 52, 62));
    HGDIOBJ prev_b = ::SelectObject(mem_dc, art_brush);
    HGDIOBJ prev_p = ::SelectObject(mem_dc, art_pen);
    ::RoundRect(mem_dc, layout.art.left, layout.art.top, layout.art.right,
                layout.art.bottom, 8, 8);
    ::SelectObject(mem_dc, prev_b);
    ::SelectObject(mem_dc, prev_p);
    ::DeleteObject(art_brush);
    ::DeleteObject(art_pen);
  }

  ::SetBkMode(mem_dc, TRANSPARENT);
  HFONT title_font = ::CreateFontW(
      -ScalePx(13, flyout_->scale), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HFONT artist_font = ::CreateFontW(
      -ScalePx(11, flyout_->scale), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");

  HGDIOBJ old_font = ::SelectObject(mem_dc, title_font);
  ::SetTextColor(mem_dc, RGB(244, 244, 246));
  RECT title_rc = layout.title;
  ::DrawTextW(mem_dc, flyout_->title.c_str(), -1, &title_rc,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                  DT_NOPREFIX);

  ::SelectObject(mem_dc, artist_font);
  ::SetTextColor(mem_dc, RGB(161, 161, 170));
  RECT artist_rc = layout.artist;
  ::DrawTextW(mem_dc, flyout_->artist.c_str(), -1, &artist_rc,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                  DT_NOPREFIX);

  ::SelectObject(mem_dc, old_font);
  ::DeleteObject(title_font);
  ::DeleteObject(artist_font);

  for (int i = 0; i < 3; ++i) {
    const RECT& btn = layout.buttons[i];
    const bool hovered = flyout_->hover_button == i;
    if (hovered || i == 1) {
      const COLORREF pill_bg =
          hovered ? RGB(54, 54, 66) : RGB(36, 36, 44);
      HBRUSH pill_b = ::CreateSolidBrush(pill_bg);
      HPEN pill_p = ::CreatePen(PS_NULL, 0, 0);
      HGDIOBJ ob = ::SelectObject(mem_dc, pill_b);
      HGDIOBJ op = ::SelectObject(mem_dc, pill_p);
      ::Ellipse(mem_dc, btn.left, btn.top, btn.right, btn.bottom);
      ::SelectObject(mem_dc, ob);
      ::SelectObject(mem_dc, op);
      ::DeleteObject(pill_b);
      ::DeleteObject(pill_p);
    }
    const COLORREF fg = hovered ? RGB(255, 255, 255) : RGB(228, 228, 232);
    if (i == 0) {
      DrawSkipIcon(mem_dc, btn, fg, false);
    } else if (i == 1) {
      if (flyout_->is_playing) {
        DrawPauseIcon(mem_dc, btn, fg);
      } else {
        DrawPlayIcon(mem_dc, btn, fg);
      }
    } else {
      DrawSkipIcon(mem_dc, btn, fg, true);
    }
  }

  ::BitBlt(hdc, 0, 0, width, height, mem_dc, 0, 0, SRCCOPY);
  ::SelectObject(mem_dc, old_bmp);
  ::DeleteObject(mem_bmp);
  ::DeleteDC(mem_dc);
  ::EndPaint(hwnd, &ps);
}

void HermesDesktopWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "startDragging") {
    if (hwnd_ != nullptr && !is_fullscreen_) {
      ::ReleaseCapture();
      ::SendMessageW(hwnd_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    }
    result->Success();
    return;
  }

  if (method == "startTopResize") {
    if (hwnd_ != nullptr && !is_fullscreen_ && !::IsZoomed(hwnd_)) {
      ::ReleaseCapture();
      ::SendMessageW(hwnd_, WM_NCLBUTTONDOWN, HTTOP, 0);
    }
    result->Success();
    return;
  }

  if (method == "minimize") {
    if (hwnd_ != nullptr) {
      ::ShowWindow(hwnd_, SW_MINIMIZE);
    }
    result->Success();
    return;
  }

  if (method == "toggleMaximize") {
    if (hwnd_ != nullptr) {
      if (is_fullscreen_) {
        SetFullscreen(false);
      } else {
        ::ShowWindow(hwnd_, ::IsZoomed(hwnd_) ? SW_RESTORE : SW_MAXIMIZE);
      }
    }
    result->Success();
    return;
  }

  if (method == "setFullscreen") {
    bool target = false;
    if (const auto* b = std::get_if<bool>(call.arguments())) {
      target = *b;
    } else if (const auto* m =
                   std::get_if<flutter::EncodableMap>(call.arguments())) {
      target = ReadBoolArg(*m, "fullscreen", false);
    }
    SetFullscreen(target);
    result->Success();
    return;
  }

  if (method == "closeWindow") {
    if (hwnd_ != nullptr) {
      ::PostMessageW(hwnd_, WM_CLOSE, 0, 0);
    }
    result->Success();
    return;
  }

  if (method == "quitApp") {
    force_quit_ = true;
    DestroyFlyoutWindow();
    RemoveTrayIcon();
    if (hwnd_ != nullptr && ::IsWindow(hwnd_)) {
      ::DestroyWindow(hwnd_);
    }
    result->Success();
    return;
  }

  if (method == "showWindow") {
    RestoreFromTray();
    result->Success();
    return;
  }

  if (method == "setTitle") {
    std::string title;
    if (const auto* s = std::get_if<std::string>(call.arguments())) {
      title = *s;
    } else if (const auto* m =
                   std::get_if<flutter::EncodableMap>(call.arguments())) {
      title = ReadStringArg(*m, "title");
    }
    if (hwnd_ != nullptr && !title.empty()) {
      ::SetWindowTextW(hwnd_, Utf8ToWide(title).c_str());
    }
    result->Success();
    return;
  }

  if (method == "setCloseToTray") {
    if (const auto* b = std::get_if<bool>(call.arguments())) {
      close_to_tray_ = *b;
    }
    result->Success();
    return;
  }

  if (method == "updateTrayState") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      const std::string title = ReadStringArg(*args, "title");
      const std::string artist = ReadStringArg(*args, "artist");
      tray_is_playing_ = ReadBoolArg(*args, "isPlaying", false);
      if (title.empty()) {
        tray_track_label_.clear();
      } else if (artist.empty()) {
        tray_track_label_ = Utf8ToWide(title);
      } else {
        tray_track_label_ = Utf8ToWide(title + " — " + artist);
      }
      UpdateTrayTooltip();
    }
    result->Success();
    return;
  }

  if (method == "getBounds") {
    result->Success(flutter::EncodableValue(ReadBoundsMap()));
    return;
  }

  if (method == "setBounds") {
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      ApplyBounds(*args);
    }
    result->Success();
    return;
  }

  if (method == "showMediaFlyout") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "Expected flyout map.");
      return;
    }
    std::vector<uint8_t> art_bgra;
    const auto art_it = args->find(flutter::EncodableValue("artBgra"));
    if (art_it != args->end()) {
      if (const auto* bytes =
              std::get_if<std::vector<uint8_t>>(&art_it->second)) {
        art_bgra = *bytes;
      }
    }
    ShowMediaFlyout(ReadStringArg(*args, "title"),
                    ReadStringArg(*args, "artist"),
                    ReadBoolArg(*args, "isPlaying", false), std::move(art_bgra),
                    ReadIntArg(*args, "artWidth").value_or(0),
                    ReadIntArg(*args, "artHeight").value_or(0));
    result->Success();
    return;
  }

  if (method == "hideMediaFlyout") {
    HideMediaFlyout();
    result->Success();
    return;
  }

  result->NotImplemented();
}

LRESULT HermesDesktopWindow::HandleWindowMessage(HWND hwnd, UINT message,
                                                   WPARAM wparam, LPARAM lparam,
                                                   bool* handled) noexcept {
  *handled = false;

  switch (message) {
    case WM_NCCALCSIZE: {
      if (wparam == TRUE) {
        *handled = true;
        if (is_fullscreen_) {
          return 0;
        }
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        RECT* r = &params->rgrc[0];
        if (::IsZoomed(hwnd)) {
          MONITORINFO mi{sizeof(mi)};
          if (::GetMonitorInfoW(
                  ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi)) {
            *r = mi.rcWork;
          }
          return 0;
        }
        const int frame_x =
            GetDpiMetric(hwnd, SM_CXFRAME) + GetDpiMetric(hwnd, SM_CXPADDEDBORDER);
        const int frame_y =
            GetDpiMetric(hwnd, SM_CYFRAME) + GetDpiMetric(hwnd, SM_CXPADDEDBORDER);
        r->left += frame_x;
        r->right -= frame_x;
        r->bottom -= frame_y;
        return 0;
      }
      break;
    }

    case WM_GETMINMAXINFO: {
      const double scale = GetScaleForHwnd(hwnd);
      auto* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
      mmi->ptMinTrackSize.x = ScalePx(900, scale);
      mmi->ptMinTrackSize.y = ScalePx(600, scale);
      *handled = true;
      return 0;
    }

    case WM_SIZE: {
      const bool maximized = ::IsZoomed(hwnd) != FALSE;
      if (maximized != last_maximized_) {
        last_maximized_ = maximized;
        EmitWindowState();
      }
      break;
    }

    case WM_CLOSE: {
      if (close_to_tray_ && !force_quit_) {
        ::ShowWindow(hwnd, SW_HIDE);
        *handled = true;
        return 0;
      }
      break;
    }

    case WM_APPCOMMAND: {
      const UINT cmd = GET_APPCOMMAND_LPARAM(lparam);
      if (cmd == APPCOMMAND_BROWSER_BACKWARD) {
        EmitSimpleEvent("onAppCommand", "back");
        *handled = true;
        return TRUE;
      }
      if (cmd == APPCOMMAND_BROWSER_FORWARD) {
        EmitSimpleEvent("onAppCommand", "forward");
        *handled = true;
        return TRUE;
      }
      break;
    }

    case kWmTrayIcon: {
      const UINT tray_msg = static_cast<UINT>(lparam);
      if (tray_msg == WM_LBUTTONUP || tray_msg == WM_LBUTTONDBLCLK) {
        RestoreFromTray();
      } else if (tray_msg == WM_RBUTTONUP || tray_msg == WM_CONTEXTMENU) {
        ShowTrayMenu();
      }
      *handled = true;
      return 0;
    }
  }

  return 0;
}
