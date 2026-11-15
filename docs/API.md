# Hermes Media Server — REST & SignalR API Reference

Base URL (local development / Docker Compose default): `http://localhost:5258`

All timestamps are serialized as ISO 8601 UTC (`DateTimeOffset`). Request and response payloads use camelCase JSON.

---

## Authentication & Security Model

- **Bearer JWT Access Tokens**: Protected endpoints require `Authorization: Bearer <accessToken>`. Access tokens carry the user's ID, username, role (`Admin` or `Member`), issuer (`HermesMediaServer`), and audience (`HermesClients`).
- **Opaque Refresh Tokens**: Issued per device (`deviceId` + `deviceName`) with 30-day TTL and rotated on every `/api/v1/auth/refresh` call.
- **HMAC-SHA256 Stream Tickets**: Media playback endpoints (`/api/v1/streams/...`) are `.AllowAnonymous()` so native video/audio players (`<video>`, mpv, ExoPlayer) can fetch ranges and HLS playlists directly using `?ticket=<signedTicket>` scoped to `userId` and `targetId` (6-hour TTL).
- **Rate Limiting**: Setup and authentication routes enforce the `"auth"` fixed-window policy (`100` requests/minute; returns `429 Too Many Requests` when exceeded).

---

## 1. System & First-Run Setup

### `GET /health/live`
- **Auth**: Anonymous
- **Response (`200 OK`)**: `{ "status": "Healthy" }`

### `GET /api/v1/system/info`
- **Auth**: Anonymous
- **Response (`200 OK`)**: `SystemInfoDto`
  ```json
  {
    "serverId": "guid",
    "serverName": "Hermes Media Server",
    "version": "1.0.0",
    "setupCompleted": false
  }
  ```

### `POST /api/v1/setup`
Creates the initial `Admin` account and `ServerSettings` inside a PostgreSQL transaction guarded by `pg_advisory_xact_lock(424242)`.
- **Auth**: Anonymous (rate-limited)
- **Request Body (`SetupRequest`)**:
  ```json
  {
    "username": "admin",
    "password": "minimum-8-characters",
    "serverName": "Hermes Media Server"
  }
  ```
- **Responses**:
  - `201 Created`: `SetupResponse` (`userId`, `username`, `serverId`, `serverName`)
  - `400 Bad Request`: `invalid_username`, `password_too_short`, `invalid_server_name`
  - `409 Conflict`: `setup_already_completed`

---

## 2. Authentication & Stream Tickets (`/api/v1/auth`)

### `POST /api/v1/auth/register`
Registers a `Member` account using an admin-issued invite code.
- **Auth**: Anonymous (rate-limited)
- **Request Body (`RegisterRequest`)**: `{ "username", "password", "inviteCode" }`
- **Responses**: `201 Created` (`RegisterResponse`: `userId`, `username`), `400 Bad Request` (`invalid_username`, `password_too_short`, `invalid_invite_code`, `invalid_or_expired_invite`), `409 Conflict` (`username_already_exists`)

### `POST /api/v1/auth/login`
Authenticates user credentials, revokes prior active tokens for the same `deviceId`, and issues a new device session.
- **Auth**: Anonymous (rate-limited)
- **Request Body (`LoginRequest`)**: `{ "username", "password", "deviceId", "deviceName" }`
- **Responses**: `200 OK` (`AuthTokenResponse`: `accessToken`, `refreshToken`, `userId`, `username`, `role`), `400 Bad Request`, `401 Unauthorized`

### `POST /api/v1/auth/refresh`
Rotates an active opaque refresh token bound to `deviceId`.
- **Auth**: Anonymous (rate-limited)
- **Request Body (`RefreshTokenRequest`)**: `{ "deviceId", "refreshToken" }`
- **Responses**: `200 OK` (`AuthTokenResponse`), `401 Unauthorized`

### `POST /api/v1/auth/reset-password`
Resets password using a one-time reset code issued by an administrator.
- **Auth**: Anonymous (rate-limited)
- **Request Body (`ResetPasswordRequest`)**: `{ "username", "resetCode", "newPassword" }`
- **Responses**: `200 OK` (`{ "reset": true }`), `400 Bad Request` (`invalid_reset_request`, `invalid_or_expired_reset_code`)

### `POST /api/v1/auth/change-password`
Updates the signed-in user's password and revokes active refresh sessions.
- **Auth**: Bearer JWT (`Member` or `Admin`)
- **Request Body (`ChangePasswordRequest`)**: `{ "currentPassword", "newPassword" }`
- **Responses**: `200 OK` (`{ "changed": true }`), `400 Bad Request`, `401 Unauthorized`

### `POST /api/v1/auth/stream-tickets`
Mints a signed 6-hour HMAC-SHA256 stream ticket scoped to `mediaSourceId` (or `songId` for audio).
- **Auth**: Bearer JWT
- **Request Body (`CreateStreamTicketRequest`)**: `{ "mediaSourceId": "guid" }`
- **Responses**: `200 OK` (`StreamTicketResponse`: `ticket`, `expiresAtUtc`), `400 Bad Request` (`invalid_media_source_id`), `401 Unauthorized`

