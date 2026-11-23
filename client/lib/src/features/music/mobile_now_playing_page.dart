part of 'now_playing_panel.dart';

enum _MobilePlayerView { player, queue, lyrics }

/// Dedicated Spotify-style fullscreen player & queue view for mobile viewports.
class MobileNowPlayingPage extends StatefulWidget {
  const MobileNowPlayingPage({
    super.key,
    required this.coordinator,
    required this.musicService,
    required this.localDeviceId,
    required this.onClose,
    required this.onOpenDevices,
    required this.onNavigate,
  });

  final MusicPlaybackCoordinator coordinator;
  final MusicService musicService;
  final String localDeviceId;
  final VoidCallback onClose;
  final VoidCallback onOpenDevices;
  final ValueChanged<MusicPageRoute> onNavigate;

  @override
  State<MobileNowPlayingPage> createState() => _MobileNowPlayingPageState();
}

class _MobileNowPlayingPageState extends State<MobileNowPlayingPage> {
  final List<_MobilePlayerView> _viewStack = [_MobilePlayerView.player];
  _MobilePlayerView get _view => _viewStack.last;
  int? _dragPositionMs;
  double? _volumeDrag;
  String? _loadedSongId;
  SongLyricsModel? _lyrics;
  bool _loadingLyrics = false;
  final _LyricsAutoScrollTracker _lyricsTracker = _LyricsAutoScrollTracker();

  void _toggleSubView(_MobilePlayerView target) {
    setState(() {
      if (_view == target) {
        if (_viewStack.length > 1) {
          _viewStack.removeLast();
        } else {
          _viewStack
            ..clear()
            ..add(_MobilePlayerView.player);
        }
      } else {
        _viewStack.removeWhere((v) => v == target);
        _viewStack.add(target);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onCoordinatorChanged);
    unawaited(_ensureLyrics());
  }

  @override
  void didUpdateWidget(covariant MobileNowPlayingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_onCoordinatorChanged);
      widget.coordinator.addListener(_onCoordinatorChanged);
      unawaited(_ensureLyrics());
    }
  }

  @override
  void dispose() {
    _lyricsTracker.dispose();
    widget.coordinator.removeListener(_onCoordinatorChanged);
    super.dispose();
  }

