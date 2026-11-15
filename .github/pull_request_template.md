## Summary

<!-- Describe what this PR changes and why. Link the related feature slice or issue. -->

## Architectural & Security Checklist

- [ ] `Hermes.Domain` remains dependency-free (zero NuGet packages).
- [ ] Changes follow vertical slice organization (`Hermes.Api/Features/*`, `client/lib/src/features/*`).
- [ ] No secrets, `.env` credentials, or local filesystem paths are committed.
- [ ] Any new external process invocation uses `ArgumentList` (never shell string interpolation).

## Verification Performed

- [ ] `dotnet test backend/Hermes.slnx --configuration Release --verbosity minimal` (0 warnings, all tests passed)
- [ ] `dotnet list backend/Hermes.slnx package --vulnerable --include-transitive` (0 vulnerable packages)
- [ ] `cd client && flutter analyze --fatal-infos` (0 issues)
- [ ] `cd client && flutter test` (all tests passed)
