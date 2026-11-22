#include "hermes_smtc_bridge.h"

#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.foundation.h>
#include <windows.media.h>
#include <windows.storage.streams.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/implements.h>
#include <wrl/wrappers/corewrappers.h>

#include <utility>

#include "utils.h"

namespace {

using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::Foundation::IUriRuntimeClass;
using ABI::Windows::Foundation::IUriRuntimeClassFactory;
using ABI::Windows::Media::IMusicDisplayProperties;
using ABI::Windows::Media::IMusicDisplayProperties2;
using ABI::Windows::Media::ISystemMediaTransportControls;
using ABI::Windows::Media::ISystemMediaTransportControlsButtonPressedEventArgs;
using ABI::Windows::Media::ISystemMediaTransportControlsDisplayUpdater;
using ABI::Windows::Media::MediaPlaybackStatus_Closed;
using ABI::Windows::Media::MediaPlaybackStatus_Paused;
using ABI::Windows::Media::MediaPlaybackStatus_Playing;
using ABI::Windows::Media::MediaPlaybackType_Music;
using ABI::Windows::Media::SystemMediaTransportControls;
using ABI::Windows::Media::SystemMediaTransportControlsButton;
using ABI::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using ABI::Windows::Media::SystemMediaTransportControlsButton_FastForward;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Next;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Pause;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Play;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Previous;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Rewind;
using ABI::Windows::Media::SystemMediaTransportControlsButton_Stop;
using ABI::Windows::Storage::Streams::IRandomAccessStreamReference;
using ABI::Windows::Storage::Streams::IRandomAccessStreamReferenceStatics;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::FtmBase;
using Microsoft::WRL::Implements;
using Microsoft::WRL::RuntimeClassFlags;

std::string MapSmtcButtonName(SystemMediaTransportControlsButton button) {
  switch (button) {
    case SystemMediaTransportControlsButton_Play:
      return "play";
    case SystemMediaTransportControlsButton_Pause:
      return "pause";
    case SystemMediaTransportControlsButton_Stop:
      return "stop";
    case SystemMediaTransportControlsButton_Next:
    case SystemMediaTransportControlsButton_FastForward:
      return "next";
    case SystemMediaTransportControlsButton_Previous:
    case SystemMediaTransportControlsButton_Rewind:
      return "previous";
    default:
      return "";
  }
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

bool ReadBoolArg(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return false;
  }
  if (const auto* value = std::get_if<bool>(&it->second)) {
    return *value;
  }
  return false;
}

}  // namespace

struct HermesSmtcBridge::Impl {
  ComPtr<ISystemMediaTransportControls> smtc;
  EventRegistrationToken button_token{};
  bool has_button_token = false;
  bool ro_initialized = false;
  std::string last_art_url;
};