  void _onCoordinatorChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_ensureLyrics());
  }

  Future<void> _ensureLyrics() async {
    final song = widget.coordinator.currentSong;
    if (song == null) {
      if (_loadedSongId != null && mounted) {
        setState(() {
          _loadedSongId = null;
          _lyrics = null;
          _loadingLyrics = false;
          _lyricsTracker.setLineCount(0);
        });
      }
      return;
    }
    if (song.id == _loadedSongId) return;

    final songId = song.id;
    setState(() {
      _loadedSongId = songId;
      _loadingLyrics = true;
      _lyrics = null;
      _lyricsTracker.setLineCount(0);
    });

    try {
      final fetched = await widget.musicService.getSongLyrics(songId);
      if (mounted && _loadedSongId == songId) {
        setState(() {
          _lyrics = fetched;
          _loadingLyrics = false;
          _lyricsTracker.setLineCount(fetched.lines.length);
        });
      }
    } catch (_) {
      if (mounted && _loadedSongId == songId) {
        setState(() {
          _lyrics = SongLyricsModel(
            songId: songId,
            isSynced: false,
            source: 'none',
            lines: const [],
          );
          _loadingLyrics = false;
          _lyricsTracker.setLineCount(0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final coordinator = widget.coordinator;
    final session = coordinator.session;
    final song = coordinator.currentSong;
    final isPlaying = session?.state == PlaybackState.playing;
    final bgTop =
        Color.lerp(const Color(0xFF050507), tokens.accent, 0.18) ??
        const Color(0xFF14070B);

    return PopScope(
      canPop: _viewStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _viewStack.length > 1) {
          setState(() => _viewStack.removeLast());
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
        key: const Key('mobile-now-playing-page'),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, const Color(0xFF050507), tokens.bgSunken],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Drag pill + Top bar
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('mobile-player-close'),
                      tooltip: 'Close player',
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 28,
                        color: tokens.text,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _view == _MobilePlayerView.queue
                                ? 'QUEUE'
                                : _view == _MobilePlayerView.lyrics
                                    ? 'LYRICS'
                                    : 'NOW PLAYING',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: tokens.text3,
                            ),
                          ),
                          if ((coordinator.activeSourceLabel ?? '').isNotEmpty)
                            Text(
                              coordinator.activeSourceLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tokens.text2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (song != null)
                      IconButton(
                        key: const Key('mobile-player-more-menu'),
                        tooltip: 'Track options',
                        onPressed: () => unawaited(
                          _openTrackOptionsSheet(context, tokens, song),
                        ),
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 22,
                          color: tokens.text,
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: song == null
                    ? Center(
                        child: Text(
                          'Nothing playing right now.',
                          style: TextStyle(fontSize: 14, color: tokens.text2),
                        ),
                      )
                    : switch (_view) {
                        _MobilePlayerView.player => _buildPlayerBody(
                            context,
                            tokens,
                            song,
                            session,
                            isPlaying,
                          ),
                        _MobilePlayerView.queue => _buildQueueBody(
                            context,
                            tokens,
                            song,
                            session,
                          ),
                        _MobilePlayerView.lyrics => _buildLyricsBody(
                            context,
                            tokens,
                            song,
                          ),
                      },
              ),
              if (song != null && widget.coordinator.isControllingRemoteDevice)
                _buildMobileRemoteVolumeBar(
                  context,
                  accentColor: tokens.accent,
                  textColor: tokens.text,
                  mutedColor: tokens.text2,
                ),
              if (song != null) _buildMobileUtilityBar(context, tokens, session),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Future<void> _openTrackOptionsSheet(
    BuildContext context,
    HermesThemeTokens tokens,
    SongModel song,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
                leading: MusicArtworkTile(
                  size: 46,
                  title: song.albumTitle,
                  uri: widget.musicService.buildArtworkUri(song.artworkHash),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
                subtitle: Text(
                  song.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.text2),
                ),
              ),
              Divider(height: 1, color: tokens.lineSoft),
              ListTile(
                leading: Icon(
                  song.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: song.isLiked ? tokens.accent : tokens.text,
                ),
                title: Text(
                  song.isLiked
                      ? 'Remove from Liked Songs'
                      : 'Save to Liked Songs',
                  style: TextStyle(color: tokens.text),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(widget.coordinator.toggleLikeSong(song.id));
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: tokens.text),
                title: Text(
                  'Add to playlist',
                  style: TextStyle(color: tokens.text),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(_openAddToPlaylistPicker(tokens, song));
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: tokens.text),
                title: Text(
                  'Add to queue',
                  style: TextStyle(color: tokens.text),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  widget.coordinator.addToQueue(song);
                  showMusicToast(this.context, 'Added "${song.title}" to queue');
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: tokens.text),
                title: Text(
                  'Play next',
                  style: TextStyle(color: tokens.text),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  widget.coordinator.playNext(song);
                  showMusicToast(this.context, 'Playing "${song.title}" next');
                },
              ),
              if (song.albumId.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.album_rounded, color: tokens.text),
                  title: Text(
                    'Go to album',
                    style: TextStyle(color: tokens.text),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    widget.onNavigate(MusicPageRoute.album(song.albumId));
                  },
                ),
              if (song.artistId.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.person_rounded, color: tokens.text),
                  title: Text(
                    'Go to artist',
                    style: TextStyle(color: tokens.text),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    widget.onNavigate(MusicPageRoute.artist(song.artistId));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddToPlaylistPicker(
    HermesThemeTokens tokens,
    SongModel song,
  ) async {
    var playlists = widget.musicService.cachedPlaylists ?? const [];
    if (playlists.isEmpty) {
      try {
        playlists = await widget.musicService.listPlaylists();
      } catch (_) {
        playlists = const [];
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (pickerCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text(
                'Add to playlist',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
            ),
            Divider(height: 1, color: tokens.lineSoft),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No playlists created yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: tokens.text2),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (ctx, idx) {
                    final pl = playlists[idx];
                    return ListTile(
                      leading: MusicArtworkTile(
                        size: 40,
                        title: pl.name,
                        isPlaylist: true,
                      ),
                      title: Text(pl.name, style: TextStyle(color: tokens.text)),
                      subtitle: Text(
                        '${pl.trackCount} songs',
                        style: TextStyle(fontSize: 12, color: tokens.text2),
                      ),
                      onTap: () async {
                        Navigator.of(pickerCtx).pop();
                        try {
                          await widget.musicService.addTrackToPlaylist(
                            playlistId: pl.id,
                            songId: song.id,
                          );
                          if (mounted) {
                            showMusicToast(
                              context,
                              'Added "${song.title}" to ${pl.name}',
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            showMusicToast(context, 'Failed to add: $e');
                          }
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileUtilityBar(
    BuildContext context,
    HermesThemeTokens tokens,
    PlaybackSessionState? session,
  ) {
    final coordinator = widget.coordinator;
    final rendererLabel = coordinator.isLocalRenderer
        ? 'This device'
        : (session?.activeRendererDeviceName?.isNotEmpty == true
            ? session!.activeRendererDeviceName!
            : 'Remote device');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                key: const Key('mobile-player-devices'),
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onOpenDevices,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: coordinator.isLocalRenderer
                          ? Colors.white.withValues(alpha: 0.12)
                          : tokens.accent.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.speaker_group_rounded,
                        size: 16,
                        color: coordinator.isLocalRenderer
                            ? tokens.text2
                            : tokens.accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          rendererLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('mobile-player-lyrics-toggle'),
            tooltip: _view == _MobilePlayerView.lyrics
                ? 'Hide lyrics'
                : 'Lyrics',
            onPressed: () {
              if (_view != _MobilePlayerView.lyrics) {
                _lyricsTracker.resumeNow();
              }
              _toggleSubView(_MobilePlayerView.lyrics);
            },
            icon: Icon(
              Icons.lyrics_outlined,
              size: 20,
              color: _view == _MobilePlayerView.lyrics
                  ? tokens.accent
                  : tokens.text2,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('mobile-player-queue-toggle'),
            tooltip: _view == _MobilePlayerView.queue
                ? 'Hide queue'
                : 'View queue',
            onPressed: () => _toggleSubView(_MobilePlayerView.queue),
            icon: Icon(
              Icons.queue_music_rounded,
              size: 22,
              color: _view == _MobilePlayerView.queue
                  ? tokens.accent
                  : tokens.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBody(
    BuildContext context,
    HermesThemeTokens tokens,
    SongModel song,
    PlaybackSessionState? session,
    bool isPlaying,
  ) {
    final coordinator = widget.coordinator;
    final maxMs = song.durationMs > 0 ? song.durationMs : 1;
    final activeMs = (_dragPositionMs ?? coordinator.currentPositionMs).clamp(
      0,
      maxMs,
    );
    final shuffleOn = session?.shuffle ?? false;
    final repeatMode = session?.repeatMode ?? HermesRepeatMode.off;

    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = (constraints.maxHeight * 0.42)
            .clamp(120.0, 320.0)
            .clamp(120.0, (constraints.maxWidth - 48).clamp(120.0, 320.0));

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 24).clamp(0.0, 1200.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 4),
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: HermesArtworkImage(
                      uri: widget.musicService.buildArtworkUri(
                        song.artworkHash,
                      ),
                      fallbackTitle: song.albumTitle,
                      fallbackIcon: Icons.music_note_rounded,
                      width: artSize,
                      height: artSize,
                      borderRadius: BorderRadius.circular(16),
                      showFallbackLabel: false,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                onTap: song.albumId.isNotEmpty
                                    ? () => widget.onNavigate(
                                          MusicPageRoute.album(song.albumId),
                                        )
                                    : null,
                                child: HermesMarqueeText(
                                  song.title,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: tokens.text,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              ArtistCreditLine(
                                song: song,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: tokens.text2,
                                ),
                                onTapArtist: (artistId) => widget.onNavigate(
                                  MusicPageRoute.artist(artistId),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const Key('mobile-player-like'),
                          tooltip: song.isLiked
                              ? 'Remove from Liked Songs'
                              : 'Save to Liked Songs',
                          onPressed: () =>
                              unawaited(coordinator.toggleLikeSong(song.id)),
                          icon: Icon(
                            song.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 26,
                            color: song.isLiked ? tokens.accent : tokens.text2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: tokens.accent,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                        thumbColor: tokens.text,
                        overlayColor: tokens.accent.withValues(alpha: 0.2),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        key: const Key('mobile-player-seek'),
                        value: activeMs.toDouble(),
                        min: 0,
                        max: maxMs.toDouble(),
                        onChanged: (v) =>
                            setState(() => _dragPositionMs = v.round()),
                        onChangeEnd: (v) {
                          final target = v.round();
                          setState(() => _dragPositionMs = null);
                          unawaited(coordinator.seekTo(target));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDurationMs(activeMs),
                            style: TextStyle(
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: tokens.text2,
                            ),
                          ),
                          Text(
                            formatDurationMs(maxMs),
                            style: TextStyle(
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: tokens.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const Key('mobile-player-shuffle'),
                          tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle off',
                          onPressed: () => unawaited(coordinator.toggleShuffle()),
                          icon: Icon(
                            Icons.shuffle_rounded,
                            size: 22,
                            color: shuffleOn ? tokens.accent : tokens.text2,
                          ),
                        ),
                        IconButton(
                          key: const Key('mobile-player-prev'),
                          tooltip: 'Previous Track',
                          onPressed: () =>
                              unawaited(coordinator.skipPrevious()),
                          icon: Icon(
                            Icons.skip_previous_rounded,
                            size: 34,
                            color: tokens.text,
                          ),
                        ),
                        Material(
                          color: tokens.accent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const Key('mobile-player-play-pause'),
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                unawaited(coordinator.togglePlayPause()),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 36,
                                color: tokens.accentInk,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('mobile-player-next'),
                          tooltip: 'Next Track',
                          onPressed: () => unawaited(coordinator.skipNext()),
                          icon: Icon(
                            Icons.skip_next_rounded,
                            size: 34,
                            color: tokens.text,
                          ),
                        ),
                        IconButton(
                          key: const Key('mobile-player-repeat'),
                          tooltip: 'Repeat: ${repeatMode.name}',
                          onPressed: () =>
                              unawaited(coordinator.cycleRepeatMode()),
                          icon: Icon(
                            repeatMode == HermesRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            size: 22,
                            color: repeatMode == HermesRepeatMode.off
                                ? tokens.text2
                                : tokens.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQueueBody(
    BuildContext context,
    HermesThemeTokens tokens,
    SongModel song,
    PlaybackSessionState? session,
  ) {
    final coordinator = widget.coordinator;
    final upNext = coordinator.upNext;
    final fromSource = coordinator.upcomingFromSource;

    return Container(
      key: const Key('mobile-player-queue-view'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Text(
            'Now playing',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.text2,
            ),
          ),
          const SizedBox(height: 6),
          _MobileQueueRow(
            song: song,
            artworkUri: widget.musicService.buildArtworkUri(song.artworkHash),
            active: true,
            tokens: tokens,
            onTap: () => setState(() {
              _viewStack
                ..clear()
                ..add(_MobilePlayerView.player);
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Next in queue',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.text2,
                  ),
                ),
              ),
              if (upNext.isNotEmpty)
                TextButton(
                  onPressed: coordinator.clearUpNext,
                  child: Text(
                    'Clear',
                    style: TextStyle(fontSize: 12, color: tokens.text2),
                  ),
                ),
            ],
          ),
          if (upNext.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Swipe any song right to add it to the queue.',
                style: TextStyle(fontSize: 12, color: tokens.text3),
              ),
            )
          else
            for (var i = 0; i < upNext.length; i++)
              _MobileQueueRow(
                song: upNext[i],
                artworkUri: widget.musicService.buildArtworkUri(
                  upNext[i].artworkHash,
                ),
                active: false,
                tokens: tokens,
                onTap: () => unawaited(coordinator.playUpNextAt(i)),
                onRemove: () => coordinator.removeFromUpNext(i),
              ),
          if (fromSource.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Up next from ${coordinator.activeSourceLabel ?? "library"}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.text2,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < fromSource.length; i++)
              _MobileQueueRow(
                song: fromSource[i],
                artworkUri: widget.musicService.buildArtworkUri(
                  fromSource[i].artworkHash,
                ),
                active: false,
                tokens: tokens,
                onTap: () => unawaited(
                  coordinator.playAtIndex((session?.currentIndex ?? 0) + 1 + i),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLyricsBody(
    BuildContext context,
    HermesThemeTokens tokens,
    SongModel song,
  ) {
    final posMs = widget.coordinator.currentPositionMs;
    if (_loadingLyrics) {
      return Container(
        key: const Key('mobile-player-lyrics-view'),
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Container(
        key: const Key('mobile-player-lyrics-view'),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 36, color: tokens.text3),
            const SizedBox(height: 10),
            Text(
              'No lyrics available for "${song.title}"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
          ],
        ),
      );
    }

    var activeIndex = -1;
    if (lyrics.isSynced) {
      for (var i = 0; i < lyrics.lines.length; i++) {
        final ts = lyrics.lines[i].timestampMs;
        if (ts != null && ts <= posMs) {
          activeIndex = i;
        }
      }
      _lyricsTracker.scheduleIfNeeded(
        activeIndex: activeIndex,
        isMounted: () => mounted,
      );
    }

    return Container(
      key: const Key('mobile-player-lyrics-view'),
      child: Column(
        children: [
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _lyricsTracker.handleUserScroll,
              child: SingleChildScrollView(
                controller: _lyricsTracker.scrollController,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lyrics.lines.length; i++)
                      InkWell(
                        key: i < _lyricsTracker.lineKeys.length
                            ? _lyricsTracker.lineKeys[i]
                            : null,
                        onTap: lyrics.lines[i].timestampMs != null
                            ? () {
                                _lyricsTracker.resumeNow();
                                unawaited(
                                  widget.coordinator.seekTo(
                                    lyrics.lines[i].timestampMs!,
                                  ),
                                );
                              }
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: Text(
                            lyrics.lines[i].text,
                            style: TextStyle(
                              fontSize: i == activeIndex ? 20 : 17,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                              color: !lyrics.isSynced || i == activeIndex
                                  ? tokens.text
                                  : tokens.text3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileRemoteVolumeBar(
    BuildContext context, {
    required Color accentColor,
    required Color textColor,
    required Color mutedColor,
  }) {
    final effective =
        (_volumeDrag ?? widget.coordinator.effectiveVolume).clamp(0.0, 1.0);
    return Padding(
      key: const Key('mobile-player-remote-volume-bar'),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: effective == 0
                  ? 'Unmute remote device'
                  : 'Mute remote device',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(widget.coordinator.toggleMute()),
              icon: Icon(
                effective == 0
                    ? Icons.volume_off_rounded
                    : effective < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                size: 19,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Remote',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  activeTrackColor: accentColor,
                  inactiveTrackColor: textColor.withValues(alpha: 0.18),
                  thumbColor: accentColor,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 11,
                  ),
                ),
                child: Slider(
                  value: effective,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    setState(() => _volumeDrag = v);
                    unawaited(
                      widget.coordinator.setVolume(v, immediate: false),
                    );
                  },
                  onChangeEnd: (v) {
                    setState(() => _volumeDrag = null);
                    unawaited(
                      widget.coordinator.setVolume(v, immediate: true),
                    );
                  },
                ),
              ),
            ),
            Text(
              '${(effective * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileQueueRow extends StatelessWidget {
  const _MobileQueueRow({
    required this.song,
    required this.artworkUri,
    required this.active,
    required this.tokens,
    required this.onTap,
    this.onRemove,
  });

  final SongModel song;
  final Uri? artworkUri;
  final bool active;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            MusicArtworkTile(
              size: 44,
              title: song.albumTitle,
              uri: artworkUri,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? tokens.accent : tokens.text,
                    ),
                  ),
                  ArtistCreditLine(
                    song: song,
                    style: TextStyle(fontSize: 12, color: tokens.text2),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove from queue',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
