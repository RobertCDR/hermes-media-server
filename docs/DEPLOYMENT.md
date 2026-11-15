# Hermes Media Server — Deployment & Development Setup Guide

This guide covers containerized deployment with Docker Compose, local IDE debugging in **Visual Studio 2026** and **VS Code**, remote access via **Tailscale**, and backup procedures.

---

## 1. Docker Compose Stack (`hermes`)

The Compose definition at [deploy/docker-compose.yml](../deploy/docker-compose.yml) sets `name: hermes` and provisions two containers:

- **`hermes-postgres`**: `postgres:17-alpine` with health check (`pg_isready`) and persistent volume `hermes_pgdata`
- **`hermes-api`**: .NET 10 runtime with `ffmpeg`/`ffprobe` installed, auto-applying pending EF Core migrations on startup and binding `${HERMES_PORT:-5258}:8080`

### Setup Steps

1. Create `deploy/.env` from the template:
   ```bash
   cp deploy/.env.example deploy/.env
   ```

2. Generate cryptographic secrets (minimum 32 characters) and configure `HERMES_MEDIA_PATH`:
   - `POSTGRES_PASSWORD`: Strong database password
   - `HERMES_JWT_SECRET`: Symmetric HMAC key for JWT signing
   - `HERMES_STREAM_TICKET_SECRET`: Symmetric HMAC key for expiring media stream tickets
   - `HERMES_TMDB_API_KEY` *(optional)*: TMDB API key for metadata enrichment & artwork fetching
   - `HERMES_MEDIA_PATH`: Host directory mounted read-only at `/media` inside `hermes-api`

3. Build and start the `hermes` stack:
   ```bash
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
   ```

4. Verify containers and API health:
   ```bash
   docker ps --filter "name=hermes"
   curl -s http://localhost:5258/health/live
   curl -s http://localhost:5258/api/v1/system/info
   ```

> [!NOTE]
> `deploy/.env` is excluded by `.gitignore` and must never be committed to version control.

---

## 2. Visual Studio 2026 & VS Code Startup Profiles

### Visual Studio 2026 (`backend/Hermes.slnx`)
Opening [backend/Hermes.slnx](../backend/Hermes.slnx) automatically loads [backend/src/Hermes.Api/Properties/launchSettings.json](../backend/src/Hermes.Api/Properties/launchSettings.json) with three startup profiles for `Hermes.Api`:

| Profile | Environment | URL | Browser Launch |
|---|---|---|---|
| `Hermes.Api (Local Dev)` | `Development` | `http://localhost:5258` | Opens `/api/v1/system/info` |
| `Hermes.Api (Headless Dev)` | `Development` | `http://localhost:5258` | Disabled |
| `Hermes.Api (Production Mode)` | `Production` | `http://localhost:5258` | Disabled |

To connect local Visual Studio runs to a dedicated PostgreSQL instance with persistent JWT keys, store local overrides outside Git using **.NET User Secrets**:
```bash
dotnet user-secrets init --project backend/src/Hermes.Api/Hermes.Api.csproj
dotnet user-secrets set "ConnectionStrings:Postgres" "Host=localhost;Port=5432;Database=hermes;Username=hermes;Password=<your-local-password>" --project backend/src/Hermes.Api/Hermes.Api.csproj
dotnet user-secrets set "Security:JwtSigningKey" "<min-32-char-secret>" --project backend/src/Hermes.Api/Hermes.Api.csproj
dotnet user-secrets set "Security:StreamTicketSecret" "<min-32-char-secret>" --project backend/src/Hermes.Api/Hermes.Api.csproj
```
If `JwtSigningKey` / `StreamTicketSecret` are omitted in local development, `Hermes.Api` generates ephemeral CSPRNG keys in memory per run so `F5` starts cleanly out of the box.

### VS Code Launch Configurations (`.vscode/launch.json`)
The repository provides ready-to-run VS Code debug profiles in [.vscode/launch.json](../.vscode/launch.json) and tasks in [.vscode/tasks.json](../.vscode/tasks.json):
- `Hermes.Api (.NET 10 - Local Dev)`
- `Hermes Client (Flutter Web - Edge)`
- `Hermes Client (Flutter Windows Desktop)` *(requires Visual Studio **"Desktop development with C++"** workload)*
- Compound: `Hermes Full Stack (API + Web Client)`

---

## 3. Remote Access (Tailscale & Reverse Proxy)

### Tailscale Dual-Endpoint Failover
Hermes clients natively accept two server URLs in `EndpointResolver`:
1. **Primary (Tailscale)**: e.g., `https://hermes.tailnet-name.ts.net` (1.5s probe timeout)
2. **LAN Fallback**: e.g., `http://192.168.1.50:5258`

When probing, the client compares the returned `serverId` from `/api/v1/system/info` to ensure failover connects to the exact same Hermes instance.

### Reverse Proxy Requirements (Nginx / Caddy)
Ensure your reverse proxy enables WebSocket upgrades for SignalR (`/hubs/sync`) and disables response buffering for byte-range & HLS streaming:
```nginx
location /hubs/sync {
    proxy_pass http://127.0.0.1:5258;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}

location / {
    proxy_pass http://127.0.0.1:5258;
    proxy_buffering off;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

---

## 4. Backup & Restore

### PostgreSQL Backup
```bash
docker exec -t hermes-postgres pg_dump -U hermes -d hermes -Fc > hermes-backup.dump
```

### PostgreSQL Restore
```bash
cat hermes-backup.dump | docker exec -i hermes-postgres pg_restore -U hermes -d hermes --clean --if-exists
```
