import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';
import 'music_shared_widgets.dart';

/// Shared responsive Spotify collection header matching Figma `.collection-header`.
class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.kindLabel,
    required this.title,
    required this.art,
    required this.metaLine,
  });

  final String kindLabel;
  final String title;
  final Widget art;
  final Widget metaLine;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 580;
        final headingSize = constraints.maxWidth > 900 ? 46.0 : 32.0;

        if (compact) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: art),
                const SizedBox(height: 16),
                Text(
                  kindLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.03,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 8),
                metaLine,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              art,
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kindLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: headingSize,
                        height: 1.04,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.03,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    metaLine,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Complete inline Album detail view receiving sorted album tracks cleanly.
class MusicAlbumPage extends StatelessWidget {
  const MusicAlbumPage({
    super.key,
    required this.album,
    required this.songs,
    required this.moreByArtist,
    required this.musicService,
    required this.coordinator,
    required this.playlists,
    required this.onPlayCollection,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onNavigate,
  });

  final AlbumSummaryModel album;
  final List<SongModel> songs;
  final List<AlbumSummaryModel> moreByArtist;
  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final List<PlaylistSummaryModel> playlists;
  final Future<void> Function(List<SongModel> songs, {int startIndex, String? sourceLabel, MusicPageRoute? sourceRoute}) onPlayCollection;
  final ValueChanged<SongModel> onToggleLike;
  final Future<void> Function(String playlistId, SongModel song) onAddToPlaylist;
  final ValueChanged<MusicPageRoute> onNavigate;

  String _formatAlbumDuration(List<SongModel> items) {
    final totalSec = items.fold<int>(0, (s, e) => s + e.durationMs) ~/ 1000;
    final mins = totalSec ~/ 60;
    if (mins >= 60) {
      return '${mins ~/ 60} hr ${mins % 60} min';
    }
    return '${mins > 0 ? mins : 1} min';
  }

  String _formatQualitySummary(List<SongModel> items) {
    if (items.isEmpty) return '';
    final sample = items.first;
    final codec = sample.codec.toUpperCase();
    final hz = (sample.sampleRateHz / 1000.0).toStringAsFixed(1);
    return '$codec • ${sample.bitDepth}-bit / $hz kHz';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final session = coordinator.session;
    final playingThis = session?.state == PlaybackState.playing &&
        songs.any((s) => s.id == session?.currentSongId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionHeader(
          kindLabel: 'Album',
          title: album.title,
          art: MusicArtworkTile(
            size: 196,
            title: album.title,
            uri: musicService.buildArtworkUri(album.artworkHash),
            borderRadius: 6,
          ),
          metaLine: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: () => onNavigate(MusicPageRoute.artist(album.artistId)),
                child: Text(
                  album.artistName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
              ),
              if (album.year != null)
                Text('• ${album.year}', style: TextStyle(fontSize: 13, color: tokens.text2)),
              Text(
                '• ${songs.length} ${songs.length == 1 ? 'song' : 'songs'}, ${_formatAlbumDuration(songs)}',
                style: TextStyle(fontSize: 13, color: tokens.text2),
              ),
            ],
          ),
        ),
        MusicCollectionActionBar(
          canPlay: songs.isNotEmpty,
          isPlayingThisCollection: playingThis,
          shuffleEnabled: session?.shuffle ?? false,
          onPlayPressed: () {
            if (playingThis) {
              coordinator.togglePlayPause();
            } else {
              onPlayCollection(
                songs,
                startIndex: 0,
                sourceLabel: album.title,
                sourceRoute: MusicPageRoute.album(album.id),
              );
            }
          },
          onToggleShuffle: () => coordinator.toggleShuffle(),
        ),
        MusicTrackTable(
          songs: songs,
          musicService: musicService,
          coordinator: coordinator,
          playlists: playlists,
          showAlbum: false,
          discGrouping: true,
          onPlayTrackAt: (idx) => onPlayCollection(
            songs,
            startIndex: idx,
            sourceLabel: album.title,
            sourceRoute: MusicPageRoute.album(album.id),
          ),
          onToggleLike: onToggleLike,
          onAddToPlaylist: onAddToPlaylist,
          onNavigate: onNavigate,
        ),
        if (songs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (album.year != null)
                  Text(
                    'Released ${album.year}',
                    style: TextStyle(fontSize: 13, color: tokens.text),
                  ),
                const SizedBox(height: 2),
                Text(
                  _formatQualitySummary(songs),
                  style: TextStyle(fontSize: 12, color: tokens.text2),
                ),
              ],
            ),
          ),
        if (moreByArtist.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'More by ${album.artistName}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 12),
          _AlbumCardGrid(
            albums: moreByArtist,
            musicService: musicService,
            onNavigate: onNavigate,
            onPlayAlbum: (other) => onNavigate(MusicPageRoute.album(other.id)),
          ),
        ],
      ],
    );
  }
}

