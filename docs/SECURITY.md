# Security Policy & Design Controls

## Supported Versions

Hermes Media Server follows active development on the `main` branch. Please report security issues responsibly rather than posting exploit details in public issues.

---

## Cryptographic & Authentication Controls

| Mechanism | Implementation | Details |
| :--- | :--- | :--- |
| **Password Storage** | `PasswordHasherAdapter` | PBKDF2-HMAC-SHA256 (`Rfc2898DeriveBytes.Pbkdf2`), `100,000` iterations, 16-byte cryptographic random salt, 32-byte derived key, constant-time comparison via `CryptographicOperations.FixedTimeEquals`. |
| **Access Tokens** | `JwtTokenService` | Short-lived **15-minute** HMAC-SHA256 JWTs signed with a configurable `>= 32`-byte `Security:JwtSigningKey`. |
| **Refresh Tokens** | `JwtTokenService` + `RefreshToken` | 32-byte cryptographically random opaque tokens, bound per `DeviceId`, rotated on every `/api/v1/auth/refresh` call (replaying an old token fails), and stored hashed (`SHA-256` uppercase hex). Password changes revoke all device refresh tokens. |
| **Onboarding** | `SetupEndpoints` + `InviteEndpoints` | First-run `/api/v1/setup` locks permanently after admin creation. Subsequent users require an admin-issued `InviteCode` with expiration and bounded `MaxUses`. |
| **Media Stream Tickets** | `HmacStreamTicketService` | Native players (`libmpv`, ExoPlayer, HTML/HLS fetchers) authenticate `/api/v1/streams/*` requests via short-lived, source-scoped HMAC-SHA256 `?ticket=...` tokens rather than passing long-lived bearer JWTs in query logs. Verified with `CryptographicOperations.FixedTimeEquals` and bound strictly to `expectedMediaSourceId` + Unix expiration timestamp. |

---

## Process, File & Container Hardening

- **No Shell Interpolation (`FFmpeg` / `FFprobe`)**: Media probes (`FfprobeMediaProbeService`) and transcoders (`FfmpegTranscodeSessionManager`, `SubtitleExtractorService`) pass arguments exclusively via `ProcessStartInfo.ArgumentList` with `UseShellExecute = false`.
- **Path Traversal Guard on HLS Assets**: `ResolveHlsAssetPath` enforces `Path.GetFileName(fileName) == fileName` and restricts extensions strictly to `.m3u8` and `.ts` inside active session directories.
- **Bounded Transcode Concurrency**: Simultaneous FFmpeg HLS sessions are capped by configured slot limits (`TryStartVideoHlsSessionAsync`), returning `429 Too Many Requests` (`transcode_slots_exhausted`) instead of exhausting host CPU/disk.
- **Non-Root Container Execution**: [deploy/Dockerfile](../deploy/Dockerfile) runs the API runtime under `$APP_UID` with read-only media mounts (`:ro` in [deploy/docker-compose.yml](../deploy/docker-compose.yml)); [deploy/docker-compose.yml](../deploy/docker-compose.yml) enforces required secrets (`POSTGRES_PASSWORD`, `HERMES_JWT_SECRET`, `HERMES_STREAM_TICKET_SECRET`) at Compose interpolation time.

---

## Automated Supply-Chain & Static Analysis

Configured in [security.yml](../.github/workflows/security.yml):
1. **NuGet Vulnerability Audit**: `NuGetAudit=true`, `NuGetAuditMode=all`, `NuGetAuditLevel=low` in `Directory.Build.props` plus `dotnet list backend/Hermes.slnx package --vulnerable --include-transitive`.
2. **Secret Scanning**: `gitleaks` full-history scan on pushes and pull requests.
3. **SAST**: GitHub **CodeQL** analysis for C# (`csharp`).
