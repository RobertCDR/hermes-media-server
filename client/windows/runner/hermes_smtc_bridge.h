#ifndef RUNNER_HERMES_SMTC_BRIDGE_H_
#define RUNNER_HERMES_SMTC_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Native Windows SystemMediaTransportControls (SMTC) integration exposed over a
// Flutter MethodChannel ("hermes.media/smtc") without ATL dependencies.
class HermesSmtcBridge {
 public:
  static constexpr UINT kWmButtonPressed = WM_APP + 0x101;

  HermesSmtcBridge(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~HermesSmtcBridge();

  HermesSmtcBridge(const HermesSmtcBridge&) = delete;
  HermesSmtcBridge& operator=(const HermesSmtcBridge&) = delete;

  void HandleWindowMessage(WPARAM wparam);
  void Shutdown();

 private:
  struct Impl;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void PublishState(const std::string& title, const std::string& artist,
                    const std::string& album, bool is_playing,
                    const std::string& art_url);
  void ClearState();

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_HERMES_SMTC_BRIDGE_H_