/// Dedicated Artist page with atmospheric hero banner, Popular tracks, and Discography grid.
class MusicArtistPage extends StatelessWidget {
  const MusicArtistPage({
    super.key,
    required this.artist,
    required this.albums,
    required this.songs,
    required this.musicService,
    required this.coordinator,
    required this.playlists,
    required this.onPlayCollection,
    required this.onPlayAlbum,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onNavigate,
  });

  final ArtistSummaryModel artist;
  final List<AlbumSummaryModel> albums;
  final List<SongModel> songs;
  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final List<PlaylistSummaryModel> playlists;
  final Future<void> Function(List<SongModel> songs, {int startIndex, String? sourceLabel, MusicPageRoute? sourceRoute}) onPlayCollection;
  final ValueChanged<AlbumSummaryModel> onPlayAlbum;
  final ValueChanged<SongModel> onToggleLike;
  final Future<void> Function(String playlistId, SongModel song) onAddToPlaylist;
  final ValueChanged<MusicPageRoute> onNavigate;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final session = coordinator.session;
    final playingThis = session?.state == PlaybackState.playing &&
        songs.any((s) => s.id == session?.currentSongId);
    final bannerUri = musicService.buildArtworkUri(
      artist.artworkHash ?? (albums.isNotEmpty ? albums.first.artworkHash : null),
      variant: 'hero_800',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 256,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HermesArtworkImage(
                  uri: bannerUri,
                  fallbackTitle: artist.name,
                  fallbackIcon: Icons.person_rounded,
                  borderRadius: BorderRadius.zero,
                  showFallbackLabel: false,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color(0xD8000000),
                        Color(0x40000000),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 22,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Artist',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 40,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.03,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${albums.length} ${albums.length == 1 ? 'album' : 'albums'} • ${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        MusicCollectionActionBar(
          canPlay: songs.isNotEmpty,
          isPlayingThisCollection: playingThis,
          shuffleEnabled: session?.shuffle ?? false,
          onPlayPressed: () {
            if (playingThis) {
              coordinator.togglePlayPause();
            } else {
              onPlayCollection(
                songs,
                startIndex: 0,
                sourceLabel: artist.name,
                sourceRoute: MusicPageRoute.artist(artist.id),
              );
            }
          },
          onToggleShuffle: () => coordinator.toggleShuffle(),
        ),
        if (songs.isNotEmpty) ...[
          Text(
            'Popular',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 10),
          MusicTrackTable(
            songs: songs.take(10).toList(),
            musicService: musicService,
            coordinator: coordinator,
            playlists: playlists,
            showAlbum: true,
            discGrouping: false,
            onPlayTrackAt: (idx) => onPlayCollection(
              songs,
              startIndex: idx,
              sourceLabel: artist.name,
              sourceRoute: MusicPageRoute.artist(artist.id),
            ),
            onToggleLike: onToggleLike,
            onAddToPlaylist: onAddToPlaylist,
            onNavigate: onNavigate,
          ),
        ],
        if (albums.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            'Discography',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 12),
          _AlbumCardGrid(
            albums: albums,
            musicService: musicService,
            onNavigate: onNavigate,
            onPlayAlbum: onPlayAlbum,
          ),
        ],
      ],
    );
  }
}

/// Dedicated page for Playlist, Liked Songs, and Smart Playlists.
class MusicCollectionPage extends StatelessWidget {
  const MusicCollectionPage({
    super.key,
    required this.kindLabel,
    required this.title,
    required this.description,
    required this.songs,
    required this.route,
    required this.musicService,
    required this.coordinator,
    required this.playlists,
    required this.onPlayCollection,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onNavigate,
    this.isLikedCollection = false,
    this.smartKind,
    this.playlistId,
    this.coverArtworkHash,
    this.onRenamePlaylist,
    this.onDeletePlaylist,
    this.onRemoveFromPlaylist,
  });

