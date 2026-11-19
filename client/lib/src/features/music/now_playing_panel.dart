import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_marquee_text.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';
import 'music_shared_widgets.dart';

enum NowPlayingTab { queue, lyrics }

class _LyricsAutoScrollTracker {
  final ScrollController scrollController = ScrollController();
  List<GlobalKey> lineKeys = const [];
  int _lastIndex = -1;
  DateTime? _pausedUntil;

  void setLineCount(int count) {
    lineKeys = count <= 0 ? const [] : List.generate(count, (_) => GlobalKey());
    _lastIndex = -1;
  }

  void resumeNow() {
    _pausedUntil = null;
    _lastIndex = -1;
  }

  void pauseTemporarily([Duration duration = const Duration(seconds: 4)]) {
    _pausedUntil = DateTime.now().add(duration);
  }

  bool handleUserScroll(UserScrollNotification notification) {
    if (notification.direction != ScrollDirection.idle) {
      pauseTemporarily();
    }
    return false;
  }

  void scheduleIfNeeded({
    required int activeIndex,
    required bool Function() isMounted,
    double alignment = 0.35,
  }) {
    if (activeIndex < 0 || activeIndex >= lineKeys.length) return;
    if (activeIndex == _lastIndex) return;
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) {
      return;
    }
    _lastIndex = activeIndex;
    final key = lineKeys[activeIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) return;
      final ctx = key.currentContext;
      if (ctx == null) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          alignment: alignment,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void dispose() {
    scrollController.dispose();
  }
}

/// Figma v4 `.np-panel` side panel showing current cover, Queue management, Lyrics, and active device.
class NowPlayingPanel extends StatefulWidget {
  const NowPlayingPanel({
    super.key,
    required this.coordinator,
    required this.musicService,
    required this.localDeviceId,
    required this.onClose,
    required this.onOpenDevices,
    required this.onNavigate,
    this.isModal = false,
  });

  final MusicPlaybackCoordinator coordinator;
  final MusicService musicService;
  final String localDeviceId;
  final VoidCallback onClose;
  final VoidCallback onOpenDevices;
  final ValueChanged<MusicPageRoute> onNavigate;
  final bool isModal;