---

## 3. Administration (`/api/v1/admin`)

All endpoints require the `AdminOnly` authorization policy (`Role == Admin`).

### Invites
- `POST /api/v1/admin/invites` — Body (`CreateInviteRequest`): `{ "maxUses": 1, "expiresInHours": 24 }` -> `201 Created` (`InviteResponse`: `id`, `code`, `maxUses`, `usedCount`, `expiresAtUtc`, `isRevoked`)
- `GET /api/v1/admin/invites` -> `200 OK` (`InviteResponse[]`)

### Users
- `GET /api/v1/admin/users` -> `200 OK` (`UserSummaryDto[]`: `id`, `username`, `role`, `isActive`, `createdAtUtc`)
- `POST /api/v1/admin/users/{id:guid}/reset-code` -> `200 OK` (`ResetCodeResponse`: `resetCode`, `expiresAtUtc`), or `404 Not Found` (`user_not_found`)

### Media Libraries & Metadata Matching
- `POST /api/v1/admin/libraries` — Body (`CreateLibraryRootRequest`): `{ "name", "mediaType": "Movies" | "Series" | "Music", "rootPath", "watchEnabled": true }` -> `201 Created` (`LibraryRootResponse`), `400 Bad Request`, `409 Conflict`
- `GET /api/v1/admin/libraries` -> `200 OK` (`LibraryRootResponse[]`)
- `POST /api/v1/admin/libraries/{id:guid}/scan` — Runs library scan synchronously -> `200 OK` (`LibraryScanSummaryDto`: `libraryRootId`, `filesDiscovered`, `sourcesUpserted`, `sourcesMarkedMissing`, `completedAtUtc`), `404 Not Found`
- `POST /api/v1/admin/libraries/{id:guid}/scan/queue` — Enqueues background scan via `LibraryScanChannel` -> `202 Accepted`, `404 Not Found`
- `POST /api/v1/admin/media/{id:guid}/identify` — Locks TMDB match & downloads artwork on Movie or TV Series. Body (`IdentifyMediaRequest`): `{ "tmdbId": 123, "title": "...", "year": 2024, "overview": "..." }` -> `200 OK` (`IdentifyMediaResponse`), `400 Bad Request`, `404 Not Found`

---

## 4. Cinema (`/api/v1/cinema`)

All endpoints require authentication (`Bearer` JWT).

### `GET /api/v1/cinema/movies`
Returns all indexed movies ordered by title with per-user `WatchProgressDto` and available `MediaSourceDto[]` + `MediaStreamDto[]`.

### `GET /api/v1/cinema/movies/{id:guid}`
Returns `MovieSummaryDto` for the specified movie, or `404 Not Found` (`movie_not_found`).

### `GET /api/v1/cinema/series`
Returns `TvSeriesSummaryDto[]` including nested `TvSeasonDto[]` -> `EpisodeSummaryDto[]` with per-episode watch progress and sources.

### `PUT /api/v1/cinema/progress`
Persists watch position (`PositionMs` / `DurationMs`), evaluates the 90% auto-watched rule (unless overridden by `MarkWatched`), and broadcasts `WatchProgressUpdated` over SignalR.
- **Request Body (`UpdateWatchProgressRequest`)**:
  ```json
  {
    "movieId": "guid-or-null",
    "episodeId": "guid-or-null",
    "positionMs": 120000,
    "durationMs": 7200000,
    "markWatched": null
  }
  ```
- **Responses**: `200 OK` (`WatchProgressDto`), `400 Bad Request` (`specify_movie_or_episode`), `404 Not Found` (`movie_not_found` / `episode_not_found`)

---

## 5. Music, Playlists & Unified Search

All endpoints require authentication (`Bearer` JWT).