  final String kindLabel;
  final String title;
  final String description;
  final List<SongModel> songs;
  final MusicPageRoute route;
  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final List<PlaylistSummaryModel> playlists;
  final Future<void> Function(List<SongModel> songs, {int startIndex, String? sourceLabel, MusicPageRoute? sourceRoute}) onPlayCollection;
  final ValueChanged<SongModel> onToggleLike;
  final Future<void> Function(String playlistId, SongModel song) onAddToPlaylist;
  final ValueChanged<MusicPageRoute> onNavigate;
  final bool isLikedCollection;
  final SmartPlaylistKind? smartKind;
  final String? playlistId;
  final String? coverArtworkHash;
  final VoidCallback? onRenamePlaylist;
  final VoidCallback? onDeletePlaylist;
  final Future<void> Function(String playlistId, int position)? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final session = coordinator.session;
    final playingThis = session?.state == PlaybackState.playing &&
        songs.any((s) => s.id == session?.currentSongId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionHeader(
          kindLabel: kindLabel,
          title: title,
          art: MusicArtworkTile(
            size: 196,
            title: title,
            uri: musicService.buildArtworkUri(coverArtworkHash),
            borderRadius: 6,
            isLikedCollection: isLikedCollection,
            smartKind: smartKind,
            isPlaylist: playlistId != null,
          ),
          metaLine: Text(
            description.isNotEmpty
                ? '$description • ${songs.length} ${songs.length == 1 ? 'song' : 'songs'}'
                : '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}',
            style: TextStyle(fontSize: 13, color: tokens.text2),
          ),
        ),
        MusicCollectionActionBar(
          canPlay: songs.isNotEmpty,
          isPlayingThisCollection: playingThis,
          shuffleEnabled: session?.shuffle ?? false,
          onPlayPressed: () {
            if (playingThis) {
              coordinator.togglePlayPause();
            } else {
              onPlayCollection(
                songs,
                startIndex: 0,
                sourceLabel: title,
                sourceRoute: route,
              );
            }
          },
          onToggleShuffle: () => coordinator.toggleShuffle(),
          onRenamePlaylist: onRenamePlaylist,
          onDeletePlaylist: onDeletePlaylist,
        ),
        MusicTrackTable(
          songs: songs,
          musicService: musicService,
          coordinator: coordinator,
          playlists: playlists,
          showAlbum: true,
          discGrouping: false,
          playlistIdForRemoval: playlistId,
          onPlayTrackAt: (idx) => onPlayCollection(
            songs,
            startIndex: idx,
            sourceLabel: title,
            sourceRoute: route,
          ),
          onToggleLike: onToggleLike,
          onAddToPlaylist: onAddToPlaylist,
          onRemoveFromPlaylist: onRemoveFromPlaylist,
          onNavigate: onNavigate,
          emptyTitle: isLikedCollection ? 'No liked songs yet' : 'Empty playlist',
          emptySubtitle: isLikedCollection
              ? 'Tap the heart on any track to save it to Liked Songs.'
              : 'Use the track menu on any song to add tracks here.',
        ),
      ],
    );
  }
}

class _AlbumCardGrid extends StatelessWidget {
  const _AlbumCardGrid({
    required this.albums,
    required this.musicService,
    required this.onNavigate,
    required this.onPlayAlbum,
  });

  final List<AlbumSummaryModel> albums;
  final MusicService musicService;
  final ValueChanged<MusicPageRoute> onNavigate;
  final ValueChanged<AlbumSummaryModel> onPlayAlbum;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 205,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final alb = albums[index];
        final year = alb.year != null ? '${alb.year} • ' : '';
        return MusicBrowseCard(
          title: alb.title,
          subtitle: '$year${alb.artistName}',
          artworkUri: musicService.buildArtworkUri(alb.artworkHash),
          onOpen: () => onNavigate(MusicPageRoute.album(alb.id)),
          onPlay: () => onPlayAlbum(alb),
        );
      },
    );
  }
}