  @override
  State<NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends State<NowPlayingPanel> {
  NowPlayingTab _tab = NowPlayingTab.queue;
  String? _loadedSongId;
  SongLyricsModel? _lyrics;
  bool _loadingLyrics = false;
  final _LyricsAutoScrollTracker _lyricsTracker = _LyricsAutoScrollTracker();

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onCoordinatorChanged);
    unawaited(_ensureLyrics());
  }

  @override
  void didUpdateWidget(covariant NowPlayingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_onCoordinatorChanged);
      widget.coordinator.addListener(_onCoordinatorChanged);
    }
    unawaited(_ensureLyrics());
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

    if (song.id == _loadedSongId) {
      return;
    }

    _loadedSongId = song.id;
    setState(() {
      _loadingLyrics = true;
      _lyrics = null;
      _lyricsTracker.setLineCount(0);
    });

    try {
      final fetched = await widget.musicService.getSongLyrics(song.id);
      if (mounted && _loadedSongId == song.id) {
        setState(() {
          _lyrics = fetched;
          _loadingLyrics = false;
          _lyricsTracker.setLineCount(fetched.lines.length);
        });
      }
    } catch (_) {
      if (mounted && _loadedSongId == song.id) {
        setState(() {
          _lyrics = SongLyricsModel(
            songId: song.id,
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
    final song = coordinator.currentSong;
    final session = coordinator.session;
    if (song == null || session == null) {
      return const SizedBox.shrink();
    }

    final tint = deriveMusicTint(song.albumTitle, fallback: tokens.surface3);
    final isPlaying = session.state == PlaybackState.playing;
    final sourceLabel = coordinator.activeSourceLabel ?? song.albumTitle;
    final sourceRoute = coordinator.activeSourceRoute ?? MusicPageRoute.album(song.albumId);
    final isRemote = session.activeRendererDeviceId != null &&
        session.activeRendererDeviceId != widget.localDeviceId;
    final deviceLabel = isRemote
        ? (session.activeRendererDeviceName ?? session.activeRendererDeviceId!)
        : 'This Device';

    final content = Container(
      width: widget.isModal ? double.infinity : 340,
      margin: widget.isModal
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(0, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.isModal ? 12 : 8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, 0.35),
          colors: [
            Color.lerp(tokens.surface, tint, 0.55)!,
            tokens.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onNavigate(sourceRoute),
                    child: Text(
                      sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close panel',
                  onPressed: widget.onClose,
                  icon: Icon(Icons.close_rounded, size: 18, color: tokens.text2),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _lyricsTracker.handleUserScroll,
              child: ListView(
                controller: _lyricsTracker.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: MusicArtworkTile(
                        size: constraints.maxWidth,
                        title: song.albumTitle,
                        uri: widget.musicService.buildArtworkUri(song.artworkHash),
                        borderRadius: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () =>
                                widget.onNavigate(MusicPageRoute.album(song.albumId)),
                            child: HermesMarqueeText(
                              song.title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.01,
                                color: tokens.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          ArtistCreditLine(
                            song: song,
                            style: TextStyle(fontSize: 13, color: tokens.text2),
                            onTapArtist: (artistId) =>
                                widget.onNavigate(MusicPageRoute.artist(artistId)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: song.isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs',
                      onPressed: () => unawaited(coordinator.toggleLikeSong(song.id)),
                      icon: Icon(
                        song.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: song.isLiked ? tokens.accent : tokens.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _UnderlineTabButton(
                      label: 'Queue',
                      selected: _tab == NowPlayingTab.queue,
                      onTap: () => setState(() => _tab = NowPlayingTab.queue),
                    ),
                    const SizedBox(width: 20),
                    _UnderlineTabButton(
                      label: 'Lyrics',
                      selected: _tab == NowPlayingTab.lyrics,
                      onTap: () {
                        _lyricsTracker.resumeNow();
                        setState(() => _tab = NowPlayingTab.lyrics);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_tab == NowPlayingTab.queue)
                  _buildQueueSection(context, tokens, song, session, isPlaying, sourceLabel)
                else
                  _buildLyricsSection(context, tokens, session),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isRemote ? Icons.speaker_group_rounded : Icons.computer_rounded,
                        size: 20,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Playing on',
                              style: TextStyle(fontSize: 11, color: tokens.text2),
                            ),
                            Text(
                              deviceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tokens.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onOpenDevices,
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        child: const Text(
                          'Change',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );

    return content;
  }

  Widget _buildQueueSection(
    BuildContext context,
    HermesThemeTokens tokens,
    SongModel song,
    PlaybackSessionState session,
    bool isPlaying,
    String sourceLabel,
  ) {
    final coordinator = widget.coordinator;
    final upNext = coordinator.upNext;
    final fromSource = coordinator.upcomingFromSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            'Now playing',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tokens.text,
            ),
          ),
        ),
        _QueueRowTile(
          song: song,
          artworkUri: widget.musicService.buildArtworkUri(song.artworkHash),
          active: true,
          trailing: isPlaying ? HermesEqBars(color: tokens.accent, height: 12) : null,
          onTap: () => widget.onNavigate(MusicPageRoute.album(song.albumId)),
          onSecondaryTapDown: (d) => unawaited(
            _openQueueContextMenu(context, d.globalPosition, song, includePlayNow: false),
          ),
        ),
        if (upNext.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Next in queue',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
                InkWell(
                  onTap: coordinator.clearUpNext,
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < upNext.length; i++)
            _QueueRowTile(
              song: upNext[i],
              artworkUri: widget.musicService.buildArtworkUri(upNext[i].artworkHash),
              onTap: () => unawaited(coordinator.playUpNextAt(i)),
              onRemove: () => coordinator.removeFromUpNext(i),
              onSecondaryTapDown: (d) => unawaited(
                _openQueueContextMenu(
                  context,
                  d.globalPosition,
                  upNext[i],
                  upNextIndex: i,
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Next from $sourceLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
              ),
              if (session.shuffle)
                Text(
                  'Shuffled',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
        ),
        if (fromSource.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'End of queue.',
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          )
        else
          for (var i = 0; i < fromSource.length; i++)
            _QueueRowTile(
              song: fromSource[i],
              artworkUri:
                  widget.musicService.buildArtworkUri(fromSource[i].artworkHash),
              onTap: () =>
                  unawaited(coordinator.playAtIndex(session.currentIndex + 1 + i)),
              onSecondaryTapDown: (d) => unawaited(
                _openQueueContextMenu(
                  context,
                  d.globalPosition,
                  fromSource[i],
                  queueSongIndex: session.currentIndex + 1 + i,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _openQueueContextMenu(
    BuildContext context,
    Offset globalPosition,
    SongModel song, {
    int? upNextIndex,
    int? queueSongIndex,
    bool includePlayNow = true,
  }) async {
    final coordinator = widget.coordinator;
    final currentSong = coordinator.songById(song.id) ?? song;
    final items = buildMusicSongMenuItems(
      song: currentSong,
      showPlayNow: includePlayNow,
      showRemoveFromQueue: upNextIndex != null,
    );
    final chosen = await showMusicContextMenu<String>(
      context,
      globalPosition,
      items,
    );
    if (chosen == null || !mounted) return;

    if (chosen == 'play') {
      if (upNextIndex != null) {
        await coordinator.playUpNextAt(upNextIndex);
      } else if (queueSongIndex != null) {
        await coordinator.playAtIndex(queueSongIndex);
      }
    } else if (chosen == 'queue') {
      coordinator.addToQueue(currentSong);
      if (context.mounted) {
        showMusicToast(context, 'Added "${currentSong.title}" to queue');
      }
    } else if (chosen == 'next') {
      coordinator.playNext(currentSong);
      if (context.mounted) {
        showMusicToast(context, 'Playing "${currentSong.title}" next');
      }
    } else if (chosen == 'queue_remove' && upNextIndex != null) {
      coordinator.removeFromUpNext(upNextIndex);
    } else if (chosen == 'album') {
      widget.onNavigate(MusicPageRoute.album(currentSong.albumId));
    } else if (chosen == 'artist') {
      widget.onNavigate(MusicPageRoute.artist(currentSong.artistId));
    } else if (chosen == 'like') {
      unawaited(coordinator.toggleLikeSong(currentSong.id));
    }
  }

  Widget _buildLyricsSection(
    BuildContext context,
    HermesThemeTokens tokens,
    PlaybackSessionState session,
  ) {
    if (_loadingLyrics) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No lyrics available',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lyrics appear when the file has them embedded or an .lrc file sits next to it.',
              style: TextStyle(fontSize: 13, height: 1.5, color: tokens.text2),
            ),
          ],
        ),
      );
    }

    var activeIndex = -1;
    final positionMs = widget.coordinator.currentPositionMs;
    if (lyrics.isSynced) {
      for (var i = 0; i < lyrics.lines.length; i++) {
        final ts = lyrics.lines[i].timestampMs;
        if (ts != null && positionMs >= ts) {
          activeIndex = i;
        }
      }
      _lyricsTracker.scheduleIfNeeded(
        activeIndex: activeIndex,
        isMounted: () => mounted,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lyrics.lines.length; i++)
            Padding(
              key: i < _lyricsTracker.lineKeys.length
                  ? _lyricsTracker.lineKeys[i]
                  : null,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: lyrics.lines[i].timestampMs != null
                    ? () {
                        _lyricsTracker.resumeNow();
                        unawaited(
                          widget.coordinator.seekTo(lyrics.lines[i].timestampMs!),
                        );
                      }
                    : null,
                child: Text(
                  lyrics.lines[i].text,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.01,
                    color: !lyrics.isSynced
                        ? tokens.text.withValues(alpha: 0.85)
                        : i == activeIndex
                            ? tokens.text
                            : i < activeIndex
                                ? tokens.text.withValues(alpha: 0.58)
                                : tokens.text.withValues(alpha: 0.34),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnderlineTabButton extends StatelessWidget {
  const _UnderlineTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? tokens.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? tokens.text : tokens.text2,
          ),
        ),
      ),
    );
  }
}

class _QueueRowTile extends StatelessWidget {
  const _QueueRowTile({
    required this.song,
    required this.artworkUri,
    required this.onTap,
    this.onSecondaryTapDown,
    this.active = false,
    this.trailing,
    this.onRemove,
  });

  final SongModel song;
  final Uri? artworkUri;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool active;
  final Widget? trailing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            MusicArtworkTile(
              size: 42,
              title: song.albumTitle,
              uri: artworkUri,
              borderRadius: 4,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
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
            ?trailing,
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove from queue',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 16, color: tokens.text2),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

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
                              InkWell(
                                onTap: song.artistId.isNotEmpty
                                    ? () => widget.onNavigate(
                                          MusicPageRoute.artist(song.artistId),
                                        )
                                    : null,
                                child: HermesMarqueeText(
                                  song.artistName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: tokens.text2,
                                  ),
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
