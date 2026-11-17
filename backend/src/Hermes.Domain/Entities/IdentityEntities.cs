using Hermes.Domain.Enums;

namespace Hermes.Domain.Entities;

public sealed class User
{
    private readonly List<RefreshToken> _refreshTokens = [];

    private User()
    {
        Username = string.Empty;
        PasswordHash = string.Empty;
        PreferredAccentHex = "#E11D48";
        SubtitleSize = "medium";
        SubtitleBackground = "shadow";
    }

    private User(Guid id, string username, string passwordHash, UserRole role, DateTimeOffset createdAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(username);
        ArgumentException.ThrowIfNullOrWhiteSpace(passwordHash);

        Id = id;
        Username = username.Trim();
        PasswordHash = passwordHash;
        Role = role;
        IsActive = true;
        CreatedAtUtc = createdAtUtc;
        PreferredSurfacePreset = ThemeSurfacePreset.ObsidianGlow;
        PreferredAccentHex = "#E11D48";
        AutoplayNextEpisode = true;
        NormalizeVolume = false;
        MatchTitleColors = true;
        SubtitleSize = "medium";
        SubtitleBackground = "shadow";
    }

    public Guid Id { get; private set; }
    public string Username { get; private set; }
    public string PasswordHash { get; private set; }
    public UserRole Role { get; private set; }
    public bool IsActive { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset? PasswordChangedAtUtc { get; private set; }
    public string? OneTimeResetCodeHash { get; private set; }
    public DateTimeOffset? OneTimeResetExpiresAtUtc { get; private set; }
    public ThemeSurfacePreset PreferredSurfacePreset { get; private set; }
    public string PreferredAccentHex { get; private set; }
    public bool AutoplayNextEpisode { get; private set; } = true;
    public bool NormalizeVolume { get; private set; }
    public bool MatchTitleColors { get; private set; } = true;
    public string SubtitleSize { get; private set; } = "medium";
    public string SubtitleBackground { get; private set; } = "shadow";

    private static readonly HashSet<string> ValidSubtitleSizes =
        new(["small", "medium", "large", "xl"], StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> ValidSubtitleBackgrounds =
        new(["none", "shadow", "box"], StringComparer.OrdinalIgnoreCase);

    public ICollection<RefreshToken> RefreshTokens => _refreshTokens;

    public static User Create(string username, string passwordHash, UserRole role, DateTimeOffset utcNow) =>
        new(Guid.NewGuid(), username, passwordHash, role, utcNow);

    public void ChangePassword(string newPasswordHash, DateTimeOffset utcNow)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(newPasswordHash);
        PasswordHash = newPasswordHash;
        PasswordChangedAtUtc = utcNow;
        OneTimeResetCodeHash = null;
        OneTimeResetExpiresAtUtc = null;

        foreach (var token in _refreshTokens)
        {
            token.Revoke(utcNow);
        }
    }

    public void SetOneTimeResetCode(string codeHash, DateTimeOffset expiresAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(codeHash);
        OneTimeResetCodeHash = codeHash;
        OneTimeResetExpiresAtUtc = expiresAtUtc;
    }

    public void UpdateThemePreferences(ThemeSurfacePreset surfacePreset, string accentHex)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accentHex);
        PreferredSurfacePreset = surfacePreset;
        PreferredAccentHex = accentHex.Trim();
    }

    public void UpdateAccountPreferences(
        bool autoplayNextEpisode,
        bool normalizeVolume,
        bool matchTitleColors,
        string subtitleSize,
        string subtitleBackground)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitleSize);
        ArgumentException.ThrowIfNullOrWhiteSpace(subtitleBackground);

        var normalizedSize = subtitleSize.Trim().ToLowerInvariant();
        if (!ValidSubtitleSizes.Contains(normalizedSize))
        {
            throw new ArgumentException($"Unsupported subtitle size '{subtitleSize}'.", nameof(subtitleSize));
        }

        var normalizedBg = subtitleBackground.Trim().ToLowerInvariant();
        if (!ValidSubtitleBackgrounds.Contains(normalizedBg))
        {
            throw new ArgumentException($"Unsupported subtitle background '{subtitleBackground}'.", nameof(subtitleBackground));
        }

        AutoplayNextEpisode = autoplayNextEpisode;
        NormalizeVolume = normalizeVolume;
        MatchTitleColors = matchTitleColors;
        SubtitleSize = normalizedSize;
        SubtitleBackground = normalizedBg;
    }

    public void Deactivate(DateTimeOffset utcNow)
    {
        IsActive = false;
        foreach (var token in _refreshTokens)
        {
            token.Revoke(utcNow);
        }
    }
}

