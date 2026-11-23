using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Media;

public static class TmdbArtworkExtensions
{
    public static async Task<string?> DownloadAndStoreArtworkAsync(
        this ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        string? remotePath,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(remotePath))
        {
            return null;
        }

        var bytes = await tmdbClient.DownloadImageBytesAsync(remotePath, cancellationToken);
        return bytes is { Length: > 0 }
            ? await artworkStore.SaveArtworkVariantsAsync(bytes, cancellationToken)
            : null;
    }
}
