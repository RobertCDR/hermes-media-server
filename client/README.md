# Hermes Client (Flutter)

Cross-platform **Cinema & Music** streaming client for **Hermes Media Server**, built with Flutter (`3.50.0` / Dart `3.14.0`). Supports **Windows Desktop**, **Android**, and **Web (`Edge`)**.

---

## Module Structure

```text
client/lib/
├── main.dart                                  # Application entry point and root state wiring
└── src/
    ├── core/
    │   ├── auth/
    │   │   ├── auth_service.dart              # Setup, login, invite registration, token refresh, reset
    │   │   ├── authenticated_http_client.dart # Automatic bearer injection and 401 token refresh retry
    │   │   └── session_store.dart             # SharedPreferences JWT, refresh token, and endpoint persistence
    │   ├── media/
    │   │   └── hermes_media_runtime.dart      # media_kit & platform audio runtime initialization
    │   ├── network/
    │   │   ├── endpoint_resolver.dart         # Tailscale-first -> LAN failover via /api/v1/system/info
    │   │   └── hermes_sync_client.dart        # SignalR WebSocket client & ConnectTransport adapter
    │   ├── settings/
    │   │   └── hermes_preferences.dart        # Device & account preferences persistence and API sync
    │   ├── storage/
    │   │   ├── hermes_cache_manager.dart      # Artwork/image cache inspection, cap tiers (up to 10 GB), and cleanup
    │   │   └── search_history_store.dart      # Local cinema & music search history store
    │   ├── theme/
    │   │   └── hermes_theme_tokens.dart       # 6 dark-first palettes (Crimson..Graphite), OLED pure black, title tinting
    │   ├── widgets/                           # Artwork tiles, vector icons, marquee text, horizontal shelves, search pills
    │   └── window/
    │       ├── hermes_desktop_titlebar.dart   # Custom frameless Windows titlebar + keyboard shortcuts dialog
    │       └── hermes_window_bridge.dart      # MethodChannel bridge for Win32 fullscreen, tray, bounds & media flyout
    └── features/
        ├── admin/                             # Library roots, watcher/scan progress, active sessions, TMDb identify, invites, server settings
        ├── auth/                              # First-run setup and multi-device login screen
        ├── cinema/                            # Movie/series catalog, detail page, SourceSelectorCard, HDR-safe player (Fit/Cover/Stretch)
        ├── music/                             # Dual-mode Connect coordinator, audio engine, OS media bridge, mini player, Now Playing panel
        ├── settings/                          # Theme/palette selector, audio/video quality, cache controls, desktop tray/flyout toggles
        └── shell/                             # Dual-world shell (Obsidian Rail on desktop, floating toggle pill & bottom tabs on mobile)
```

---

## Key Client Features

### 1. Dual-World Theme Tokens (`HermesThemeTokens`)
- **6 Palettes (`HermesThemeId`)**:
  - `crimson` (`Crimson`): `#130A0C` bg / `#1C1012` surface / `#DC143C` accent (default)
  - `midnight` (`Midnight`): `#0B0E15` bg / `#131826` surface / `#5B8CFF` accent
  - `forest` (`Forest`): `#0A110D` bg / `#111C16` surface / `#3DD68C` accent
  - `amethyst` (`Amethyst`): `#100C16` bg / `#1A1424` surface / `#A678FF` accent
  - `amber` (`Amber`): `#120E09` bg / `#1D1710` surface / `#F2A93B` accent
  - `graphite` (`Graphite`): `#0F0F10` bg / `#18181A` surface / `#F2F2F3` accent
- **Pure Black (`pureBlack`)**: Optional OLED toggle forcing `#000000` backgrounds, plus contrast-clamped local `titleTint`.

### 2. Cinema & HDR-Safe Playback (`HermesVideoPlayerScreen`)
- **Source Switching (`SourceSelectorCard`)**: Switch between multiple releases per title (`1080p`, `4K HDR10`), inspect codecs/bitrate, select target transcoding presets (`DirectPlay`, `1080p`, `720p`, `480p`), cycle video fit (`Fit` / `Cover` / `Stretch`), and customize Nuvio-style subtitles (track, delay, size, background).
- **HDR-Safe Subtitle Clamping (`HermesVideoPlayerConfig.hdrSafeDefault`)**: Configures `gpu-api=opengl` and renders subtitle text at `#D8D8D8` over `#80000000` so subtitles do not bloom on HDR displays.

### 3. Spotify-Style Music Connect (`MusicPlaybackCoordinator`)
- Monotonic `Version` reconciliation ensures out-of-order `SessionStateUpdated` frames never overwrite newer state.
- Distinguishes the **active audio renderer** (`ActiveRendererDeviceId`) from remote controller devices unless `TransferOutput` is requested.
- Automatically pauses active playback when the active audio renderer disconnects.
- Adapts requested audio quality based on network type (`Wi-Fi`: `Lossless`, `Cellular`: `High160`) and integrates with Windows SMTC / tray / flyout and Android `audio_service`.

---

## Running Locally

### Prerequisites
- **Flutter `3.50.0+`** (`flutter doctor` passing for target platform)
- For **Windows Desktop (`-d windows`)**: Visual Studio with the **"Desktop development with C++"** workload installed (MSVC C++ x64/x86 build tools, CMake tools, and Windows 10/11 SDK)
- Running **Hermes Media Server** backend (default: `http://localhost:5258`)

### Commands
```bash
cd client
flutter pub get

# Run on Windows Desktop (requires Visual Studio C++ Desktop workload)
flutter run -d windows

# Run on Android device or emulator
flutter run -d android

# Run in Microsoft Edge (Web target)
flutter run -d edge
```

---

## Code Quality, Tests & Coverage

```bash
cd client
flutter analyze --fatal-infos
flutter test --coverage
```

- LCOV coverage report is written to `client/coverage/lcov.info`.