### Music (`/api/v1/music`)
- `GET /api/v1/music/artists` -> `ArtistSummaryDto[]` (`id`, `name`, `artworkHash`, `albumCount`)
- `GET /api/v1/music/artists/{id:guid}` -> `ArtistDetailDto` (`albums`, `songs`) or `404 Not Found` (`artist_not_found`)
- `GET /api/v1/music/albums` -> `AlbumSummaryDto[]`
- `GET /api/v1/music/albums/{id:guid}` -> `AlbumDetailDto` (`songs`) or `404 Not Found` (`album_not_found`)
- `GET /api/v1/music/songs` -> `SongDto[]` (ordered by Artist, Album, DiscNumber, TrackNumber, Title; includes `isLiked` and `isMissing`)
- `GET /api/v1/music/songs/liked` -> `SongDto[]` (most recently liked first)
- `POST /api/v1/music/songs/{id:guid}/like` -> `200 OK` (`LikeToggleResponse`: `songId`, `isLiked`), or `404 Not Found`
- `GET /api/v1/music/session` -> `PlaybackSessionDto` (fetches or initializes the user's Connect playback state)
- `GET /api/v1/music/devices` -> `OnlineDeviceDto[]` (`deviceId`, `deviceName`, `platform`, `connectedAtUtc`)

### Playlists (`/api/v1/music/playlists`)
- `GET /api/v1/music/playlists/` -> `PlaylistSummaryDto[]`
- `GET /api/v1/music/playlists/{id:guid}` -> `PlaylistDetailDto` (`tracks`: `{ position, song }[]`) or `404 Not Found`
- `POST /api/v1/music/playlists/` — Body (`CreatePlaylistRequest`): `{ "name", "description" }` -> `201 Created` (`PlaylistDetailDto`)
- `POST /api/v1/music/playlists/{id:guid}/tracks` — Body (`AddPlaylistTrackRequest`): `{ "songId" }` -> `200 OK` (`PlaylistDetailDto`)
- `DELETE /api/v1/music/playlists/{id:guid}/tracks/{position:int}` — Removes track at `position` and compacts subsequent positions inside a transaction -> `200 OK` (`PlaylistDetailDto`), `404 Not Found`

### Unified Search
- `GET /api/v1/search?q={query}` -> `200 OK` (`UnifiedSearchResponse`: `query`, `movies`, `series`, `artists`, `albums`, `songs`) backed by PostgreSQL `pg_trgm` `ILIKE`.

---

## 6. Streaming & Artwork

### Video & Audio Streams (`/api/v1/streams`)
All stream routes validate `?ticket=<signedTicket>` against the target GUID:
- `GET /api/v1/streams/{mediaSourceId:guid}/direct?ticket=...` — Byte-range streaming (`Accept-Ranges: bytes`, `206 Partial Content`)
- `GET /api/v1/streams/{mediaSourceId:guid}/video/master.m3u8?quality=direct|480p|720p|1080p&audioStreamIndex=1&startSeconds=0&ticket=...` — Returns HLS master playlist (`X-Hermes-Transcode-Session` header for transcoded sessions, `429 transcode_slots_exhausted` if busy)
- `GET /api/v1/streams/{mediaSourceId:guid}/hls/{sessionId:guid}/{assetName}?ticket=...` — Serves `.m3u8` (rewritten with `?ticket=...`) and `.ts` media segments
- `DELETE /api/v1/streams/{mediaSourceId:guid}/hls/{sessionId:guid}?ticket=...` — Terminates FFmpeg session and cleans segment temp directory (`204 No Content`)
- `GET /api/v1/streams/{targetId:guid}/audio?quality=lossless|veryhigh|high|medium|low&ticket=...` — Streams Song or MediaSource audio with strict zero-upscale (`X-Hermes-Delivery: DirectPlay` or `Transcoded`)
- `GET /api/v1/streams/{mediaSourceId:guid}/subtitles/{streamIndex:int}.vtt?ticket=...` — Extracts or converts subtitles to `text/vtt`

### Artwork (`/api/v1/artwork`)
- `GET /api/v1/artwork/{hash}/{variant}` (`AllowAnonymous`) — Serves immutable WebP thumbnails (`Cache-Control: public,max-age=31536000,immutable`, `ETag` with `304 Not Modified` support).

---

## 7. Real-Time Sync Hub (`/hubs/sync`)

Connect with SignalR (`access_token` query parameter supported for WebSockets alongside query metadata `deviceId`, `deviceName`, `platform`).

### Client-to-Server Hub Methods
| Method | Parameter | Return / Effect |
|---|---|---|
| `StartPlayback` | `StartPlaybackCommand(queueSongIds, startIndex)` | Sets caller as `ActiveRendererDeviceId`, broadcasts `SessionStateUpdated` |
| `SendTransportCommand` | `RemoteTransportCommand(state, currentIndex, positionMs, repeatMode, shuffle, volume)` | Applies play/pause/seek/volume/shuffle/repeat without changing active renderer, broadcasts `SessionStateUpdated` |
| `TransferOutput` | `TransferOutputCommand(targetDeviceId)` | Transfers `ActiveRendererDeviceId` cleanly, broadcasts `SessionStateUpdated` |
| `ReportProgress` | `ProgressHeartbeatCommand(positionMs)` | Updates `PositionMs` only if caller is the active renderer, broadcasts `SessionStateUpdated` |
| `GetOnlineDevices` | *(none)* | Returns `OnlineDeviceDto[]` for the signed-in user |

### Server-to-Client Events (User Group `user:{userId:D}`)
- `SessionStateUpdated(PlaybackSessionDto)` — Sent on connect, playback mutations, progress heartbeats, and automatic pause when the active renderer disconnects
- `DevicesUpdated(OnlineDeviceDto[])` — Sent when a user device connects or disconnects
- `WatchProgressUpdated(WatchProgressUpdatedEvent)` — Sent when `PUT /api/v1/cinema/progress` updates movie/episode progress
