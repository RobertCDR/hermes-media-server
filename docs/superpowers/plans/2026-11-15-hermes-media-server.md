# Hermes Media Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (chosen inline) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build **Hermes Media Server** completely from scratch in a clean public repository (`<repo-root>`), delivered through 10 automated, vertically tested PRs (Backend `.NET 10 LTS` + `PostgreSQL 17` + `FFmpeg` + `SignalR v2` and native `Flutter` client for Windows/Android with `media_kit`/`libmpv`, `Dual-World Hub: Cinema | Music`, and the `Obsidian Crimson` token theme).

**Architecture:** Monorepo organized into `backend/` (**Vertical Slice Architecture + Pragmatic DDD** on `.NET 10`: `Hermes.Domain` with rich entities, encapsulated invariants, and zero-dependency `Ports/`; `Hermes.Infrastructure` with `HermesDbContext` on PostgreSQL 17 and external adapters; `Hermes.Api` structured into vertical `Features/` without a redundant `Application` layer or `GenericRepository<T>`; plus `Hermes.UnitTests` with `NetArchTest.Rules` and `Hermes.IntegrationTests` with `Testcontainers.PostgreSql`), `client/` (GPU-rendered native Flutter client for Windows & Android), and `deploy/` (multi-stage `Dockerfile` with `ffmpeg` + `docker-compose.yml`). Media state uses a `1:N MediaSources` model per movie/episode, pre-generated WebP artwork on disk with `ETag` (zero BLOBs in SQL), hybrid Direct Play + FFmpeg HLS/Audio transcoding, and deterministic SignalR sync using monotonic `long Version`.

**Tech Stack:** `.NET SDK 10.0.401+`, ASP.NET Core 10, EF Core 10 (`Npgsql.EntityFrameworkCore.PostgreSQL`), `PostgreSQL 17` (`pg_trgm`), `FluentValidation`, `TagLibSharp`, `SkiaSharp`, `FFmpeg`/`FFprobe`, `xUnit`, `NetArchTest.Rules`, `Testcontainers.PostgreSql`, `Flutter 3.50.0` (`Windows` & `Android`), `http`, `material_ui`.

**Spec:** [2026-11-15-hermes-media-server-design.md](../../specs/2026-11-15-hermes-media-server-design.md) *(copied into the repository at `docs/specs/2026-11-15-hermes-media-server-design.md` in Task 1)*

## Global Constraints

- **Legacy repo untouched:** `<legacy-prototype-repo>` is never modified and stays as a private thesis archive.
- **Desktop workspace layout:** At the start of Task 1, create `<projects-root>`, move `<projects-root>\other-project-a` and `<projects-root>\other-project-b` into `<projects-root>\`, and initialize the new repo at `<repo-root>` (`<local-media-folder>` remains untouched for local manual testing).
- **Zero secrets or personal paths in Git:** No TMDb API key, JWT secret, local path (`<local-media-folder>`), IP address, or hardware serial may ever enter source code or committed configuration files.
- **Strict compilation quality:** `<TargetFramework>net10.0</TargetFramework>`, `<Nullable>enable</Nullable>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<NuGetAudit>true</NuGetAudit>`, zero `AutoMapper`, zero `GenericRepository<T>`, and zero `SixLabors.ImageSharp`.
- **Zero BLOBs in SQL & zero `Task.WhenAll` on the same `DbContext`:** Images reside strictly on disk/volume indexed by `ArtworkHash`, and `EnsureCreatedAsync()` is forbidden (only real EF Core migrations are allowed).
- **Strictly read-only scanner:** `TagLib.File` is opened read-only inside a `using` scope; user media files are never mutated.
- **Git workflow:** Each Task (1–10) is developed on its own branch (`feat/pr-XX-...` or `chore/pr-XX-...`), with atomic conventional commits and PR creation/merge verified by green test runs.

## Review Focus

1. **First-Run Setup race condition (`POST /api/v1/setup`):** Two concurrent requests when the database has zero users must create exactly one `Admin` account (`201 Created`), while the second receives `409 Conflict` / `410 Gone` (covered in **Task 3**).
2. **Stream ticket expiry during long movies or HLS sessions:** A `StreamTicket` bound to `(UserId, MediaSourceId)` must authorize HTTP Range requests and HLS segments throughout an active session (`6-hour` stream TTL) and reject any other `MediaSourceId` with `403 Forbidden` (covered in **Task 3** and **Task 5**).
3. **FFmpeg slot exhaustion (`MaxConcurrentVideoTranscodes = 2`) & orphan process prevention:** A third simultaneous transcoded video stream must return `429 TooManyRequests` with `"transcode_slots_exhausted"` (without blocking threads), and stopping/expiring a session must terminate the `ffmpeg` process and delete temporary segment directories (covered in **Task 5**).
4. **Out-of-order SignalR updates & active renderer disconnection:** Messages/mutations with `Version <= LastAppliedVersion` are ignored without UI/seek regressions, and SignalR disconnection of `ActiveRendererDeviceId` automatically pauses the session in the database and notifies the user group without starting unrequested audio on remote controller devices (covered in **Task 6** and **Task 9**).
5. **Temporarily missing media files or diacritics in filenames:** When a file is missing during a rescan, the scanner sets `MediaSource.MissingSince = utcNow` without deleting `Movie`/`Episode` or `WatchProgress`, and resets `MissingSince = null` if the file reappears (covered in **Task 4**).

---

## File Structure

```text

