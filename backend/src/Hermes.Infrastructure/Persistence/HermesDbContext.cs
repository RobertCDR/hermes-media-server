using Hermes.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Infrastructure.Persistence;

public sealed class HermesDbContext(DbContextOptions<HermesDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<InviteCode> InviteCodes => Set<InviteCode>();
    public DbSet<ServerSettings> ServerSettings => Set<ServerSettings>();
    public DbSet<MediaLibraryRoot> MediaLibraryRoots => Set<MediaLibraryRoot>();
    public DbSet<Movie> Movies => Set<Movie>();
    public DbSet<TvSeries> TvSeries => Set<TvSeries>();
    public DbSet<TvSeason> TvSeasons => Set<TvSeason>();
    public DbSet<Episode> Episodes => Set<Episode>();
    public DbSet<MediaSource> MediaSources => Set<MediaSource>();
    public DbSet<MediaStream> MediaStreams => Set<MediaStream>();
    public DbSet<WatchProgress> WatchProgresses => Set<WatchProgress>();
    public DbSet<WatchlistItem> WatchlistItems => Set<WatchlistItem>();
    public DbSet<Artist> Artists => Set<Artist>();
    public DbSet<Album> Albums => Set<Album>();
    public DbSet<Song> Songs => Set<Song>();
    public DbSet<Playlist> Playlists => Set<Playlist>();
    public DbSet<PlaylistTrack> PlaylistTracks => Set<PlaylistTrack>();
    public DbSet<LikedSong> LikedSongs => Set<LikedSong>();
    public DbSet<PlaybackSession> PlaybackSessions => Set<PlaybackSession>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.HasPostgresExtension("pg_trgm");

        ConfigureIdentity(modelBuilder);
        ConfigureCinema(modelBuilder);
        ConfigureMusicAndPlayback(modelBuilder);
    }

    private static void ConfigureIdentity(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(b =>
        {
            b.HasKey(u => u.Id);
            b.Property(u => u.Username).HasMaxLength(64).IsRequired();
            b.Property(u => u.PasswordHash).HasMaxLength(512).IsRequired();
            b.Property(u => u.PreferredAccentHex).HasMaxLength(16).IsRequired();
            b.Property(u => u.AutoplayNextEpisode).HasDefaultValue(true);
            b.Property(u => u.NormalizeVolume).HasDefaultValue(false);
            b.Property(u => u.MatchTitleColors).HasDefaultValue(true);
            b.Property(u => u.SubtitleSize).HasMaxLength(16).HasDefaultValue("medium").IsRequired();
            b.Property(u => u.SubtitleBackground).HasMaxLength(16).HasDefaultValue("shadow").IsRequired();
            b.HasIndex(u => u.Username).IsUnique();
            b.HasMany(u => u.RefreshTokens)
                .WithOne(t => t.User)
                .HasForeignKey(t => t.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<RefreshToken>(b =>
        {
            b.HasKey(t => t.Id);
            b.Property(t => t.DeviceId).HasMaxLength(128).IsRequired();
            b.Property(t => t.DeviceName).HasMaxLength(128).IsRequired();
            b.Property(t => t.TokenHash).HasMaxLength(128).IsRequired();
            b.HasIndex(t => t.TokenHash).IsUnique();
            b.HasIndex(t => new { t.UserId, t.DeviceId });
        });

        modelBuilder.Entity<InviteCode>(b =>
        {
            b.HasKey(i => i.Id);
            b.Property(i => i.Code).HasMaxLength(64).IsRequired();
            b.HasIndex(i => i.Code).IsUnique();
        });

        modelBuilder.Entity<ServerSettings>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.ServerName).HasMaxLength(128).IsRequired();
            b.Property(s => s.HardwareAccelerationMode).HasDefaultValue(Domain.Enums.HardwareAccelerationMode.None);
        });
    }

    private static void ConfigureCinema(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<MediaLibraryRoot>(b =>
        {
            b.HasKey(r => r.Id);
            b.Property(r => r.Name).HasMaxLength(128).IsRequired();
            b.Property(r => r.RootPath).HasMaxLength(1024).IsRequired();
            b.Property(r => r.FetchMetadata).HasDefaultValue(true);
            b.HasIndex(r => r.RootPath).IsUnique();
        });

        modelBuilder.Entity<Movie>(b =>
        {
            b.HasKey(m => m.Id);
            b.Property(m => m.Title).HasMaxLength(512).IsRequired();
            b.Property(m => m.ArtworkHash).HasMaxLength(128);
            b.Property(m => m.BackdropHash).HasMaxLength(128);
            b.Property(m => m.GenresCsv).HasMaxLength(512);
            b.Property(m => m.CastJson).HasMaxLength(4000);
            b.HasIndex(m => m.LibraryRootId);
            b.HasIndex(m => m.TmdbId);
            b.HasIndex(m => m.Title)
                .HasDatabaseName("IX_Movies_Title_Trgm")
                .HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            b.HasMany(m => m.Sources)
                .WithOne(s => s.Movie)
                .HasForeignKey(s => s.MovieId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TvSeries>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.Title).HasMaxLength(512).IsRequired();
            b.Property(s => s.ArtworkHash).HasMaxLength(128);
            b.Property(s => s.BackdropHash).HasMaxLength(128);
            b.Property(s => s.GenresCsv).HasMaxLength(512);
            b.Property(s => s.CastJson).HasMaxLength(4000);
            b.HasIndex(s => s.LibraryRootId);
            b.HasIndex(s => s.TmdbId);
            b.HasIndex(s => s.Title)
                .HasDatabaseName("IX_TvSeries_Title_Trgm")
                .HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            b.HasMany(s => s.Seasons)
                .WithOne(sn => sn.TvSeries)
                .HasForeignKey(sn => sn.TvSeriesId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TvSeason>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.Title).HasMaxLength(256).IsRequired();
            b.Property(s => s.ArtworkHash).HasMaxLength(128);
            b.HasIndex(s => new { s.TvSeriesId, s.SeasonNumber }).IsUnique();
            b.HasMany(s => s.Episodes)
                .WithOne(e => e.TvSeason)
                .HasForeignKey(e => e.TvSeasonId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Episode>(b =>
        {
            b.HasKey(e => e.Id);
            b.Property(e => e.Title).HasMaxLength(512).IsRequired();
            b.Property(e => e.StillArtworkHash).HasMaxLength(128);
            b.HasIndex(e => new { e.TvSeasonId, e.EpisodeNumber }).IsUnique();
            b.HasMany(e => e.Sources)
                .WithOne(s => s.Episode)
                .HasForeignKey(s => s.EpisodeId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<MediaSource>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.FilePath).HasMaxLength(2048).IsRequired();
            b.Property(s => s.SourceLabel).HasMaxLength(128).IsRequired();
            b.Property(s => s.Container).HasMaxLength(32).IsRequired();
            b.Property(s => s.VideoCodec).HasMaxLength(64).IsRequired();
            b.Property(s => s.AudioCodec).HasMaxLength(64).IsRequired();
            b.HasIndex(s => s.FilePath).IsUnique();
            b.HasMany(s => s.Streams)
                .WithOne(st => st.MediaSource)
                .HasForeignKey(st => st.MediaSourceId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<MediaStream>(b =>
        {
            b.HasKey(st => st.Id);
            b.Property(st => st.Codec).HasMaxLength(64).IsRequired();
            b.Property(st => st.Language).HasMaxLength(32).IsRequired();
            b.Property(st => st.Title).HasMaxLength(256).IsRequired();
            b.HasIndex(st => new { st.MediaSourceId, st.StreamIndex }).IsUnique();
        });

        modelBuilder.Entity<WatchProgress>(b =>
        {
            b.HasKey(w => w.Id);
            b.HasIndex(w => new { w.UserId, w.MovieId })
                .IsUnique()
                .HasFilter("\"MovieId\" IS NOT NULL");
            b.HasIndex(w => new { w.UserId, w.EpisodeId })
                .IsUnique()
                .HasFilter("\"EpisodeId\" IS NOT NULL");
        });

        modelBuilder.Entity<WatchlistItem>(b =>
        {
            b.HasKey(w => w.Id);
            b.HasIndex(w => new { w.UserId, w.MovieId })
                .IsUnique()
                .HasFilter("\"MovieId\" IS NOT NULL");
            b.HasIndex(w => new { w.UserId, w.TvSeriesId })
                .IsUnique()
                .HasFilter("\"TvSeriesId\" IS NOT NULL");
        });
    }

    private static void ConfigureMusicAndPlayback(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Artist>(b =>
        {
            b.HasKey(a => a.Id);
            b.Property(a => a.Name).HasMaxLength(256).IsRequired();
            b.Property(a => a.ArtworkHash).HasMaxLength(128);
            b.HasIndex(a => a.Name, "IX_Artists_Name").IsUnique();
            b.HasIndex(a => a.Name, "IX_Artists_Name_Trgm")
                .HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            b.HasMany(a => a.Songs)
                .WithOne(s => s.Artist)
                .HasForeignKey(s => s.ArtistId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Album>(b =>
        {
            b.HasKey(a => a.Id);
            b.Property(a => a.Title).HasMaxLength(256).IsRequired();
            b.Property(a => a.ArtworkHash).HasMaxLength(128);
            b.HasIndex(a => new { a.ArtistId, a.Title }).IsUnique();
            b.HasIndex(a => a.Title)
                .HasDatabaseName("IX_Albums_Title_Trgm")
                .HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            b.HasMany(a => a.Songs)
                .WithOne(s => s.Album)
                .HasForeignKey(s => s.AlbumId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Song>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.Title).HasMaxLength(512).IsRequired();
            b.Property(s => s.FilePath).HasMaxLength(2048).IsRequired();
            b.Property(s => s.Codec).HasMaxLength(64).IsRequired();
            b.HasIndex(s => s.FilePath).IsUnique();
            b.HasIndex(s => s.Title)
                .HasDatabaseName("IX_Songs_Title_Trgm")
                .HasMethod("gin")
                .HasOperators("gin_trgm_ops");
        });

        modelBuilder.Entity<Playlist>(b =>
        {
            b.HasKey(p => p.Id);
            b.Property(p => p.Name).HasMaxLength(256).IsRequired();
            b.HasIndex(p => p.OwnerUserId);
            b.HasMany(p => p.Tracks)
                .WithOne(t => t.Playlist)
                .HasForeignKey(t => t.PlaylistId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<PlaylistTrack>(b =>
        {
            b.HasKey(t => t.Id);
            b.HasIndex(t => new { t.PlaylistId, t.Position }).IsUnique();
        });

        modelBuilder.Entity<LikedSong>(b =>
        {
            b.HasKey(l => new { l.UserId, l.SongId });
        });

        modelBuilder.Entity<PlaybackSession>(b =>
        {
            b.HasKey(s => s.Id);
            b.Property(s => s.ActiveRendererDeviceId).HasMaxLength(128);
            b.Property(s => s.ActiveRendererDeviceName).HasMaxLength(128);
            b.HasIndex(s => s.UserId).IsUnique();
        });
    }
}
