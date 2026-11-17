import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';

/// Displays a flat Spotify-style right-click context menu anchored at [globalPosition].
Future<T?> showMusicContextMenu<T>(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<T>> items,
) {
  if (items.isEmpty) return Future<T?>.value(null);
  final tokens = HermesThemeTokens.of(context);
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  final overlaySize = overlayBox?.size ?? MediaQuery.sizeOf(context);
  final rect = Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1);

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlaySize),
    color: tokens.surface3,
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: tokens.line),
    ),
    items: items,
  );
}

List<PopupMenuEntry<String>> buildMusicSongMenuItems({
  required SongModel song,
  List<PlaylistSummaryModel> playlists = const [],
  String? playlistIdForRemoval,
  bool showPlayNow = false,
  bool showRemoveFromQueue = false,
}) {
  return [
    if (showPlayNow)
      const PopupMenuItem(value: 'play', child: Text('Play now')),
    const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
    const PopupMenuItem(value: 'next', child: Text('Play next')),
    if (showRemoveFromQueue)
      const PopupMenuItem(value: 'queue_remove', child: Text('Remove from queue')),
    const PopupMenuDivider(),
    const PopupMenuItem(value: 'album', child: Text('Go to album')),
    const PopupMenuItem(value: 'artist', child: Text('Go to artist')),
    PopupMenuItem(
      value: 'like',
      child: Text(song.isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs'),
    ),
    if (playlistIdForRemoval != null)
      const PopupMenuItem(
        value: 'remove',
        child: Text('Remove from this playlist'),
      ),
    if (playlists.isNotEmpty) ...[
      const PopupMenuDivider(),
      for (final pl in playlists)
        PopupMenuItem(
          value: 'pl:${pl.id}',
          child: Text('Add to ${pl.name}'),
        ),
    ],
  ];
}

Future<void> openMusicCollectionContextMenu(
  BuildContext context,
  Offset globalPosition, {
  String openLabel = 'Open',
  required VoidCallback onOpen,
  VoidCallback? onPlay,
  VoidCallback? onAddToQueue,
  List<PopupMenuEntry<String>> extraItems = const [],
  ValueChanged<String>? onExtraSelected,
}) async {
  final items = <PopupMenuEntry<String>>[
    PopupMenuItem(value: 'open', child: Text(openLabel)),
    if (onPlay != null)
      const PopupMenuItem(value: 'play', child: Text('Play')),
    if (onAddToQueue != null)
      const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
    if (extraItems.isNotEmpty) ...[
      const PopupMenuDivider(),
      ...extraItems,
    ],
  ];

  final choice = await showMusicContextMenu<String>(
    context,
    globalPosition,
    items,
  );
  if (choice == null) return;
  if (choice == 'open') {
    onOpen();
  } else if (choice == 'play') {
    onPlay?.call();
  } else if (choice == 'queue') {
    onAddToQueue?.call();
  } else {
    onExtraSelected?.call(choice);
  }
}

void showMusicToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Three-bar equalizer indicator matching Figma `.eq` for active playback rows and Connect cards.
/// Uses bounded state transitions rather than an infinite ticker so frame scheduling settles cleanly.
class HermesEqBars extends StatelessWidget {
  const HermesEqBars({
    super.key,
    this.color,
    this.paused = false,
    this.height = 14,
  });

  final Color? color;
  final bool paused;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final resolved = color ?? tokens.accent;
    final factors = paused
        ? const [0.35, 0.35, 0.35]
        : const [0.55, 1.0, 0.72];

    return SizedBox(
      width: 14,
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final factor in factors)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 3,
              height: (height * factor).clamp(3.0, height),
              decoration: BoxDecoration(
                color: resolved,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Circular Play/Pause action using optically centered [HermesPlayIcon] and [HermesPauseIcon].
class HermesCircularPlayButton extends StatefulWidget {
  const HermesCircularPlayButton({
    super.key,
    required this.onPressed,
    this.size = 48,
    this.iconSize,
    this.isPlaying = false,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final double size;
  final double? iconSize;
  final bool isPlaying;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;

  @override
  State<HermesCircularPlayButton> createState() =>
      _HermesCircularPlayButtonState();
}

class _HermesCircularPlayButtonState extends State<HermesCircularPlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final bg = widget.backgroundColor ?? tokens.accent;
    final fg = widget.iconColor ?? tokens.accentInk;
    final iconSz = widget.iconSize ?? (widget.size * 0.44);
    final enabled = widget.onPressed != null;

    final child = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      label: widget.tooltip ?? (widget.isPlaying ? 'Pause' : 'Play'),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: (_hovered && enabled) ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: Material(
            color: enabled ? bg : bg.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(
                  child: widget.isPlaying
                      ? HermesPauseIcon(size: iconSz, color: fg)
                      : HermesPlayIcon(size: iconSz, color: fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null) {
      return child;
    }
    return Tooltip(message: widget.tooltip!, child: child);
  }
}

/// Renders artwork or specialized Liked Songs / Smart Playlist / Playlist cover tiles.
class MusicArtworkTile extends StatelessWidget {
  const MusicArtworkTile({
    super.key,
    required this.size,
    required this.title,
    this.uri,
    this.borderRadius = 4,
    this.circular = false,
    this.isLikedCollection = false,
    this.smartKind,
    this.isPlaylist = false,
  });

  final double size;
  final String title;
  final Uri? uri;
  final double borderRadius;
  final bool circular;
  final bool isLikedCollection;
  final SmartPlaylistKind? smartKind;
  final bool isPlaylist;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final radius = circular
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(borderRadius);

    if (isLikedCollection) {
      return ExcludeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tokens.accent.withValues(alpha: 0.55),
                  tokens.accent,
                ],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: (size * 0.42).clamp(16.0, 72.0),
              ),
            ),
          ),
        ),
      );
    }

    if (smartKind != null) {
      final icon = switch (smartKind!) {
        SmartPlaylistKind.recentlyAdded => Icons.auto_awesome_rounded,
        SmartPlaylistKind.losslessMasters => Icons.graphic_eq_rounded,
        SmartPlaylistKind.freshMix => Icons.shuffle_rounded,
      };
      return ExcludeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            width: size,
            height: size,
            color: tokens.surface3,
            child: Center(
              child: Icon(
                icon,
                color: tokens.accent,
                size: (size * 0.42).clamp(16.0, 72.0),
              ),
            ),
          ),
        ),
      );
    }

    return HermesArtworkImage(
      uri: uri,
      fallbackTitle: title,
      fallbackIcon: isPlaylist ? Icons.queue_music_rounded : Icons.album_rounded,
      width: size,
      height: size,
      borderRadius: radius,
      showFallbackLabel: size >= 120,
    );
  }
}

