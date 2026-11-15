namespace Hermes.Api.Features.System;

public sealed record SystemInfoDto(
    Guid ServerId,
    string ServerName,
    string Version,
    bool SetupCompleted);
