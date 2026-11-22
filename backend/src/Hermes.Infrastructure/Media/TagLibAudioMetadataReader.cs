using Hermes.Domain.Common;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Media;

public sealed class TagLibAudioMetadataReader : IAudioMetadataReader
{
    public ProbedAudioTrackMetadata? ReadMetadata(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return null;
        }

        try
        {
            using var tagFile = TagLib.File.Create(filePath, TagLib.ReadStyle.Average);

            var title = string.IsNullOrWhiteSpace(tagFile.Tag.Title)
                ? Path.GetFileNameWithoutExtension(filePath)
                : tagFile.Tag.Title.Trim();

            var performerCredits = ArtistCreditParser.FromPerformerTags(tagFile.Tag.Performers);
            if (performerCredits.Count == 0 && !string.IsNullOrWhiteSpace(tagFile.Tag.FirstAlbumArtist))
            {
                performerCredits = ArtistCreditParser.FromPerformerTags([tagFile.Tag.FirstAlbumArtist]);
            }

            if (performerCredits.Count == 0)
            {
                performerCredits = ["Unknown Artist"];
            }

            var artist = performerCredits[0];

            var album = string.IsNullOrWhiteSpace(tagFile.Tag.Album)
                ? "Unknown Album"
                : tagFile.Tag.Album.Trim();

            var year = tagFile.Tag.Year > 0 ? (int?)tagFile.Tag.Year : null;
            var track = tagFile.Tag.Track > 0 ? (int)tagFile.Tag.Track : 1;
            var disc = tagFile.Tag.Disc > 0 ? (int)tagFile.Tag.Disc : 1;
            var durationMs = Math.Max(0L, (long)tagFile.Properties.Duration.TotalMilliseconds);
            var codec = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
            var bitrateBps = tagFile.Properties.AudioBitrate > 0 ? tagFile.Properties.AudioBitrate * 1000L : 320_000L;
            var sampleRate = tagFile.Properties.AudioSampleRate > 0 ? tagFile.Properties.AudioSampleRate : 44_100;
            var bitDepth = tagFile.Properties.BitsPerSample > 0 ? tagFile.Properties.BitsPerSample : 16;
            var artwork = tagFile.Tag.Pictures.FirstOrDefault()?.Data.Data;

            return new ProbedAudioTrackMetadata(
                title,
                artist,
                album,
                year,
                track,
                disc,
                durationMs,
                string.IsNullOrWhiteSpace(codec) ? "mp3" : codec,
                bitrateBps,
                sampleRate,
                bitDepth,
                artwork is { Length: > 0 } ? artwork : null,
                performerCredits);
        }
        catch (Exception)
        {
            var ext = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
            return new ProbedAudioTrackMetadata(
                Path.GetFileNameWithoutExtension(filePath),
                "Unknown Artist",
                "Unknown Album",
                null,
                1,
                1,
                0,
                string.IsNullOrWhiteSpace(ext) ? "mp3" : ext,
                320_000L,
                44_100,
                16,
                null);
        }
    }
}
