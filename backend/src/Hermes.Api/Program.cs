using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.RateLimiting;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Cinema;
using Hermes.Api.Features.Music;
using Hermes.Api.Features.Setup;
using Hermes.Api.Features.Streaming;
using Hermes.Api.Features.System;
using Hermes.Api.Hubs;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Hermes.Infrastructure.Realtime;
using Hermes.Infrastructure.Security;
using Microsoft.AspNetCore.Authentication.JwtBearer;
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

builder.Services.AddHttpClient<ITmdbClient, TmdbMetadataClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddSingleton<IMediaProbeService, FfprobeMediaProbeService>();
builder.Services.AddSingleton<IAudioMetadataReader, TagLibAudioMetadataReader>();
builder.Services.AddSingleton<IArtworkStore>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var artworkDir = config["Hermes:ArtworkDirectory"];
    return new SkiaArtworkStore(string.IsNullOrWhiteSpace(artworkDir) ? "artwork-cache" : artworkDir);
});
builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var transcodeDir = config["Hermes:TranscodeDirectory"];
    return new FfmpegTranscodeSessionManager(string.IsNullOrWhiteSpace(transcodeDir) ? "transcodes" : transcodeDir);
});
builder.Services.AddSingleton<ITranscodeSessionManager>(sp => sp.GetRequiredService<FfmpegTranscodeSessionManager>());
builder.Services.AddSingleton<SubtitleExtractorService>();
builder.Services.AddSingleton<LrcLyricsService>();
builder.Services.AddSingleton<LibraryScanProgressTracker>();
builder.Services.AddSingleton<LibraryScanChannel>();
builder.Services.AddScoped<LibraryScannerService>();
builder.Services.AddHostedService<LibraryScanWorker>();
builder.Services.AddSingleton<LibraryWatcherService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<LibraryWatcherService>());
builder.Services.AddSingleton<IDevicePresenceRegistry, InMemoryDevicePresenceRegistry>();
builder.Services.AddSingleton<PlaybackSessionLockProvider>();
builder.Services.AddScoped<PlaybackConnectService>();
builder.Services.AddSignalR(options =>
{
    options.KeepAliveInterval = TimeSpan.FromSeconds(5);
    options.ClientTimeoutInterval = TimeSpan.FromSeconds(15);
});

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
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs/sync"))
                {
                    context.Token = accessToken;
                }

                return Task.CompletedTask;
            },
            OnTokenValidated = async context =>
            {
                if (context.Principal is null || !context.Principal.TryGetUserId(out var userId))
                {
                    context.Fail("missing_user_id");
                    return;
                }

                var db = context.HttpContext.RequestServices.GetRequiredService<HermesDbContext>();
                var userState = await db.Users
                    .AsNoTracking()
                    .Where(u => u.Id == userId)
                    .Select(u => new { u.IsActive, u.PasswordChangedAtUtc })
                    .SingleOrDefaultAsync(context.HttpContext.RequestAborted);

                if (userState is null || !userState.IsActive)
                {
                    context.Fail("user_inactive");
                    return;
                }

                if (userState.PasswordChangedAtUtc is { } pwdChangedAt)
                {
                    var iatMsClaim = context.Principal.FindFirst("iat_ms")?.Value;
                    var issuedAtUtc = long.TryParse(iatMsClaim, NumberStyles.Integer, CultureInfo.InvariantCulture, out var iatMs)
                        ? DateTimeOffset.FromUnixTimeMilliseconds(iatMs)
                        : new DateTimeOffset(DateTime.SpecifyKind(context.SecurityToken.ValidFrom, DateTimeKind.Utc));

                    if (issuedAtUtc < pwdChangedAt)
                    {
                        context.Fail("token_revoked");
                    }
                }
            }
        };
    });

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("AdminOnly", policy => policy.RequireRole(nameof(UserRole.Admin)));

var configuredCorsOrigins = builder.Configuration.GetSection("Hermes:CorsAllowedOrigins").Get<string[]>()?
    .Where(o => !string.IsNullOrWhiteSpace(o))
    .Select(o => o.Trim())
    .ToArray();

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        if (configuredCorsOrigins is { Length: > 0 })
        {
            policy.WithOrigins(configuredCorsOrigins)
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials();
        }
        else
        {
            policy.SetIsOriginAllowed(IsLocalOrPrivateNetworkOrigin)
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials();
        }
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("auth", httpContext =>
    {
        var partitionKey = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey,
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            });
    });
});