├── .editorconfig
├── .gitignore
├── global.json
├── README.md
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONTRIBUTING.md
│   ├── SECURITY.md
│   ├── specs/2026-11-15-hermes-media-server-design.md
│   └── superpowers/plans/2026-11-15-hermes-media-server.md
├── deploy/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
├── .github/workflows/
│   ├── ci-backend.yml
│   ├── ci-client.yml
│   ├── security.yml
│   └── docker.yml
├── backend/
│   ├── Hermes.slnx
│   ├── Directory.Build.props
│   ├── Directory.Packages.props
│   ├── src/
│   │   ├── Hermes.Domain/
│   │   │   ├── AssemblyReference.cs
│   │   │   ├── Entities/{User,RefreshToken,InviteCode,ServerSettings,MediaLibraryRoot,Movie,TvSeries,TvSeason,Episode,MediaSource,MediaStream,Artist,Album,Song,Playlist,PlaylistTrack,LikedSong,WatchProgress,PlaybackSession}.cs
│   │   │   ├── Enums/{UserRole,LibraryMediaType,StreamKind,VideoQualityPreset,AudioQualityPreset,PlaybackState,RepeatMode,ThemeSurfacePreset}.cs
│   │   │   └── Ports/{ITokenService,IStreamTicketService,IMediaProbeService,ITmdbClient,IArtworkStore,ITranscodeSessionManager,IDevicePresenceRegistry}.cs
│   │   ├── Hermes.Infrastructure/
│   │   │   ├── AssemblyReference.cs
│   │   │   ├── Persistence/{HermesDbContext,Configurations/*,Migrations/*}.cs
│   │   │   ├── Security/{JwtTokenService,HmacStreamTicketService,PasswordHasherAdapter}.cs
│   │   │   ├── Media/{LibraryScanChannel,LibraryScanWorker,FfprobeMediaProbeService,TagLibAudioMetadataReader,SkiaArtworkStore,TmdbMetadataClient,FfmpegTranscodeSessionManager,SubtitleExtractorService}.cs
│   │   │   └── Realtime/InMemoryDevicePresenceRegistry.cs
│   │   └── Hermes.Api/
│   │       ├── Program.cs
│   │       ├── appsettings.json
│   │       ├── appsettings.Example.json
│   │       ├── Features/
│   │       │   ├── System/{SystemInfoDto,SystemEndpoints}.cs
│   │       │   ├── Setup/{SetupDtos,SetupEndpoints,SetupHandler}.cs
│   │       │   ├── Auth/{AuthDtos,AuthEndpoints,AuthHandlers}.cs
│   │       │   ├── Admin/{AdminDtos,AdminEndpoints,InviteHandlers,LibraryAdminHandlers}.cs
│   │       │   ├── Cinema/{CinemaDtos,CinemaEndpoints,WatchProgressHandlers}.cs
│   │       │   ├── Streaming/{StreamDtos,StreamEndpoints,ArtworkEndpoints}.cs
│   │       │   └── Music/{MusicDtos,MusicEndpoints,PlaylistHandlers,PlaybackConnectService}.cs
│   │       └── Hubs/PlaybackSyncHub.cs
│   └── tests/
│       ├── Hermes.UnitTests/
│       │   ├── SanityTests.cs
│       │   ├── ArchitectureTests.cs
│       │   └── Domain/*Tests.cs
│       └── Hermes.IntegrationTests/
└── client/
    ├── pubspec.yaml
    ├── analysis_options.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── core/
    │   │   ├── network/{endpoint_resolver.dart,hermes_api_client.dart,auth_interceptor.dart}
    │   │   ├── storage/{secure_session_store.dart,artwork_cache_manager.dart}
    │   │   └── theme/{hermes_theme_tokens.dart,theme_controller.dart}
    │   └── features/
    │       ├── shell/dual_world_shell.dart
    │       ├── auth/{setup_screen.dart,login_screen.dart}
    │       ├── cinema/{cinema_home_screen.dart,media_details_screen.dart,source_selector_card.dart,video_player_screen.dart,video_player_controller.dart}
    │       ├── music/{music_home_screen.dart,music_search_screen.dart,playlists_screen.dart,music_playback_coordinator.dart,mini_player_bar.dart,device_picker_sheet.dart,platform_media_bridge.dart}
    │       ├── settings/player_and_theme_settings_screen.dart
    │       └── admin/{admin_dashboard_screen.dart,library_roots_tab.dart,invites_and_users_tab.dart,identify_media_dialog.dart}
    └── test/
```

---

### Task 1: Workspace Organization, Prerequisites, Monorepo Skeleton & CI/CD (PR #1)

**Branch:** `chore/pr-01-foundation`

**Files:**
- Create: `{.gitignore,.editorconfig,global.json,README.md}`
- Create: `docs\specs\2026-11-15-hermes-media-server-design.md`
- Create: `docs\superpowers\plans\2026-11-15-hermes-media-server.md`
- Create: `backend\{Hermes.slnx,Directory.Build.props,Directory.Packages.props}`
- Create: `backend\src\Hermes.Domain\{Hermes.Domain.csproj,AssemblyReference.cs}`
- Create: `backend\src\Hermes.Infrastructure\{Hermes.Infrastructure.csproj,AssemblyReference.cs}`
- Create: `backend\src\Hermes.Api\{Hermes.Api.csproj,Program.cs,appsettings.json,appsettings.Example.json,Features/System/SystemInfoDto.cs,Features/System/SystemEndpoints.cs}`
- Create: `backend\tests\Hermes.UnitTests\{Hermes.UnitTests.csproj,SanityTests.cs,ArchitectureTests.cs}`
- Create: `backend\tests\Hermes.IntegrationTests\Hermes.IntegrationTests.csproj`
- Create: `deploy\{Dockerfile,docker-compose.yml,.env.example}`
- Create: `.github\workflows\{ci-backend.yml,security.yml,docker.yml}`

**Interfaces:**
- Consumes: None (initial repository foundation)
- Produces:
  - `GET /health/live` -> `200 OK`
  - `GET /api/v1/system/info` -> `SystemInfoDto(Guid ServerId, string ServerName, string Version, bool SetupCompleted)`
  - Compile/dependency boundary enforced by `NetArchTest.Rules` in `ArchitectureTests.cs`

- [ ] **Step 1: Organize `Desktop\Projects`, install missing CLI tools (`ffmpeg`, `flutter`), and initialize Git repository**

Run in PowerShell:
```powershell
New-Item -ItemType Directory -Force -Path "<projects-root>"
if (Test-Path "<projects-root>\other-project-a") { Move-Item "<projects-root>\other-project-a" "<projects-root>\other-project-a" }
if (Test-Path "<projects-root>\other-project-b") { Move-Item "<projects-root>\other-project-b" "<projects-root>\other-project-b" }
winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements --silent
winget install --id Google.Flutter -e --accept-source-agreements --accept-package-agreements --silent
New-Item -ItemType Directory -Force -Path "<repo-root>"
cd "<repo-root>"
git init -b main
# initial root commit on main, then:
git checkout -b chore/pr-01-foundation
```
Expected: `<projects-root>\{other-project-a,other-project-b,hermes-media-server}` exist; `ffmpeg -version` and `flutter --version` succeed.

- [ ] **Step 2: Create project files (without `SystemInfoDto`, `AssemblyReference`, or endpoints) and write failing unit & architecture tests in `Hermes.UnitTests`**

```csharp
// SanityTests.cs
using FluentAssertions;
using Hermes.Api.Features.System;
using Xunit;

namespace Hermes.UnitTests;

public class SanityTests
{
    [Fact]
    public void SystemInfoDto_PreservesServerIdentityAndSetupFlag()
    {
        var id = Guid.NewGuid();
        var dto = new SystemInfoDto(id, "Hermes Media Server", "1.0.0", false);
        dto.ServerId.Should().Be(id);
        dto.SetupCompleted.Should().BeFalse();
    }
}

// ArchitectureTests.cs
using FluentAssertions;
using NetArchTest.Rules;
using Xunit;

namespace Hermes.UnitTests;

public class ArchitectureTests
{
    [Fact]
    public void Domain_ShouldNotDependOn_InfrastructureOrApi()
    {
        var result = Types.InAssembly(typeof(Hermes.Domain.AssemblyReference).Assembly)
            .ShouldNot()
            .HaveDependencyOnAny("Hermes.Infrastructure", "Hermes.Api")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }

    [Fact]
    public void Infrastructure_ShouldNotDependOn_Api()
    {
        var result = Types.InAssembly(typeof(Hermes.Infrastructure.AssemblyReference).Assembly)
            .ShouldNot()
            .HaveDependencyOn("Hermes.Api")
            .GetResult();

        result.IsSuccessful.Should().BeTrue();
    }
}
```

- [ ] **Step 3: Run tests to verify they fail before `SystemInfoDto` and `AssemblyReference` exist**

Run: `dotnet test backend\Hermes.slnx`
Expected: FAIL with `CS0234` / `CS0246` (missing `Hermes.Api.Features.System.SystemInfoDto` and `AssemblyReference`).

- [ ] **Step 4: Implement `Hermes.Domain.AssemblyReference`, `Hermes.Infrastructure.AssemblyReference`, `Features/System/{SystemInfoDto,SystemEndpoints}`, `Program.cs`, `deploy/`, `.github/workflows/`, and copy design + plan docs into `docs/`**

Pin `global.json` to `"version": "10.0.401"` with `"rollForward": "latestFeature"`. In `Directory.Build.props` set `<TargetFramework>net10.0</TargetFramework>`, `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, and `<NuGetAudit>true</NuGetAudit>`.

- [ ] **Step 5: Run build and tests to verify zero warnings and passing tests**

Run: `dotnet test backend\Hermes.slnx --configuration Release`
Expected: PASS (`Passed: 3, Failed: 0`, `0 Warning(s)`, `0 Error(s)`).

- [ ] **Step 6: Commit PR #1**

```bash
git add .
git commit -m "chore: bootstrap .NET 10 VSA monorepo, Docker, and GitHub Actions CI"
```

---

### Task 2: Pragmatic DDD Domain Entities, `1:N MediaSources` PostgreSQL Schema & Migrations (PR #2)

**Branch:** `feat/pr-02-domain-postgres`

**Files:**
- Create: `backend/src/Hermes.Domain/Enums/{UserRole,LibraryMediaType,StreamKind,VideoQualityPreset,AudioQualityPreset,PlaybackState,RepeatMode,ThemeSurfacePreset}.cs`
- Create: `backend/src/Hermes.Domain/Entities/{User,RefreshToken,InviteCode,ServerSettings,MediaLibraryRoot,Movie,TvSeries,TvSeason,Episode,MediaSource,MediaStream,Artist,Album,Song,Playlist,PlaylistTrack,LikedSong,WatchProgress,PlaybackSession}.cs`
- Create: `backend/src/Hermes.Domain/Ports/{ITokenService,IStreamTicketService,IMediaProbeService,ITmdbClient,IArtworkStore,ITranscodeSessionManager,IDevicePresenceRegistry}.cs`
- Create: `backend/src/Hermes.Infrastructure/Persistence/{HermesDbContext,Configurations/*,Migrations/*}.cs`
- Test: `backend/tests/Hermes.UnitTests/Domain/{WatchProgressDomainTests,PlaybackSessionDomainTests,InviteCodeDomainTests}.cs`
- Test: `backend/tests/Hermes.IntegrationTests/Persistence/PostgresSchemaMigrationTests.cs`

**Interfaces:**
- Consumes: `Hermes.Domain` base project from Task 1
- Produces:
  - Rich Domain Model entities (`WatchProgress.UpdatePosition(...)` enforcing >=90% watched rule, `PlaybackSession` Connect monotonic `Version++` state machine, `InviteCode.TryConsume(...)`, `Movie`/`Episode` `LockManualMatch(...)` + `MediaSource.MarkMissing()`/`MarkRestored()`).
  - `HermesDbContext : DbContext` with `DbSet<T>` for all 19 entities, `pg_trgm` extension enabled (`HasPostgresExtension("pg_trgm")`), GIN trigram indexes on `Movie.Title`, `TvSeries.Title`, `Artist.Name`, `Album.Title`, `Song.Title`, and unique index on `MediaSource.FilePath`.

- [ ] **Step 1: Write failing Pragmatic DDD unit tests + PostgreSQL Testcontainers migration & 1:N `MediaSource` integration test**

- [ ] **Step 2: Run unit and integration tests to verify they fail**

Run: `dotnet test backend/Hermes.slnx`
Expected: FAIL with missing Domain methods / `HermesDbContext`.

- [ ] **Step 3: Implement rich Domain entities (zero `byte[]` columns), Ports interfaces, `HermesDbContext`, EF configurations, and initial EF Core migration (`dotnet ef migrations add InitialPostgresSchema`)**

Ensure `ServerSettings` has `Guid ServerId`, `int MaxConcurrentVideoTranscodes = 2`, `int MaxConcurrentAudioTranscodes = 4`, `int? MaxRemoteVideoBitrateBps`, `bool TranscodingEnabled = true`.

- [ ] **Step 4: Run unit tests + PostgreSQL 17 Testcontainers migration test**

Run: `dotnet test backend/Hermes.slnx`
Expected: PASS.

- [ ] **Step 5: Commit PR #2**

```bash
git add backend/
git commit -m "feat(db): add Pragmatic DDD domain model, PostgreSQL 17 schema, 1:N MediaSources, and pg_trgm migrations"
```

---

### Task 3: First-Run Setup, Invite-Only Auth, Multi-Device Refresh Tokens & HMAC Stream Tickets (PR #3)

**Branch:** `feat/pr-03-auth-setup-tickets`

**Files:**
- Create: `backend/src/Hermes.Infrastructure/Security/{JwtTokenService,HmacStreamTicketService,PasswordHasherAdapter}.cs`
- Create: `backend/src/Hermes.Api/Features/Setup/{SetupDtos,SetupEndpoints}.cs`
- Create: `backend/src/Hermes.Api/Features/Auth/{AuthDtos,AuthEndpoints}.cs`
- Create: `backend/src/Hermes.Api/Features/Admin/{InviteDtos,InviteEndpoints,UserManagementEndpoints}.cs`
- Test: `backend/tests/Hermes.IntegrationTests/Security/{SetupEndpointTests,AuthMultiDeviceTests,StreamTicketServiceTests}.cs`

**Interfaces:**
- Consumes: `HermesDbContext`, `User`, `RefreshToken`, `InviteCode`, `ServerSettings`, `ITokenService`, `IStreamTicketService` from Task 2
- Produces:
  - `POST /api/v1/setup` -> creates single Admin under DB serializable/advisory lock
  - `POST /api/v1/auth/{register,login,refresh,change-password}` -> per-device `RefreshToken`
  - `POST /api/v1/admin/{invites,users/{id}/reset-code}`
  - `ITokenService` & `IStreamTicketService` (`CreateStreamTicket`, `TryValidateStreamTicket`)

- [ ] **Step 1: Write failing tests covering concurrent first-run setup race (Review Focus #1), multi-device login preservation, and stream-ticket media-source binding (Review Focus #2)**

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter "FullyQualifiedName~Security"`
Expected: FAIL.

- [ ] **Step 3: Implement `JwtTokenService`, `HmacStreamTicketService` (UTF-8 HMAC-SHA256), `PasswordHasherAdapter`, and Vertical Slice endpoints in `Features/{Setup,Auth,Admin}/` with ASP.NET Core Rate Limiting**

- [ ] **Step 4: Run security integration tests to verify all pass**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter "FullyQualifiedName~Security"`
Expected: PASS (`Passed: 6, Failed: 0`).

- [ ] **Step 5: Commit PR #3**

```bash
git add backend/
git commit -m "feat(auth): add first-run setup, invite codes, per-device refresh tokens, and HMAC stream tickets"
```

---

### Task 4: Admin Library Roots, Read-Only `Channel<T>` Scanner, TMDb Identify & WebP Artwork Store (PR #4)

**Branch:** `feat/pr-04-scanner-artwork-identify`

**Files:**
- Create: `backend/src/Hermes.Infrastructure/Media/{LibraryScanChannel,LibraryScanWorker,FfprobeMediaProbeService,TagLibAudioMetadataReader,SkiaArtworkStore,TmdbMetadataClient}.cs`
- Create: `backend/src/Hermes.Api/Features/Admin/{LibraryRootDtos,LibraryAdminEndpoints,IdentifyEndpoints}.cs`
- Create: `backend/src/Hermes.Api/Features/Streaming/ArtworkEndpoints.cs`
- Test: `backend/tests/Hermes.IntegrationTests/Media/LibraryScannerTests.cs`

**Interfaces:**
- Consumes: `HermesDbContext`, `IMediaProbeService`, `ITmdbClient`, `IArtworkStore`, Domain entities from Task 2
- Produces:
  - `POST /api/v1/admin/libraries`, `POST /api/v1/admin/libraries/scan`
  - `POST /api/v1/admin/media/{id}/identify` (sets `IsMetadataLocked = true` via Domain method)
  - `GET /api/v1/artwork/{hash}/{variant}` (`thumb_400.webp` | `poster_800.webp` | `backdrop_1280.webp` with `ETag` & `304 Not Modified`)

- [ ] **Step 1: Write failing scanner & artwork tests (including Review Focus #5: missing file resilience & DB-first TMDb skip)**

- [ ] **Step 2: Run tests to verify they fail**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter LibraryScannerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `LibraryScanChannel`, `LibraryScanWorker` (skips `Extras`/`Trailers`/`Sample`), `FfprobeMediaProbeService`, `TagLibAudioMetadataReader` (strictly read-only `using var tagFile = TagLib.File.Create(...)`), `SkiaArtworkStore`, and `Features/Admin/{LibraryAdminEndpoints,IdentifyEndpoints}`**

- [ ] **Step 4: Run scanner and artwork integration tests**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter LibraryScannerTests`
Expected: PASS (`Passed: 4, Failed: 0`).

- [ ] **Step 5: Commit PR #4**

```bash
git add backend/
git commit -m "feat(media): add UI-managed library roots, Channel<T> scanner, TMDb identify, and WebP artwork store"
```

---

### Task 5: Video/Audio Streaming Pipeline (Direct Play + FFmpeg HLS/Audio Quality Selectors + Subtitles) & Watch Progress (PR #5)

**Branch:** `feat/pr-05-streaming-ffmpeg-progress`

**Files:**
- Create: `backend/src/Hermes.Infrastructure/Media/{FfmpegTranscodeSessionManager,SubtitleExtractorService}.cs`
- Create: `backend/src/Hermes.Api/Features/Cinema/{CinemaDtos,CinemaEndpoints,WatchProgressEndpoints}.cs`
- Create: `backend/src/Hermes.Api/Features/Streaming/{StreamDtos,StreamEndpoints}.cs`
- Test: `backend/tests/Hermes.IntegrationTests/Streaming/{TranscodeSessionManagerTests,StreamingEndpointsTests}.cs`

**Interfaces:**
- Consumes: `IStreamTicketService` (Task 3), `MediaSource` & `MediaStream` (Task 4), `WatchProgress` domain entity (Task 2)
- Produces:
  - `GET /api/v1/streams/{mediaSourceId}/direct?ticket=...` (HTTP Range `206 Partial Content`)
  - `GET /api/v1/streams/{mediaSourceId}/video/master.m3u8?quality={1080p|720p|480p}&audioStreamIndex=...&startSeconds=...&ticket=...`
  - `GET /api/v1/streams/{mediaSourceId}/audio?quality={Lossless|VeryHigh320|High160|Medium96|Low64}&ticket=...` (Direct Play when `sourceBitrate <= targetBitrate`)
  - `GET /api/v1/streams/{mediaSourceId}/subtitles/{streamIndex}.vtt?ticket=...`
  - `PUT /api/v1/cinema/progress` -> broadcasts `WatchProgressUpdated` over SignalR user group

- [ ] **Step 1: Write failing tests for slot exhaustion (`429`, Review Focus #3), no-upscale audio Direct Play fallback, HTTP Range streaming, and WatchProgress >= 90% auto-watched rule**

- [ ] **Step 2: Run streaming tests to verify they fail**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter "FullyQualifiedName~Streaming"`
Expected: FAIL.

- [ ] **Step 3: Implement `FfmpegTranscodeSessionManager` (slot semaphore, process kill + temp dir cleanup on cancel/idle), `SubtitleExtractorService` (`.srt`/`.ass` -> `.vtt`), `Features/Cinema/`, and `Features/Streaming/`**

- [ ] **Step 4: Run streaming & progress tests to verify all pass**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter "FullyQualifiedName~Streaming"`
Expected: PASS (`Passed: 5, Failed: 0`).

- [ ] **Step 5: Commit PR #5**

```bash
git add backend/
git commit -m "feat(streaming): add Direct Play, FFmpeg video/audio quality transcoding, VTT subtitles, and WatchProgress sync"
```

---

### Task 6: Music Catalog, Native SQL Search, Playlists & SignalR v2 Monotonic Connect Sync (PR #6)

**Branch:** `feat/pr-06-music-signalr-v2`

**Files:**
- Create: `backend/src/Hermes.Infrastructure/Realtime/InMemoryDevicePresenceRegistry.cs`
- Create: `backend/src/Hermes.Api/Features/Music/{MusicDtos,MusicEndpoints,PlaylistEndpoints,PlaybackConnectService}.cs`
- Create: `backend/src/Hermes.Api/Hubs/PlaybackSyncHub.cs`
- Test: `backend/tests/Hermes.IntegrationTests/Realtime/PlaybackHubIntegrationTests.cs`

**Interfaces:**
- Consumes: `Song`, `Album`, `Artist`, `Playlist`, `PlaybackSession` (Task 2), `IDevicePresenceRegistry`, JWT auth (Task 3)
- Produces:
  - `PlaybackSessionStateDto(Guid SessionId, long Version, DateTimeOffset ServerTimestamp, string? ActiveRendererDeviceId, string? ActiveRendererDeviceName, Guid? CurrentSongId, List<PlaybackQueueItemDto> Queue, int CurrentIndex, long PositionMs, PlaybackState State, RepeatMode RepeatMode, bool Shuffle, double Volume, List<OnlineDeviceDto> OnlineDevices)`
  - Hub `/hubs/sync`: `RegisterDevice`, `SendTransportCommand`, `TransferOutput`, `ReportRendererProgress` -> broadcasts `SessionStateUpdated(PlaybackSessionStateDto)`

- [ ] **Step 1: Write failing multi-client `HubConnection` tests (including Review Focus #4: remote-control default on Device B, explicit `TransferOutput`, and active renderer disconnect auto-pause)**

- [ ] **Step 2: Run SignalR integration tests to verify they fail**

Run: `dotnet test backend/tests/Hermes.IntegrationTests --filter PlaybackHubIntegrationTests`
Expected: FAIL.

- [ ] **Step 3: Implement `MusicEndpoints` (`pg_trgm` single-query search, zero `Task.WhenAll` on `DbContext`), `PlaylistEndpoints`, `InMemoryDevicePresenceRegistry`, `PlaybackConnectService` (delegating mutations to `PlaybackSession` in Domain), and `PlaybackSyncHub`**

- [ ] **Step 4: Run full backend test suite (`UnitTests` + `IntegrationTests`)**

Run: `dotnet test backend/Hermes.slnx`
Expected: PASS (all unit and integration tests green, 0 warnings).

- [ ] **Step 5: Commit PR #6**

```bash
git add backend/
git commit -m "feat(sync): add native SQL music search, playlists, and SignalR v2 monotonic Spotify Connect sync"
```

---

### Task 7: Flutter Foundation, Multi-Endpoint Failover, Secure Auth & `Obsidian Crimson` Token Theme Engine (PR #7)

**Branch:** `feat/pr-07-flutter-foundation-theme`

**Files:**
- Create: `client/{pubspec.yaml,analysis_options.yaml}`
- Create: `client/lib/main.dart`
- Create: `client/lib/core/network/{endpoint_resolver.dart,hermes_api_client.dart,auth_interceptor.dart}`
- Create: `client/lib/core/storage/{secure_session_store.dart,artwork_cache_manager.dart}`
- Create: `client/lib/core/theme/{hermes_theme_tokens.dart,theme_controller.dart}`
- Create: `client/lib/features/shell/dual_world_shell.dart`
- Create: `client/lib/features/auth/{setup_screen.dart,login_screen.dart}`
- Modify: `.github/workflows/ci-client.yml`
- Test: `client/test/core/{endpoint_resolver_test.dart,theme_tokens_test.dart}`
- Test: `client/test/features/shell/dual_world_shell_test.dart`

**Interfaces:**
- Consumes: `/api/v1/system/info`, `/api/v1/setup`, `/api/v1/auth/*` from Task 3
- Produces:
  - `EndpointResolver.resolveActiveBaseUrl({required String primaryUrl, String? lanUrl, required String expectedServerId}) -> Future<String>`
  - `HermesThemeTokens` (`Obsidian Glow` default surface `#090B12`, `Crimson` default accent `#E11D48`, presets `obsidian` / `oled` / `slate`)
  - `DualWorldShell` (`ActiveWorld.cinema` | `ActiveWorld.music` top switcher)

- [ ] **Step 1: Scaffold Flutter Windows/Android app in `client/` and write failing unit & widget tests in `client/test/`**
- [ ] **Step 2: Run `flutter test` to verify tests fail**
- [ ] **Step 3: Implement `EndpointResolver`, `SecureSessionStore` (`flutter_secure_storage`), `ArtworkCacheManager`, `HermesThemeTokens` (`Obsidian Crimson` default), `SetupScreen`/`LoginScreen`, and `DualWorldShell`**
- [ ] **Step 4: Run `flutter analyze && flutter test` -> PASS (`No issues found!`)**
- [ ] **Step 5: Commit PR #7**

---

### Task 8: Flutter Cinema Experience, `1:N` Source Picker, `media_kit` Player with HDR/OpenGL Controls & Admin UI (PR #8)

**Branch:** `feat/pr-08-flutter-cinema-player-admin`

**Files:**
- Create: `client/lib/features/cinema/{cinema_home_screen.dart,media_details_screen.dart,source_selector_card.dart,video_player_screen.dart,video_player_controller.dart}`
- Create: `client/lib/features/settings/player_and_theme_settings_screen.dart`
- Create: `client/lib/features/admin/{admin_dashboard_screen.dart,library_roots_tab.dart,invites_and_users_tab.dart,identify_media_dialog.dart}`
- Test: `client/test/features/cinema/{media_details_source_picker_test.dart,video_player_hdr_config_test.dart}`

- [ ] **Step 1: Write failing tests for `libmpv` OpenGL/HDR subtitle config (`gpu-api=opengl`, `#D8D8D8`) and `1:N` Source + Quality selection**
- [ ] **Step 2: Run `flutter test test/features/cinema/` to verify failure**
- [ ] **Step 3: Implement Cinema screens, `VideoPlayerScreen` (`media_kit`), `PlayerAndThemeSettingsScreen`, and `AdminDashboardScreen`**
- [ ] **Step 4: Run `flutter analyze && flutter test` -> PASS**
- [ ] **Step 5: Commit PR #8**

---

### Task 9: Flutter Music Experience, Spotify-Style Quality Selector, SMTC/MediaSession & Monotonic Connect Sync (PR #9)

**Branch:** `feat/pr-09-flutter-music-connect`

**Files:**
- Create: `client/lib/features/music/{music_home_screen.dart,music_search_screen.dart,playlists_screen.dart,music_playback_coordinator.dart,mini_player_bar.dart,device_picker_sheet.dart,platform_media_bridge.dart}`
- Test: `client/test/features/music/music_playback_coordinator_test.dart`

- [ ] **Step 1: Write failing unit tests for `MusicPlaybackCoordinator` monotonic version guard (`dto.version <= lastAppliedVersion`) and Remote Control vs Local Renderer mode (Review Focus #4)**
- [ ] **Step 2: Run `flutter test test/features/music/music_playback_coordinator_test.dart` to verify failure**
- [ ] **Step 3: Implement `MusicPlaybackCoordinator`, `PlatformMediaBridge` (`audio_service` + `smtc_windows`), Wi-Fi/Cellular audio quality selector, `MusicHomeScreen`, `PlaylistsScreen`, `MiniPlayerBar`, and `DevicePickerSheet`**
- [ ] **Step 4: Run `flutter analyze && flutter test` -> PASS**
- [ ] **Step 5: Commit PR #9**

---

### Task 10: End-to-End Docker/LAN Validation with `<local-media-folder>`, Documentation & Public Showcase Polish (PR #10)

**Branch:** `chore/pr-10-showcase-polish`

**Files:**
- Modify: `README.md`
- Create: `docs/{ARCHITECTURE.md,CONTRIBUTING.md,SECURITY.md}`
- Create: `.github/{pull_request_template.md,ISSUE_TEMPLATE/bug_report.md}`
- Test: `backend/tests/Hermes.IntegrationTests/EndToEnd/FullStackSmokeTests.cs`

- [ ] **Step 1: Write E2E integration test verifying full lifecycle (First-Run Setup -> Add Library Root -> Scan -> Issue Stream Ticket -> Direct Play & HLS Manifest -> WatchProgress -> Music Connect Handoff)**
- [ ] **Step 2: Run `dotnet test backend/Hermes.slnx --configuration Release`, `flutter analyze`, `flutter test`, `flutter build windows --debug`, and verify zero secrets/paths in `git log -p`**
- [ ] **Step 3: Write portfolio-grade `README.md`, `ARCHITECTURE.md` (inclusiv ADR: *Vertical Slices + Pragmatic DDD*), `CONTRIBUTING.md`, and `SECURITY.md`, then commit PR #10**
