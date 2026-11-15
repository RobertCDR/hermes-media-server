# Hermes Client (Flutter)

Cross-platform **Cinema & Music** streaming client for **Hermes Media Server**, built with Flutter (`3.50.0` / Dart `3.14.0`). Supports **Web (`Edge`)**, **Windows Desktop**, and **Android**.

---

## Module Structure

```text
client/lib/
├── main.dart                                  # Application entry point and root state wiring
└── src/
    ├── core/
    │   ├── auth/
    │   │   ├── auth_service.dart              # Setup, login, invite registration, token refresh, reset
    │   │   └── session_store.dart             # In-memory JWT & refresh token session persistence
    │   ├── network/
    │   │   └── endpoint_resolver.dart         # Tailscale-first -> LAN failover via /api/v1/system/info
    │   └── theme/
    │       └── hermes_theme_tokens.dart       # Surface presets, accent tokens, Dynamic Album Art clamping
    └── features/
        ├── admin/                             # Library roots, manual scan triggers, user & invite management
        ├── auth/                              # First-run setup and multi-device login screen
        ├── cinema/                            # Movie/series catalog, SourceSelectorCard, HDR-safe player
        ├── music/                             # Dual-mode playback coordinator, mini player, device picker
        ├── settings/                          # Surface/accent theme selector and video renderer settings
        └── shell/                             # Dual-world shell (Cinema <-> Music navigation)
```

---

## Key Client Features

### 1. Dual-World Theme Tokens (`HermesThemeTokens`)
- **Surface Presets (`SurfacePreset`)**:
  - `obsidianGlow` (`Obsidian Glow`): `#090B12` primary, `#111522` elevated
  - `oledBlack` (`OLED Black`): `#000000` primary, `#0B0D13` elevated
  - `slate` (`Slate`): `#0F172A` primary, `#1E293B` elevated
- **Accent Presets (`HermesAccentKind`)**:
  - `crimson`, `violet`, `emerald`, `amber`, `cyan`, and `dynamicAlbumArt` (contrast-clamped to dark backgrounds)

### 2. Cinema & HDR-Safe Playback (`HermesVideoPlayerView`)
- **Source Switching (`SourceSelectorCard`)**: Switch between multiple releases per title (`1080p`, `4K HDR10`), inspect codecs/bitrate, select target transcoding presets (`DirectPlay`, `P1080`, `P720`, `P480`), and pick audio/subtitle streams.
- **HDR-Safe Subtitle Clamping (`HermesVideoPlayerConfig.hdrSafeDefault`)**: Configures `gpu-api=opengl` and renders subtitle text at `#D8D8D8` over `#80000000` so subtitles do not bloom on HDR displays.

### 3. Spotify-Style Music Connect (`MusicPlaybackCoordinator`)
- Monotonic `Version` reconciliation ensures out-of-order `SessionStateUpdated` frames never overwrite newer state.
- Distinguishes the **active audio renderer** (`ActiveRendererDeviceId`) from remote controller devices unless `TransferOutput` is requested.
- Automatically pauses active playback when the active audio renderer disconnects.
- Adapts requested audio quality based on network type (`Wi-Fi`: `Lossless`, `Cellular`: `High160`).

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

# Run in Microsoft Edge (Web target - works immediately without C++ toolchain)
flutter run -d edge

# Run on Windows Desktop (requires Visual Studio C++ Desktop workload)
flutter run -d windows

# Run on Android device or emulator
flutter run -d android
```

---

## Code Quality, Tests & Coverage

```bash
cd client
flutter analyze --fatal-infos
flutter test --coverage
```

- LCOV coverage report is written to `client/coverage/lcov.info`.
