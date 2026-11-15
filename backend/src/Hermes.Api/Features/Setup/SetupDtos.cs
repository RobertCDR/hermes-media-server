namespace Hermes.Api.Features.Setup;

public sealed record SetupRequest(string Username, string Password, string ServerName);

public sealed record SetupResponse(Guid UserId, string Username, Guid ServerId, string ServerName);
