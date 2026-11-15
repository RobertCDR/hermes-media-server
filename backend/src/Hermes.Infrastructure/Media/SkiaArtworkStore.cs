using System.Security.Cryptography;
using Hermes.Domain.Ports;
using SkiaSharp;

namespace Hermes.Infrastructure.Media;

public sealed class SkiaArtworkStore : IArtworkStore
{
    private static readonly (string FileName, int TargetWidth)[] Variants =
    [
        ("thumb_400.webp", 400),
        ("poster_800.webp", 800),
        ("backdrop_1280.webp", 1280)
    ];

    private static readonly HashSet<string> AllowedVariantNames =
        new(Variants.Select(v => v.FileName), StringComparer.Ordinal);

    private readonly string _artworkRoot;

    public SkiaArtworkStore(string artworkRootDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(artworkRootDirectory);
        _artworkRoot = Path.GetFullPath(artworkRootDirectory);
    }

    public Task<string?> SaveArtworkVariantsAsync(byte[] sourceImageBytes, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (sourceImageBytes.Length == 0)
        {
            return Task.FromResult<string?>(null);
        }

        using var sourceBitmap = SKBitmap.Decode(sourceImageBytes);
        if (sourceBitmap is null || sourceBitmap.Width <= 0 || sourceBitmap.Height <= 0)
        {
            return Task.FromResult<string?>(null);
        }

        var hash = Convert.ToHexStringLower(SHA256.HashData(sourceImageBytes));
        var targetDirectory = Path.Combine(_artworkRoot, hash);
        Directory.CreateDirectory(targetDirectory);

        foreach (var (fileName, targetWidth) in Variants)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var outputPath = Path.Combine(targetDirectory, fileName);
            if (!File.Exists(outputPath))
            {
                WriteWebpVariant(sourceBitmap, targetWidth, outputPath);
            }
        }

        return Task.FromResult<string?>(hash);
    }

    public string? ResolveVariantFilePath(string artworkHash, string variant)
    {
        if (string.IsNullOrWhiteSpace(artworkHash) ||
            artworkHash.Length != 64 ||
            !artworkHash.All(c => c is (>= '0' and <= '9') or (>= 'a' and <= 'f')))
        {
            return null;
        }

        if (!AllowedVariantNames.Contains(variant))
        {
            return null;
        }

        var path = Path.Combine(_artworkRoot, artworkHash, variant);
        return File.Exists(path) ? path : null;
    }

    private static void WriteWebpVariant(SKBitmap source, int targetWidth, string outputPath)
    {
        var width = Math.Max(1, targetWidth);
        var height = Math.Max(1, (int)Math.Round(source.Height * ((double)width / source.Width)));

        using var resized = source.Resize(new SKImageInfo(width, height), SKSamplingOptions.Default)
            ?? throw new InvalidOperationException("Failed to resize artwork bitmap.");
        using var image = SKImage.FromBitmap(resized);
        using var data = image.Encode(SKEncodedImageFormat.Webp, 82);
        using var fileStream = File.Create(outputPath);
        data.SaveTo(fileStream);
    }
}
