# Contributing to Hermes Media Server

Thank you for contributing to **Hermes Media Server**. Please follow the architectural rules, test practices, and verification steps below.

---

## Prerequisites

- **.NET 10 SDK** (`10.0.401` per [global.json](../global.json))
- **Flutter `3.50.0`** / **Dart `3.14.0`**
- **Docker** (required for running `Hermes.IntegrationTests` against ephemeral `postgres:17` containers via Testcontainers)
- **FFmpeg & FFprobe** installed on `PATH`

---

## Engineering & Architecture Rules

1. **Maintain Layer Boundaries**:
   - `Hermes.Domain` must keep **zero NuGet package references**.
   - Business invariants (e.g., 90% auto-watched threshold, Connect monotonic `Version`, password hashing/ticket contracts via interfaces) belong in `Hermes.Domain`.
   - New backend API features should be self-contained under `backend/src/Hermes.Api/Features/<Slice>/`.
2. **Compiler & Analyzer Strictness**:
   - Backend builds with `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<Nullable>enable</Nullable>`, and `NuGetAuditMode=all` (see [Directory.Build.props](../backend/Directory.Build.props)).
   - Flutter code uses `package:material_ui/material_ui.dart` and must pass `flutter analyze --fatal-infos` with **zero issues**.
3. **Test-Driven Changes**:
   - Add unit tests in `backend/tests/Hermes.UnitTests/` or `client/test/`.
   - Add Postgres + Testcontainers API/FFmpeg/SignalR integration tests in `backend/tests/Hermes.IntegrationTests/`.
4. **No Secrets or Machine-Specific Paths**:
   - Never commit `.env` files, API keys, JWT signing keys, or user-specific filesystem paths.

---

## Verification Checklist Before Opening a PR

Run all checks locally from the repository root:

```bash
# 1. Backend build, architecture rules, unit & integration tests (Release)
dotnet test backend/Hermes.slnx --configuration Release --verbosity minimal

# 2. Transitive NuGet security audit
dotnet list backend/Hermes.slnx package --vulnerable --include-transitive

# 3. Flutter static analysis and unit/widget tests
cd client
flutter analyze --fatal-infos
flutter test
```

All PRs targeting `main` are validated by GitHub Actions:
- [CI Backend (.NET 10)](../.github/workflows/ci-backend.yml)
- [CI Client (Flutter)](../.github/workflows/ci-client.yml)
- [Docker Build Check](../.github/workflows/docker.yml)
- [Security & Supply Chain](../.github/workflows/security.yml)
