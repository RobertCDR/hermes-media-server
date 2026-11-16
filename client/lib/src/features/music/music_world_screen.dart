import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';

enum _MusicSection {
  overview('Overview'),
  albums('Albums'),
  artists('Artists'),
  songs('Songs'),
  liked('Liked'),
  playlists('Playlists');

  const _MusicSection(this.label);
  final String label;
}

class MusicWorldScreen extends StatefulWidget {
  const MusicWorldScreen({
    super.key,
    required this.musicService,
    required this.coordinator,
  });

  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;

  @override
  State<MusicWorldScreen> createState() => _MusicWorldScreenState();
}

class _MusicWorldScreenState extends State<MusicWorldScreen> {
  List<SongModel> _songs = [];
  List<AlbumSummaryModel> _albums = [];
  List<ArtistSummaryModel> _artists = [];
  List<PlaylistSummaryModel> _playlists = [];
  _MusicSection _section = _MusicSection.overview;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.musicService.listSongs(),
        widget.musicService.listAlbums(),
        widget.musicService.listArtists(),
        widget.musicService.listPlaylists(),
      ]);
      final songs = results[0] as List<SongModel>;
      final albums = results[1] as List<AlbumSummaryModel>;
      final artists = results[2] as List<ArtistSummaryModel>;
      final playlists = results[3] as List<PlaylistSummaryModel>;

      widget.coordinator.indexSongs(songs);
      if (mounted) {
        setState(() {
          _songs = songs;
          _albums = albums;
          _artists = artists;
          _playlists = playlists;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleLike(SongModel song) async {
    final liked = await widget.musicService.toggleLikeSong(song.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _songs = [
        for (final item in _songs)
          item.id == song.id ? item.copyWith(isLiked: liked) : item,
      ];
    });
  }

  Future<void> _openCreatePlaylistDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Playlist Name',
                hintText: 'Late Night FLAC',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
        ],
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      final description = descController.text.trim();
      await widget.musicService.createPlaylist(
        name: nameController.text.trim(),
        description: description.isEmpty ? null : description,
      );
      await _load();
    }

    nameController.dispose();
    descController.dispose();
  }

  void _openAlbumSheet(AlbumSummaryModel album) {
    final tokens = HermesThemeTokens.of(context);
    final albumTracks = _songs.where((s) => s.albumId == album.id).toList();
    final coverUri = widget.musicService.buildArtworkUri(album.artworkHash, variant: 'poster_800');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgElevated,
      constraints: BoxConstraints(
        maxWidth: 740,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                HermesArtworkImage(
                  uri: coverUri,
                  fallbackTitle: album.title,
                  fallbackIcon: Icons.album_outlined,
                  width: 96,
                  height: 96,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.year != null
                            ? '${album.artistName} • ${album.year} • ${albumTracks.length} track(s)'
                            : '${album.artistName} • ${albumTracks.length} track(s)',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: albumTracks.isEmpty
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                unawaited(widget.coordinator.startQueue(albumTracks, 0));
                              },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play Album'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: albumTracks.length,
              itemBuilder: (_, idx) {
                final song = albumTracks[idx];
                return _SongRow(
                  song: song,
                  artworkUri: widget.musicService.buildArtworkUri(song.artworkHash),
                  isActive: widget.coordinator.currentSong?.id == song.id,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(widget.coordinator.startQueue(albumTracks, idx));
                  },
                  onToggleLike: () => unawaited(_toggleLike(song)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openArtistSheet(ArtistSummaryModel artist) {
    final tokens = HermesThemeTokens.of(context);
    final artistTracks = _songs.where((s) => s.artistId == artist.id).toList();
    final artistAlbums = _albums.where((a) => a.artistId == artist.id).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgElevated,
      constraints: BoxConstraints(
        maxWidth: 740,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: tokens.accentPrimary.withValues(alpha: 0.2),
                  child: Icon(Icons.person_outline, size: 30, color: tokens.accentPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${artistAlbums.length} album(s) • ${artistTracks.length} track(s)',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: artistTracks.isEmpty
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          unawaited(widget.coordinator.startQueue(artistTracks, 0));
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play All'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: artistTracks.length,
              itemBuilder: (_, idx) {
                final song = artistTracks[idx];
                return _SongRow(
                  song: song,
                  artworkUri: widget.musicService.buildArtworkUri(song.artworkHash),
                  isActive: widget.coordinator.currentSong?.id == song.id,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(widget.coordinator.startQueue(artistTracks, idx));
                  },
                  onToggleLike: () => unawaited(_toggleLike(song)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load Music library: $_error'),
            const SizedBox(height: 10),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final likedSongs = _songs.where((s) => s.isLiked).toList();

    return AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final activeSongId = widget.coordinator.currentSong?.id;
        final showAlbums =
            (_section == _MusicSection.overview || _section == _MusicSection.albums) &&
                _albums.isNotEmpty;
        final showArtists =
            (_section == _MusicSection.overview || _section == _MusicSection.artists) &&
                _artists.isNotEmpty;
        final showPlaylists =
            _section == _MusicSection.overview || _section == _MusicSection.playlists;
        final showSongs = _section == _MusicSection.overview ||
            _section == _MusicSection.songs ||
            _section == _MusicSection.liked;
        final visibleSongs = _section == _MusicSection.liked ? likedSongs : _songs;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _MusicSection.values.map((section) {
                      return ChoiceChip(
                        label: Text(section.label),
                        selected: _section == section,
                        onSelected: (_) => setState(() => _section = section),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _openCreatePlaylistDialog,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('New Playlist'),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Refresh music library',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_songs.isEmpty && _albums.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_music_outlined, size: 52, color: tokens.textSecondary),
                      const SizedBox(height: 12),
                      Text(
                        'No songs scanned yet. Open Admin Dashboard to scan a Music library.',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (showAlbums) ...[
              Text(
                'Albums (${_albums.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 18,
                children: _albums.map((album) {
                  return SizedBox(
                    width: 168,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openAlbumSheet(album),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HermesArtworkImage(
                              uri: widget.musicService.buildArtworkUri(album.artworkHash),
                              fallbackTitle: album.title,
                              fallbackIcon: Icons.album_outlined,
                              width: 168,
                              height: 168,
                              borderRadius: BorderRadius.zero,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    album.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    album.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 26),
            ],
            if (showArtists) ...[
              Text(
                'Artists (${_artists.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _artists.map((artist) {
                  return ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: tokens.accentPrimary.withValues(alpha: 0.2),
                      child: Icon(Icons.person_outline, size: 16, color: tokens.accentPrimary),
                    ),
                    label: Text('${artist.name} (${artist.albumCount})'),
                    onPressed: () => _openArtistSheet(artist),
                  );
                }).toList(),
              ),
              const SizedBox(height: 26),
            ],
            if (showPlaylists) ...[
              Text(
                'Playlists (${_playlists.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (_playlists.isEmpty)
                Text('No playlists yet.', style: TextStyle(color: tokens.textSecondary))
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _playlists.map((p) {
                    return SizedBox(
                      width: 240,
                      child: Card(
                        child: ListTile(
                          leading: Icon(Icons.queue_music, color: tokens.accentPrimary),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${p.trackCount} track(s)'),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 26),
            ],
            if (showSongs && (_songs.isNotEmpty || _section == _MusicSection.liked)) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _section == _MusicSection.liked
                        ? 'Liked Songs (${visibleSongs.length})'
                        : 'Songs (${visibleSongs.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (visibleSongs.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(widget.coordinator.startQueue(visibleSongs, 0)),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play All'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (visibleSongs.isEmpty)
                Text('No liked songs yet.', style: TextStyle(color: tokens.textSecondary))
              else
                ...visibleSongs.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final song = entry.value;
                  return _SongRow(
                    song: song,
                    artworkUri: widget.musicService.buildArtworkUri(song.artworkHash),
                    isActive: activeSongId == song.id,
                    onTap: () => unawaited(widget.coordinator.startQueue(visibleSongs, idx)),
                    onToggleLike: () => unawaited(_toggleLike(song)),
                  );
                }),
            ],
          ],
        );
      },
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.artworkUri,
    required this.isActive,
    required this.onTap,
    required this.onToggleLike,
  });

  final SongModel song;
  final Uri? artworkUri;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? tokens.accentPrimary : const Color(0x1AFFFFFF),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: HermesArtworkImage(
          uri: artworkUri,
          fallbackTitle: song.albumTitle,
          fallbackIcon: Icons.music_note_outlined,
          width: 48,
          height: 48,
          borderRadius: BorderRadius.circular(8),
          showFallbackLabel: false,
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isActive ? tokens.accentHover : tokens.textPrimary,
          ),
        ),
        subtitle: Text(
          '${song.artistName} • ${song.albumTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: tokens.bgPrimary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              child: Text(
                song.codec.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatDurationMs(song.durationMs),
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                song.isLiked ? Icons.favorite : Icons.favorite_border,
                color: song.isLiked ? tokens.accentPrimary : tokens.textSecondary,
              ),
              onPressed: onToggleLike,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