/// Collection action bar matching Figma `.action-bar` (`Play`, `Shuffle`, and optional Rename/Delete).
class MusicCollectionActionBar extends StatelessWidget {
  const MusicCollectionActionBar({
    super.key,
    required this.canPlay,
    required this.isPlayingThisCollection,
    required this.shuffleEnabled,
    required this.onPlayPressed,
    required this.onToggleShuffle,
    this.onRenamePlaylist,
    this.onDeletePlaylist,
  });

  final bool canPlay;
  final bool isPlayingThisCollection;
  final bool shuffleEnabled;
  final VoidCallback onPlayPressed;
  final VoidCallback onToggleShuffle;
  final VoidCallback? onRenamePlaylist;
  final VoidCallback? onDeletePlaylist;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HermesCircularPlayButton(
            size: 54,
            iconSize: 22,
            isPlaying: isPlayingThisCollection,
            onPressed: canPlay ? onPlayPressed : null,
            tooltip: isPlayingThisCollection ? 'Pause' : 'Play',
          ),
          _DotIconToggle(
            icon: Icons.shuffle_rounded,
            active: shuffleEnabled,
            tooltip: shuffleEnabled ? 'Shuffle on' : 'Shuffle off',
            onPressed: onToggleShuffle,
          ),
          if (onRenamePlaylist != null || onDeletePlaylist != null)
            Wrap(
              spacing: 16,
              children: [
                if (onRenamePlaylist != null)
                  TextButton(
                    onPressed: onRenamePlaylist,
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.text2,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    child: const Text(
                      'Rename',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (onDeletePlaylist != null)
                  TextButton(
                    onPressed: onDeletePlaylist,
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.text2,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DotIconToggle extends StatelessWidget {
  const _DotIconToggle({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        button: true,
        selected: active,
        excludeSemantics: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? tokens.accent : tokens.text2,
                ),
                if (active) ...[
                  const SizedBox(height: 2),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spotify-style track table with disc grouping, hover play/EQ, heart toggle, format tag, and overflow menu.
class MusicTrackTable extends StatelessWidget {
  const MusicTrackTable({
    super.key,
    required this.songs,
    required this.musicService,
    required this.coordinator,
    required this.playlists,
    required this.onPlayTrackAt,
    required this.onToggleLike,
    required this.onNavigate,
    this.showAlbum = true,
    this.discGrouping = false,
    this.playlistIdForRemoval,
    this.onRemoveFromPlaylist,
    this.onAddToPlaylist,
    this.emptyTitle = 'No tracks yet',
    this.emptySubtitle = 'Add tracks or scan a music folder to see songs here.',
  });

  final List<SongModel> songs;
  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final List<PlaylistSummaryModel> playlists;
  final ValueChanged<int> onPlayTrackAt;
  final ValueChanged<SongModel> onToggleLike;
  final ValueChanged<MusicPageRoute> onNavigate;
  final bool showAlbum;
  final bool discGrouping;
  final String? playlistIdForRemoval;
  final Future<void> Function(String playlistId, int position)? onRemoveFromPlaylist;
  final Future<void> Function(String playlistId, SongModel song)? onAddToPlaylist;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    if (songs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emptyTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tokens.text2),
              ),
            ],
          ),
        ),
      );
    }

    final distinctDiscs = songs.map((s) => s.discNumber).toSet().length;
    final showDiscHeaders = discGrouping && distinctDiscs > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 660;
        final showAlbumCol = showAlbum && constraints.maxWidth >= 560;
        final session = coordinator.session;
        final activeSongId = session?.currentSongId;
        final isPlaying = session?.state == PlaybackState.playing;

        final children = <Widget>[
          _TrackTableHeader(showAlbumCol: showAlbumCol, wide: wide),
          const SizedBox(height: 6),
        ];

        int? lastDisc;
        for (var i = 0; i < songs.length; i++) {
          final song = songs[i];
          if (showDiscHeaders && song.discNumber != lastDisc) {
            lastDisc = song.discNumber;
            final discDurationMs = songs
                .where((s) => s.discNumber == lastDisc)
                .fold<int>(0, (sum, s) => sum + s.durationMs);
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                child: Row(
                  children: [
                    Icon(Icons.album_outlined, size: 16, color: tokens.text2),
                    const SizedBox(width: 8),
                    Text(
                      'Disc $lastDisc',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatDurationMs(discDurationMs),
                      style: TextStyle(fontSize: 12, color: tokens.text2),
                    ),
                  ],
                ),
              ),
            );
          }

          final isCurrent = song.id == activeSongId;
          final effectiveLiked =
              coordinator.songById(song.id)?.isLiked ?? song.isLiked;

          children.add(
            _TrackTableRow(
              song: song.copyWith(isLiked: effectiveLiked),
              displayIndex: discGrouping ? song.trackNumber : (i + 1),
              positionInList: i,
              isCurrent: isCurrent,
              isPlaying: isCurrent && isPlaying,
              showArt: !discGrouping,
              showAlbumCol: showAlbumCol,
              wide: wide,
              artworkUri: musicService.buildArtworkUri(song.artworkHash),
              playlists: playlists,
              playlistIdForRemoval: playlistIdForRemoval,
              onPlay: () => onPlayTrackAt(i),
              onToggleLike: () => onToggleLike(song),
              onAddToQueue: () {
                coordinator.addToQueue(song);
                showMusicToast(context, 'Added "${song.title}" to queue');
              },
              onPlayNext: () {
                coordinator.playNext(song);
                showMusicToast(context, 'Playing "${song.title}" next');
              },
              onGoToAlbum: () => onNavigate(MusicPageRoute.album(song.albumId)),
              onGoToArtist: () => onNavigate(MusicPageRoute.artist(song.artistId)),
              onAddToPlaylist: onAddToPlaylist,
              onRemoveFromPlaylist: onRemoveFromPlaylist,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _TrackTableHeader extends StatelessWidget {
  const _TrackTableHeader({required this.showAlbumCol, required this.wide});

  final bool showAlbumCol;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: tokens.text2,
    );

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: wide ? 36 : 28,
            child: Text('#', textAlign: TextAlign.right, style: headerStyle),
          ),
          const SizedBox(width: 14),
          Expanded(flex: 5, child: Text('Title', style: headerStyle)),
          if (showAlbumCol)
            Expanded(flex: 3, child: Text('Album', style: headerStyle)),
          const SizedBox(width: 40),
          SizedBox(
            width: wide ? 112 : 96,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.schedule_rounded, size: 15, color: tokens.text2),
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _TrackTableRow extends StatefulWidget {
  const _TrackTableRow({
    required this.song,
    required this.displayIndex,
    required this.positionInList,
    required this.isCurrent,
    required this.isPlaying,
    required this.showArt,
    required this.showAlbumCol,
    required this.wide,
    required this.artworkUri,
    required this.playlists,
    required this.onPlay,
    required this.onToggleLike,
    required this.onAddToQueue,
    required this.onPlayNext,
    required this.onGoToAlbum,
    required this.onGoToArtist,
    this.playlistIdForRemoval,
    this.onAddToPlaylist,
    this.onRemoveFromPlaylist,
  });

  final SongModel song;
  final int displayIndex;
  final int positionInList;
  final bool isCurrent;
  final bool isPlaying;
  final bool showArt;
  final bool showAlbumCol;
  final bool wide;
  final Uri? artworkUri;
  final List<PlaylistSummaryModel> playlists;
  final VoidCallback onPlay;
  final VoidCallback onToggleLike;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final VoidCallback onGoToAlbum;
  final VoidCallback onGoToArtist;
  final String? playlistIdForRemoval;
  final Future<void> Function(String playlistId, SongModel song)? onAddToPlaylist;
  final Future<void> Function(String playlistId, int position)? onRemoveFromPlaylist;

  @override
  State<_TrackTableRow> createState() => _TrackTableRowState();
}

class _TrackTableRowState extends State<_TrackTableRow> {
  bool _hovered = false;

  Future<void> _handleMenuSelection(String value) async {
    if (value == 'play') {
      widget.onPlay();
    } else if (value == 'queue') {
      widget.onAddToQueue();
    } else if (value == 'next') {
      widget.onPlayNext();
    } else if (value == 'album') {
      widget.onGoToAlbum();
    } else if (value == 'artist') {
      widget.onGoToArtist();
    } else if (value == 'like') {
      widget.onToggleLike();
    } else if (value == 'remove' &&
        widget.playlistIdForRemoval != null &&
        widget.onRemoveFromPlaylist != null) {
      await widget.onRemoveFromPlaylist!(
        widget.playlistIdForRemoval!,
        widget.positionInList,
      );
    } else if (value.startsWith('pl:') && widget.onAddToPlaylist != null) {
      await widget.onAddToPlaylist!(value.substring(3), widget.song);
    }
  }

  List<PopupMenuEntry<String>> _menuItems({required bool includePlayNow}) {
    return buildMusicSongMenuItems(
      song: widget.song,
      playlists: widget.playlists,
      playlistIdForRemoval: widget.playlistIdForRemoval,
      showPlayNow: includePlayNow,
    );
  }

  Future<void> _openContextMenu(Offset globalPosition) async {
    final chosen = await showMusicContextMenu<String>(
      context,
      globalPosition,
      _menuItems(includePlayNow: true),
    );
    if (chosen != null) {
      await _handleMenuSelection(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final song = widget.song;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onPlay,
          onSecondaryTapDown: (details) =>
              unawaited(_openContextMenu(details.globalPosition)),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: widget.wide ? 36 : 28,
                  child: ExcludeSemantics(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _hovered
                          ? HermesPlayIcon(size: 14, color: tokens.text)
                          : widget.isPlaying
                              ? HermesEqBars(color: tokens.accent, height: 13)
                              : Text(
                                  '${widget.displayIndex}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                    color: widget.isCurrent ? tokens.accent : tokens.text2,
                                  ),
                                ),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    if (widget.showArt) ...[
                      MusicArtworkTile(
                        size: 40,
                        title: song.albumTitle,
                        uri: widget.artworkUri,
                        borderRadius: 4,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.isCurrent ? tokens.accent : tokens.text,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            song.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: tokens.text2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showAlbumCol)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: widget.onGoToAlbum,
                      child: Text(
                        song.albumTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: tokens.text2),
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 40,
                child: Semantics(
                  container: true,
                  button: true,
                  toggled: song.isLiked,
                  excludeSemantics: true,
                  label: song.isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs',
                  onTap: widget.onToggleLike,
                  child: Opacity(
                    alwaysIncludeSemantics: true,
                    opacity: (song.isLiked || _hovered || !widget.wide) ? 1.0 : 0.0,
                    child: IconButton(
                      tooltip: song.isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        song.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 17,
                        color: song.isLiked ? tokens.accent : tokens.text2,
                      ),
                      onPressed: widget.onToggleLike,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: widget.wide ? 112 : 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (song.codec.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          song.codec.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tokens.text3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      formatDurationMs(song.durationMs),
                      style: TextStyle(
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: tokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 32,
                child: PopupMenuButton<String>(
                  tooltip: 'Track options',
                  padding: EdgeInsets.zero,
                  color: tokens.surface3,
                  surfaceTintColor: Colors.transparent,
                  icon: Icon(Icons.more_horiz_rounded, size: 18, color: tokens.text2),
                  onSelected: (value) => unawaited(_handleMenuSelection(value)),
                  itemBuilder: (_) => _menuItems(includePlayNow: false),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Square or circular Spotify browse card with hover accent play button.
class MusicBrowseCard extends StatefulWidget {
  const MusicBrowseCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onOpen,
    required this.onPlay,
    this.onAddToQueue,
    this.openLabel = 'Open',
    this.extraMenuItems = const [],
    this.onExtraMenuSelected,
    this.artworkUri,
    this.circular = false,
    this.smartKind,
    this.isLikedCollection = false,
    this.isPlaylist = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onOpen;
  final VoidCallback? onPlay;
  final VoidCallback? onAddToQueue;
  final String openLabel;
  final List<PopupMenuEntry<String>> extraMenuItems;
  final ValueChanged<String>? onExtraMenuSelected;
  final Uri? artworkUri;
  final bool circular;
  final SmartPlaylistKind? smartKind;
  final bool isLikedCollection;
  final bool isPlaylist;

  @override
  State<MusicBrowseCard> createState() => _MusicBrowseCardState();
}

class _MusicBrowseCardState extends State<MusicBrowseCard> {
  bool _hovered = false;

  Future<void> _openContextMenu(Offset globalPosition) =>
      openMusicCollectionContextMenu(
        context,
        globalPosition,
        openLabel: widget.openLabel,
        onOpen: widget.onOpen,
        onPlay: widget.onPlay,
        onAddToQueue: widget.onAddToQueue,
        extraItems: widget.extraMenuItems,
        onExtraSelected: widget.onExtraMenuSelected,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onOpen,
          onSecondaryTapDown: (details) =>
              unawaited(_openContextMenu(details.globalPosition)),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? tokens.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: widget.circular
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artSize = constraints.biggest.shortestSide;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          MusicArtworkTile(
                            size: artSize,
                            title: widget.title,
                            uri: widget.artworkUri,
                            circular: widget.circular,
                            borderRadius: 6,
                            smartKind: widget.smartKind,
                            isLikedCollection: widget.isLikedCollection,
                            isPlaylist: widget.isPlaylist,
                          ),
                          if (widget.onPlay != null)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: ExcludeSemantics(
                                child: IgnorePointer(
                                  ignoring: !_hovered,
                                  child: AnimatedOpacity(
                                    alwaysIncludeSemantics: true,
                                    opacity: _hovered ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 160),
                                    child: AnimatedSlide(
                                      offset: _hovered
                                          ? Offset.zero
                                          : const Offset(0, 0.16),
                                      duration: const Duration(milliseconds: 160),
                                      child: HermesCircularPlayButton(
                                        size: 44,
                                        iconSize: 18,
                                        onPressed: widget.onPlay,
                                        tooltip: 'Play ${widget.title}',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.circular ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.circular ? TextAlign.center : TextAlign.left,
                style: TextStyle(fontSize: 12, color: tokens.text2),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
