using System.Security.Cryptography;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Security;

public sealed class PasswordHasherAdapter : IPasswordHasher
{
    private const string Prefix = "pbkdf2-sha256";
    private const int DefaultIterations = 100_000;
    private const int SaltSize = 16;
    private const int KeySize = 32;

    public string HashPassword(string password)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(password);

        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var key = Rfc2898DeriveBytes.Pbkdf2(password, salt, DefaultIterations, HashAlgorithmName.SHA256, KeySize);

        return $"{Prefix}${DefaultIterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(key)}";
    }

    public bool VerifyPassword(string password, string passwordHash)
    {
        if (string.IsNullOrWhiteSpace(password) || string.IsNullOrWhiteSpace(passwordHash))
        {
            return false;
        }

        var parts = passwordHash.Split('$');
        if (parts.Length != 4 || parts[0] != Prefix)
        {
            return false;
        }

        if (!int.TryParse(parts[1], out var iterations) || iterations <= 0)
        {
            return false;
        }

        var salt = new byte[SaltSize];
        if (!Convert.TryFromBase64String(parts[2], salt, out var saltLen) || saltLen != SaltSize)
        {
            return false;
        }

        var expectedKey = new byte[KeySize];
        if (!Convert.TryFromBase64String(parts[3], expectedKey, out var keyLen) || keyLen != KeySize)
        {
            return false;
        }

        var actualKey = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, KeySize);
        return CryptographicOperations.FixedTimeEquals(expectedKey, actualKey);
    }
}
