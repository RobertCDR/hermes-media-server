using System.Security.Cryptography;
using System.Text;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Security;

public sealed class HmacStreamTicketService : IStreamTicketService
{
    private readonly byte[] _secretBytes;
    private readonly TimeProvider _timeProvider;

    public HmacStreamTicketService(string secret, TimeProvider? timeProvider = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(secret);

        _secretBytes = Encoding.UTF8.GetBytes(secret);
        if (_secretBytes.Length < 16)
        {
            throw new ArgumentException("Stream ticket secret must be at least 16 bytes.", nameof(secret));
        }

        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public string CreateStreamTicket(Guid userId, Guid mediaSourceId, TimeSpan ttl)
    {
        var expiresAtUnix = (_timeProvider.GetUtcNow() + ttl).ToUnixTimeSeconds();
        var payload = $"{userId:N}:{mediaSourceId:N}:{expiresAtUnix}";
        var payloadB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(payload));
        var signature = HMACSHA256.HashData(_secretBytes, Encoding.UTF8.GetBytes(payloadB64));
        return $"{payloadB64}.{Base64UrlEncode(signature)}";
    }

    public bool TryValidateStreamTicket(string ticket, Guid expectedMediaSourceId, out Guid userId)
    {
        userId = Guid.Empty;
        if (string.IsNullOrWhiteSpace(ticket))
        {
            return false;
        }

        var parts = ticket.Split('.');
        if (parts.Length != 2)
        {
            return false;
        }

        if (!TryBase64UrlDecode(parts[1], out var providedSignature))
        {
            return false;
        }

        var expectedSignature = HMACSHA256.HashData(_secretBytes, Encoding.UTF8.GetBytes(parts[0]));
        if (providedSignature.Length != expectedSignature.Length ||
            !CryptographicOperations.FixedTimeEquals(providedSignature, expectedSignature))
        {
            return false;
        }

        if (!TryBase64UrlDecode(parts[0], out var payloadBytes))
        {
            return false;
        }

        var payloadParts = Encoding.UTF8.GetString(payloadBytes).Split(':');
        if (payloadParts.Length != 3)
        {
            return false;
        }

        if (!Guid.TryParseExact(payloadParts[0], "N", out var parsedUserId) ||
            !Guid.TryParseExact(payloadParts[1], "N", out var parsedMediaSourceId) ||
            !long.TryParse(payloadParts[2], out var expiresAtUnix))
        {
            return false;
        }

        if (parsedMediaSourceId != expectedMediaSourceId)
        {
            return false;
        }

        if (expiresAtUnix <= _timeProvider.GetUtcNow().ToUnixTimeSeconds())
        {
            return false;
        }

        userId = parsedUserId;
        return true;
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static bool TryBase64UrlDecode(string input, out byte[] bytes)
    {
        bytes = [];
        if (string.IsNullOrWhiteSpace(input))
        {
            return false;
        }

        var padded = input.Replace('-', '+').Replace('_', '/');
        padded = (padded.Length % 4) switch
        {
            2 => padded + "==",
            3 => padded + "=",
            0 => padded,
            _ => string.Empty
        };

        if (padded.Length == 0)
        {
            return false;
        }

        try
        {
            bytes = Convert.FromBase64String(padded);
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