HermesSmtcBridge::HermesSmtcBridge(HWND hwnd,
                                   flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd), impl_(std::make_unique<Impl>()) {
  if (messenger != nullptr) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "hermes.media/smtc",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [this](
            const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result) { HandleMethodCall(call, std::move(result)); });
  }

  if (hwnd_ == nullptr || !::IsWindow(hwnd_)) {
    return;
  }

  const HRESULT ro_hr = ::RoInitialize(RO_INIT_SINGLETHREADED);
  impl_->ro_initialized = SUCCEEDED(ro_hr);

  ComPtr<ISystemMediaTransportControlsInterop> interop;
  HSTRING_HEADER class_header{};
  HSTRING class_id = nullptr;
  const wchar_t* smtc_name = RuntimeClass_Windows_Media_SystemMediaTransportControls;
  HRESULT hr = ::WindowsCreateStringReference(
      smtc_name, static_cast<UINT32>(wcslen(smtc_name)), &class_header,
      &class_id);
  if (FAILED(hr)) {
    return;
  }

  hr = ::RoGetActivationFactory(class_id, IID_PPV_ARGS(&interop));
  if (FAILED(hr) || !interop) {
    return;
  }

  ComPtr<ISystemMediaTransportControls> controls;
  hr = interop->GetForWindow(hwnd_, IID_PPV_ARGS(&controls));
  if (FAILED(hr) || !controls) {
    return;
  }

  controls->put_IsEnabled(TRUE);
  controls->put_IsPlayEnabled(TRUE);
  controls->put_IsPauseEnabled(TRUE);
  controls->put_IsStopEnabled(TRUE);
  controls->put_IsNextEnabled(TRUE);
  controls->put_IsPreviousEnabled(TRUE);
  controls->put_PlaybackStatus(MediaPlaybackStatus_Closed);

  using AgileButtonPressedHandler = Implements<
      RuntimeClassFlags<ClassicCom>,
      ITypedEventHandler<SystemMediaTransportControls*,
                         SystemMediaTransportControlsButtonPressedEventArgs*>,
      FtmBase>;
  auto callback = Callback<AgileButtonPressedHandler>(
      [hwnd = hwnd_](
          ISystemMediaTransportControls*,
          ISystemMediaTransportControlsButtonPressedEventArgs* args) -> HRESULT {
        if (args != nullptr && ::IsWindow(hwnd)) {
          SystemMediaTransportControlsButton button{};
          if (SUCCEEDED(args->get_Button(&button))) {
            ::PostMessage(hwnd, kWmButtonPressed, static_cast<WPARAM>(button),
                          0);
          }
        }
        return S_OK;
      });

  if (callback) {
    EventRegistrationToken token{};
    if (SUCCEEDED(controls->add_ButtonPressed(callback.Get(), &token))) {
      impl_->button_token = token;
      impl_->has_button_token = true;
    }
  }

  impl_->smtc = controls;
}

HermesSmtcBridge::~HermesSmtcBridge() { Shutdown(); }

void HermesSmtcBridge::Shutdown() {
  if (impl_ && impl_->smtc) {
    if (impl_->has_button_token) {
      impl_->smtc->remove_ButtonPressed(impl_->button_token);
      impl_->has_button_token = false;
    }
    impl_->smtc->put_IsEnabled(FALSE);
    impl_->smtc.Reset();
  }
  if (impl_) {
    impl_->last_art_url.clear();
    if (impl_->ro_initialized) {
      ::RoUninitialize();
      impl_->ro_initialized = false;
    }
  }
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
}

void HermesSmtcBridge::HandleWindowMessage(WPARAM wparam) {
  if (!channel_) {
    return;
  }
  const auto button = static_cast<SystemMediaTransportControlsButton>(wparam);
  const std::string action = MapSmtcButtonName(button);
  if (action.empty()) {
    return;
  }
  channel_->InvokeMethod(
      "onMediaButton",
      std::make_unique<flutter::EncodableValue>(action));
}

void HermesSmtcBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "publishState") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "Expected a metadata map.");
      return;
    }
    PublishState(ReadStringArg(*args, "title"),
                 ReadStringArg(*args, "artist"),
                 ReadStringArg(*args, "album"),
                 ReadBoolArg(*args, "isPlaying"),
                 ReadStringArg(*args, "artUrl"));
    result->Success();
    return;
  }

  if (call.method_name() == "clearState") {
    ClearState();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void HermesSmtcBridge::PublishState(const std::string& title,
                                    const std::string& artist,
                                    const std::string& album, bool is_playing,
                                    const std::string& art_url) {
  if (!impl_ || !impl_->smtc) {
    return;
  }

  impl_->smtc->put_IsEnabled(TRUE);
  impl_->smtc->put_PlaybackStatus(is_playing ? MediaPlaybackStatus_Playing
                                             : MediaPlaybackStatus_Paused);

  ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
  if (FAILED(impl_->smtc->get_DisplayUpdater(&updater)) || !updater) {
    return;
  }

  updater->put_Type(MediaPlaybackType_Music);

  ComPtr<IMusicDisplayProperties> music_props;
  if (SUCCEEDED(updater->get_MusicProperties(&music_props)) && music_props) {
    const std::wstring w_title = Utf16FromUtf8(title);
    const std::wstring w_artist = Utf16FromUtf8(artist);
    const std::wstring w_album = Utf16FromUtf8(album);

    HSTRING_HEADER title_hdr{};
    HSTRING h_title = nullptr;
    if (SUCCEEDED(::WindowsCreateStringReference(
            w_title.c_str(), static_cast<UINT32>(w_title.size()), &title_hdr,
            &h_title))) {
      music_props->put_Title(h_title);
    }

    HSTRING_HEADER artist_hdr{};
    HSTRING h_artist = nullptr;
    if (SUCCEEDED(::WindowsCreateStringReference(
            w_artist.c_str(), static_cast<UINT32>(w_artist.size()), &artist_hdr,
            &h_artist))) {
      music_props->put_Artist(h_artist);
    }

    ComPtr<IMusicDisplayProperties2> music_props2;
    if (SUCCEEDED(music_props.As(&music_props2)) && music_props2) {
      HSTRING_HEADER album_hdr{};
      HSTRING h_album = nullptr;
      if (SUCCEEDED(::WindowsCreateStringReference(
              w_album.c_str(), static_cast<UINT32>(w_album.size()), &album_hdr,
              &h_album))) {
        music_props2->put_AlbumTitle(h_album);
      }
    }
  }

  if (art_url != impl_->last_art_url) {
    if (!art_url.empty()) {
      const std::wstring w_art = Utf16FromUtf8(art_url);
      HSTRING_HEADER uri_class_hdr{};
      HSTRING uri_class_id = nullptr;
      const wchar_t* uri_cls = RuntimeClass_Windows_Foundation_Uri;

      HSTRING_HEADER art_hdr{};
      HSTRING h_art = nullptr;
      ComPtr<IUriRuntimeClassFactory> uri_factory;
      ComPtr<IUriRuntimeClass> win_uri;

      if (SUCCEEDED(::WindowsCreateStringReference(
              uri_cls, static_cast<UINT32>(wcslen(uri_cls)), &uri_class_hdr,
              &uri_class_id)) &&
          SUCCEEDED(::RoGetActivationFactory(uri_class_id,
                                             IID_PPV_ARGS(&uri_factory))) &&
          SUCCEEDED(::WindowsCreateStringReference(
              w_art.c_str(), static_cast<UINT32>(w_art.size()), &art_hdr,
              &h_art)) &&
          SUCCEEDED(uri_factory->CreateUri(h_art, &win_uri)) && win_uri) {
        const wchar_t* stream_cls =
            RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference;
        HSTRING_HEADER stream_class_hdr{};
        HSTRING stream_class_id = nullptr;
        ComPtr<IRandomAccessStreamReferenceStatics> stream_statics;
        ComPtr<IRandomAccessStreamReference> stream_ref;
        if (SUCCEEDED(::WindowsCreateStringReference(
                stream_cls, static_cast<UINT32>(wcslen(stream_cls)),
                &stream_class_hdr, &stream_class_id)) &&
            SUCCEEDED(::RoGetActivationFactory(
                stream_class_id, IID_PPV_ARGS(&stream_statics))) &&
            SUCCEEDED(
                stream_statics->CreateFromUri(win_uri.Get(), &stream_ref)) &&
            stream_ref) {
          updater->put_Thumbnail(stream_ref.Get());
        }
      }
    } else {
      updater->put_Thumbnail(nullptr);
    }
    impl_->last_art_url = art_url;
  }

  updater->Update();
}

void HermesSmtcBridge::ClearState() {
  if (!impl_ || !impl_->smtc) {
    return;
  }
  impl_->last_art_url.clear();
  impl_->smtc->put_PlaybackStatus(MediaPlaybackStatus_Closed);
  ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
  if (SUCCEEDED(impl_->smtc->get_DisplayUpdater(&updater)) && updater) {
    updater->ClearAll();
    updater->Update();
  }
  impl_->smtc->put_IsEnabled(FALSE);
}