public sealed class RefreshToken
{
    private RefreshToken()
    {
        DeviceId = string.Empty;
        DeviceName = string.Empty;
        TokenHash = string.Empty;
    }

    private RefreshToken(Guid id, Guid userId, string deviceId, string deviceName, string tokenHash, DateTimeOffset expiresAtUtc, DateTimeOffset createdAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);
        ArgumentException.ThrowIfNullOrWhiteSpace(tokenHash);

        Id = id;
        UserId = userId;
        DeviceId = deviceId.Trim();
        DeviceName = deviceName.Trim();
        TokenHash = tokenHash;
        ExpiresAtUtc = expiresAtUtc;
        CreatedAtUtc = createdAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public string DeviceId { get; private set; }
    public string DeviceName { get; private set; }
    public string TokenHash { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset ExpiresAtUtc { get; private set; }
    public DateTimeOffset? RevokedAtUtc { get; private set; }

    public User User { get; private set; } = null!;

    public static RefreshToken Create(Guid userId, string deviceId, string deviceName, string tokenHash, DateTimeOffset expiresAtUtc, DateTimeOffset utcNow) =>
        new(Guid.NewGuid(), userId, deviceId, deviceName, tokenHash, expiresAtUtc, utcNow);

    public bool IsActive(DateTimeOffset utcNow) =>
        RevokedAtUtc is null && utcNow < ExpiresAtUtc;

    public void Revoke(DateTimeOffset utcNow)
    {
        RevokedAtUtc ??= utcNow;
    }
}

public sealed class InviteCode
{
    private InviteCode()
    {
        Code = string.Empty;
    }

    private InviteCode(Guid id, Guid createdByUserId, string code, int maxUses, DateTimeOffset expiresAtUtc, DateTimeOffset createdAtUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(code);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxUses, 1);

        Id = id;
        CreatedByUserId = createdByUserId;
        Code = code.Trim();
        MaxUses = maxUses;
        ExpiresAtUtc = expiresAtUtc;
        CreatedAtUtc = createdAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid CreatedByUserId { get; private set; }
    public string Code { get; private set; }
    public int MaxUses { get; private set; }
    public int UsedCount { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset ExpiresAtUtc { get; private set; }
    public bool IsRevoked { get; private set; }

    public static InviteCode Create(Guid createdByUserId, string code, int maxUses, DateTimeOffset expiresAtUtc, DateTimeOffset utcNow) =>
        new(Guid.NewGuid(), createdByUserId, code, maxUses, expiresAtUtc, utcNow);

    public bool TryRedeem(DateTimeOffset utcNow)
    {
        if (IsRevoked || utcNow >= ExpiresAtUtc || UsedCount >= MaxUses)
        {
            return false;
        }

        UsedCount++;
        return true;
    }

    public void Revoke() => IsRevoked = true;
}

public sealed class ServerSettings
{
    private ServerSettings()
    {
        ServerName = "Hermes Media Server";
    }

    private ServerSettings(Guid id, Guid serverId, string serverName, DateTimeOffset utcNow)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(serverName);

        Id = id;
        ServerId = serverId;
        ServerName = serverName.Trim();
        MaxConcurrentVideoTranscodes = 2;
        MaxConcurrentAudioTranscodes = 4;
        TranscodingEnabled = true;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid ServerId { get; private set; }
    public string ServerName { get; private set; }
    public int MaxConcurrentVideoTranscodes { get; private set; }
    public int MaxConcurrentAudioTranscodes { get; private set; }
    public int? MaxRemoteVideoBitrateBps { get; private set; }
    public bool TranscodingEnabled { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public static ServerSettings CreateDefault(string serverName, DateTimeOffset utcNow) =>
        new(Guid.NewGuid(), Guid.NewGuid(), serverName, utcNow);

    public void UpdateTranscodeLimits(int maxVideo, int maxAudio, int? maxRemoteVideoBitrateBps, bool transcodingEnabled, DateTimeOffset utcNow)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(maxVideo, 0);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxAudio, 0);
        if (maxRemoteVideoBitrateBps is <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxRemoteVideoBitrateBps), "Bitrate limit must be positive.");
        }

        MaxConcurrentVideoTranscodes = maxVideo;
        MaxConcurrentAudioTranscodes = maxAudio;
        MaxRemoteVideoBitrateBps = maxRemoteVideoBitrateBps;
        TranscodingEnabled = transcodingEnabled;
        UpdatedAtUtc = utcNow;
    }
}
