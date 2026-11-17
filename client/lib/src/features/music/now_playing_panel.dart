import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';
import 'music_shared_widgets.dart';

enum NowPlayingTab { queue, lyrics }

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
    });

    try {
      final fetched = await widget.musicService.getSongLyrics(song.id);
      if (mounted && _loadedSongId == song.id) {
        setState(() {
          _lyrics = fetched;
          _loadingLyrics = false;
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
            child: ListView(
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () =>
                                widget.onNavigate(MusicPageRoute.album(song.albumId)),
                            child: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.01,
                                color: tokens.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: () =>
                                widget.onNavigate(MusicPageRoute.artist(song.artistId)),
                            child: Text(
                              song.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: tokens.text2),
                            ),
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
                      onTap: () => setState(() => _tab = NowPlayingTab.lyrics),
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
              onTap: () => unawaited(coordinator.skipNext()),
              onRemove: () => coordinator.removeFromUpNext(i),
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
            ),
      ],
    );
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
    if (lyrics.isSynced) {
      for (var i = 0; i < lyrics.lines.length; i++) {
        final ts = lyrics.lines[i].timestampMs;
        if (ts != null && session.positionMs >= ts) {
          activeIndex = i;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lyrics.lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: lyrics.lines[i].timestampMs != null
                    ? () => unawaited(
                        widget.coordinator.seekTo(lyrics.lines[i].timestampMs!),
                      )
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
    this.active = false,
    this.trailing,
    this.onRemove,
  });

  final SongModel song;
  final Uri? artworkUri;
  final VoidCallback onTap;
  final bool active;
  final Widget? trailing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
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
                  Text(
                    song.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
