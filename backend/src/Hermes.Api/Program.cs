using System.Collections.Concurrent;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Setup;
using Hermes.Api.Features.Streaming;
using Hermes.Api.Features.System;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Hermes.Infrastructure.Security;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);
var ephemeralSecrets = new ConcurrentDictionary<string, string>(StringComparer.Ordinal);

string GetOrCreateSecret(IConfiguration configuration, string key, int minimumBytes)
{
    var configured = configuration[key];
    if (!string.IsNullOrWhiteSpace(configured) && Encoding.UTF8.GetByteCount(configured) >= minimumBytes)
    {
        return configured;
    }

    return ephemeralSecrets.GetOrAdd(
        key,
        _ => Convert.ToHexString(RandomNumberGenerator.GetBytes(Math.Max(minimumBytes, 32))));
}

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IPasswordHasher, PasswordHasherAdapter>();
builder.Services.AddSingleton<ITokenService>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    return new JwtTokenService(
        GetOrCreateSecret(config, "Security:JwtSigningKey", 32),
        config["Security:JwtIssuer"] ?? "HermesMediaServer",
        config["Security:JwtAudience"] ?? "HermesClients",
        sp.GetRequiredService<TimeProvider>());
});
builder.Services.AddSingleton<IStreamTicketService>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    return new HmacStreamTicketService(
        GetOrCreateSecret(config, "Security:StreamTicketSecret", 16),
        sp.GetRequiredService<TimeProvider>());
});

builder.Services.AddHttpClient<ITmdbClient, TmdbMetadataClient>();
builder.Services.AddSingleton<IMediaProbeService, FfprobeMediaProbeService>();
builder.Services.AddSingleton<IAudioMetadataReader, TagLibAudioMetadataReader>();
builder.Services.AddSingleton<IArtworkStore>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var artworkDir = config["Hermes:ArtworkDirectory"];
    return new SkiaArtworkStore(string.IsNullOrWhiteSpace(artworkDir) ? "artwork-cache" : artworkDir);
});
builder.Services.AddSingleton<LibraryScanChannel>();
builder.Services.AddScoped<LibraryScannerService>();
builder.Services.AddHostedService<LibraryScanWorker>();

builder.Services.AddDbContext<HermesDbContext>((sp, options) =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var connectionString = config.GetConnectionString("Postgres")
        ?? "Host=localhost;Port=5432;Database=hermes;Username=hermes;Password=hermes;Timeout=2";
    options.UseNpgsql(connectionString);
});

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IConfiguration>((options, config) =>
    {
        var signingKey = GetOrCreateSecret(config, "Security:JwtSigningKey", 32);
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = config["Security:JwtIssuer"] ?? "HermesMediaServer",
            ValidateAudience = true,
            ValidAudience = config["Security:JwtAudience"] ?? "HermesClients",
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireRole(nameof(UserRole.Admin)));

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddFixedWindowLimiter("auth", limiter =>
    {
        limiter.PermitLimit = 100;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
    });
});

var app = builder.Build();

app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapSystemEndpoints();
app.MapSetupEndpoints();
app.MapAuthEndpoints();
app.MapInviteEndpoints();
app.MapUserManagementEndpoints();
app.MapLibraryAdminEndpoints();
app.MapIdentifyEndpoints();
app.MapArtworkEndpoints();

await app.RunAsync();

public partial class Program;