var app = builder.Build();

foreach (var (secretKey, minBytes) in new[] { ("Security:JwtSigningKey", 32), ("Security:StreamTicketSecret", 16) })
{
    var configuredValue = app.Configuration[secretKey];
    if (string.IsNullOrWhiteSpace(configuredValue) || Encoding.UTF8.GetByteCount(configuredValue) < minBytes)
    {
        app.Logger.LogWarning(
            "Generated an ephemeral runtime secret for {ConfigKey}. Configure a persistent key before deploying to production.",
            secretKey);
    }
}

try
{
    using var migrationScope = app.Services.CreateScope();
    var db = migrationScope.ServiceProvider.GetRequiredService<HermesDbContext>();
    if (await db.Database.CanConnectAsync())
    {
        await db.Database.MigrateAsync();

        if (!await db.MediaLibraryRoots.AnyAsync())
        {
            var defaultRoots = new (string Name, LibraryMediaType MediaType, string RootPath)[]
            {
                ("Movies", LibraryMediaType.Movies, "/media/Movies"),
                ("Series", LibraryMediaType.Series, "/media/Series"),
                ("Music", LibraryMediaType.Music, "/media/Music"),
            };

            var seeded = new List<MediaLibraryRoot>();
            foreach (var (name, mediaType, rootPath) in defaultRoots)
            {
                if (Directory.Exists(rootPath))
                {
                    seeded.Add(new MediaLibraryRoot(name, mediaType, rootPath, watchEnabled: true));
                }
            }

            if (seeded.Count > 0)
            {
                db.MediaLibraryRoots.AddRange(seeded);
                await db.SaveChangesAsync();
            }
        }

        var existingRootIds = await db.MediaLibraryRoots
            .Select(r => r.Id)
            .ToListAsync();
        if (existingRootIds.Count > 0)
        {
            var scanChannel = migrationScope.ServiceProvider.GetRequiredService<LibraryScanChannel>();
            foreach (var rootId in existingRootIds)
            {
                await scanChannel.EnqueueScanAsync(rootId, CancellationToken.None);
            }
        }
    }
}
catch (Exception ex)
{
    app.Logger.LogError(ex, "Startup database migration or initialization failed; continuing without DB bootstrap.");
}

app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapSystemEndpoints();
app.MapSetupEndpoints();
app.MapAuthEndpoints();
app.MapInviteEndpoints();
app.MapUserManagementEndpoints();
app.MapLibraryAdminEndpoints();
app.MapServerSettingsEndpoints();
app.MapIdentifyEndpoints();
app.MapAdminSessionEndpoints();
app.MapArtworkEndpoints();
app.MapCinemaEndpoints();
app.MapCustomListEndpoints();
app.MapWatchProgressEndpoints();
app.MapStreamEndpoints();
app.MapMusicEndpoints();
app.MapPlaylistEndpoints();
app.MapHub<PlaybackSyncHub>("/hubs/sync");

await app.RunAsync();

static bool IsLocalOrPrivateNetworkOrigin(string origin)
{
    if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri) ||
        (!string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
         !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)))
    {
        return false;
    }

    var host = uri.Host;
    if (uri.IsLoopback ||
        string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase) ||
        host.EndsWith(".local", StringComparison.OrdinalIgnoreCase) ||
        host.EndsWith(".ts.net", StringComparison.OrdinalIgnoreCase))
    {
        return true;
    }

    if (!IPAddress.TryParse(host, out var ip))
    {
        return false;
    }

    if (ip.IsIPv4MappedToIPv6)
    {
        ip = ip.MapToIPv4();
    }

    if (IPAddress.IsLoopback(ip))
    {
        return true;
    }

    if (ip.AddressFamily == AddressFamily.InterNetwork)
    {
        var bytes = ip.GetAddressBytes();
        return bytes[0] == 10 ||
               (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
               (bytes[0] == 192 && bytes[1] == 168) ||
               (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127) ||
               (bytes[0] == 169 && bytes[1] == 254);
    }

    if (ip.AddressFamily == AddressFamily.InterNetworkV6)
    {
        var bytes = ip.GetAddressBytes();
        return ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || (bytes[0] & 0xFE) == 0xFC;
    }

    return false;
}

public partial class Program;
