part of 'music_world_screen.dart';

class _ShelfTitle extends StatelessWidget {
  const _ShelfTitle(this.text, this.tokens);

  final String text;
  final HermesThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.01,
        color: tokens.text,
      ),
    );
  }
}

class _MusicSidebar extends StatelessWidget {
  const _MusicSidebar({
    required this.currentRoute,
    required this.libraryFilter,
    required this.likedSongs,
    required this.playlists,
    required this.albums,
    required this.musicService,
    required this.coordinator,
    required this.onNavigate,
    required this.onPlaySongs,
    required this.onQueueSongs,
    required this.onPlayPlaylist,
    required this.onQueuePlaylist,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
    required this.albumSongsOf,
    required this.smartSongsOf,
    required this.onToggleFilter,
    required this.onCreatePlaylist,
  });

  final MusicPageRoute currentRoute;
  final _LibraryFilter? libraryFilter;
  final List<SongModel> likedSongs;
  final List<PlaylistSummaryModel> playlists;
  final List<AlbumSummaryModel> albums;
  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final ValueChanged<MusicPageRoute> onNavigate;
  final Future<void> Function(
    List<SongModel> songs, {
    int startIndex,
    String? sourceLabel,
    MusicPageRoute? sourceRoute,
  }) onPlaySongs;
  final void Function(List<SongModel> songs, String label) onQueueSongs;
  final Future<void> Function(PlaylistSummaryModel playlist) onPlayPlaylist;
  final Future<void> Function(PlaylistSummaryModel playlist) onQueuePlaylist;
  final Future<void> Function(PlaylistSummaryModel playlist) onRenamePlaylist;
  final Future<void> Function(PlaylistSummaryModel playlist) onDeletePlaylist;
  final List<SongModel> Function(String albumId) albumSongsOf;
  final List<SongModel> Function(SmartPlaylistKind kind) smartSongsOf;
  final ValueChanged<_LibraryFilter> onToggleFilter;
  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final playingSong = coordinator.currentSong;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _SidebarNavButton(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                selected: currentRoute.kind == MusicPageKind.home,
                onTap: () => onNavigate(const MusicPageRoute.home()),
              ),
              _SidebarNavButton(
                label: 'Albums',
                icon: Icons.album_outlined,
                selectedIcon: Icons.album_rounded,
                selected: currentRoute.kind == MusicPageKind.albums,
                onTap: () => onNavigate(const MusicPageRoute.albums()),
              ),
              _SidebarNavButton(
                label: 'Artists',
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                selected: currentRoute.kind == MusicPageKind.artists,
                onTap: () => onNavigate(const MusicPageRoute.artists()),
              ),
              _SidebarNavButton(
                label: 'Songs',
                icon: Icons.music_note_outlined,
                selectedIcon: Icons.music_note_rounded,
                selected: currentRoute.kind == MusicPageKind.songs,
                onTap: () => onNavigate(const MusicPageRoute.songs()),
              ),
              _SidebarNavButton(
                label: 'History',
                icon: Icons.history_rounded,
                selectedIcon: Icons.history_rounded,
                selected: currentRoute.kind == MusicPageKind.history,
                onTap: () => onNavigate(const MusicPageRoute.history()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 4, 10),
                  child: Row(
                    children: [
                      Icon(Icons.library_music_outlined, size: 18, color: tokens.text2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your Library',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tokens.text2,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'New playlist',
                        child: InkWell(
                          onTap: onCreatePlaylist,
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: Icon(Icons.add_rounded, size: 18, color: tokens.text2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 6, bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in _LibraryFilter.values) ...[
                          _LibraryFilterChip(
                            label: f.label,
                            active: libraryFilter == f,
                            onTap: () => onToggleFilter(f),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (libraryFilter != _LibraryFilter.albums) ...[
                        _LibraryRowButton(
                          title: 'Liked Songs',
                          subtitle: 'Playlist • ${likedSongs.length}',
                          active: currentRoute.kind == MusicPageKind.liked,
                          playing: coordinator.activeSourceRoute?.kind == MusicPageKind.liked,
                          isLiked: true,
                          onTap: () => onNavigate(const MusicPageRoute.liked()),
                          onSecondaryTapDown: (d) => unawaited(
                            openMusicCollectionContextMenu(
                              context,
                              d.globalPosition,
                              openLabel: 'Open Liked Songs',
                              onOpen: () => onNavigate(const MusicPageRoute.liked()),
                              onPlay: () => unawaited(
                                onPlaySongs(
                                  likedSongs,
                                  sourceLabel: 'Liked Songs',
                                  sourceRoute: const MusicPageRoute.liked(),
                                ),
                              ),
                              onAddToQueue: () => onQueueSongs(likedSongs, 'Liked Songs'),
                            ),
                          ),
                        ),
                        for (final pl in playlists)
                          _LibraryRowButton(
                            title: pl.name,
                            subtitle: 'Playlist • ${pl.trackCount}',
                            active: currentRoute.kind == MusicPageKind.playlist &&
                                currentRoute.targetId == pl.id,
                            playing: coordinator.activeSourceRoute == MusicPageRoute.playlist(pl.id),
                            isPlaylist: true,
                            onTap: () => onNavigate(MusicPageRoute.playlist(pl.id)),
                            onSecondaryTapDown: (d) => unawaited(
                              openMusicCollectionContextMenu(
                                context,
                                d.globalPosition,
                                openLabel: 'Open playlist',
                                onOpen: () => onNavigate(MusicPageRoute.playlist(pl.id)),
                                onPlay: () => unawaited(onPlayPlaylist(pl)),
                                onAddToQueue: () => unawaited(onQueuePlaylist(pl)),
                                extraItems: const [
                                  PopupMenuItem(value: 'rename', child: Text('Rename playlist')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                                ],
                                onExtraSelected: (action) {
                                  if (action == 'rename') {
                                    unawaited(onRenamePlaylist(pl));
                                  } else if (action == 'delete') {
                                    unawaited(onDeletePlaylist(pl));
                                  }
                                },
                              ),
                            ),
                          ),
                      ],
                      if (libraryFilter == null)
                        for (final smart in SmartPlaylistKind.values)
                          _LibraryRowButton(
                            title: smart.title,
                            subtitle: 'Smart playlist',
                            active: currentRoute.kind == MusicPageKind.smart &&
                                currentRoute.targetId == smart.id,
                            playing: coordinator.activeSourceRoute == MusicPageRoute.smart(smart.id),
                            smartKind: smart,
                            onTap: () => onNavigate(MusicPageRoute.smart(smart.id)),
                            onSecondaryTapDown: (d) {
                              final songs = smartSongsOf(smart);
                              unawaited(
                                openMusicCollectionContextMenu(
                                  context,
                                  d.globalPosition,
                                  openLabel: 'Open playlist',
                                  onOpen: () => onNavigate(MusicPageRoute.smart(smart.id)),
                                  onPlay: () => unawaited(
                                    onPlaySongs(
                                      songs,
                                      sourceLabel: smart.title,
                                      sourceRoute: MusicPageRoute.smart(smart.id),
                                    ),
                                  ),
                                  onAddToQueue: () => onQueueSongs(songs, smart.title),
                                ),
                              );
                            },
                          ),
                      if (libraryFilter != _LibraryFilter.playlists)
                        for (final alb in albums)
                          _LibraryRowButton(
                            title: alb.title,
                            subtitle: 'Album • ${alb.artistName}',
                            active: currentRoute.kind == MusicPageKind.album &&
                                currentRoute.targetId == alb.id,
                            playing: playingSong?.albumId == alb.id &&
                                coordinator.session?.state == PlaybackState.playing,
                            artworkUri: musicService.buildArtworkUri(alb.artworkHash),
                            onTap: () => onNavigate(MusicPageRoute.album(alb.id)),
                            onSecondaryTapDown: (d) {
                              final songs = albumSongsOf(alb.id);
                              unawaited(
                                openMusicCollectionContextMenu(
                                  context,
                                  d.globalPosition,
                                  openLabel: 'Open album',
                                  onOpen: () => onNavigate(MusicPageRoute.album(alb.id)),
                                  onPlay: () => unawaited(
                                    onPlaySongs(
                                      songs,
                                      sourceLabel: alb.title,
                                      sourceRoute: MusicPageRoute.album(alb.id),
                                    ),
                                  ),
                                  onAddToQueue: () => onQueueSongs(songs, alb.title),
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarNavButton extends StatelessWidget {
  const _SidebarNavButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final color = selected ? tokens.text : tokens.text2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(selected ? selectedIcon : icon, size: 20, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  const _LibraryFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? tokens.text : tokens.surface2,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? tokens.bg : tokens.text,
          ),
        ),
      ),
    );
  }
}

class _LibraryRowButton extends StatelessWidget {
  const _LibraryRowButton({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.playing,
    required this.onTap,
    this.onSecondaryTapDown,
    this.artworkUri,
    this.isLiked = false,
    this.isPlaylist = false,
    this.smartKind,
  });

  final String title;
  final String subtitle;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final Uri? artworkUri;
  final bool isLiked;
  final bool isPlaylist;
  final SmartPlaylistKind? smartKind;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? tokens.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            MusicArtworkTile(
              size: 44,
              title: title,
              uri: artworkUri,
              borderRadius: 4,
              isLikedCollection: isLiked,
              isPlaylist: isPlaylist,
              smartKind: smartKind,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: playing ? tokens.accent : tokens.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.text2),
                  ),
                ],
              ),
            ),
            if (playing) ...[
              const SizedBox(width: 6),
              HermesEqBars(color: tokens.accent, height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _MusicTopbar extends StatelessWidget {
  const _MusicTopbar({
    required this.canGoBack,
    required this.canGoForward,
    required this.scrolled,
    required this.tint,
    required this.controller,
    required this.focusNode,
    required this.hasQuery,
    required this.onBack,
    required this.onForward,
    required this.onQueryChanged,
    required this.onSubmitted,
    required this.onClearSearch,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool scrolled;
  final Color tint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasQuery;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final barBg = scrolled
        ? Color.lerp(tokens.surface, tint, 0.45)
        : Colors.transparent;

    return Container(
      color: barBg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          _TopbarNavCircleButton(
            key: const Key('music-topbar-back'),
            enabled: canGoBack,
            icon: Icons.chevron_left_rounded,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          _TopbarNavCircleButton(
            key: const Key('music-topbar-forward'),
            enabled: canGoForward,
            icon: Icons.chevron_right_rounded,
            tooltip: 'Forward',
            onTap: onForward,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextFieldTapRegion(
                  child: HermesSearchPill(
                    inputKey: const Key('music-search-input'),
                    clearKey: const Key('music-search-clear'),
                    controller: controller,
                    focusNode: focusNode,
                    hintText: 'Search your music',
                    hasQuery: hasQuery,
                    onChanged: onQueryChanged,
                    onSubmitted: onSubmitted,
                    onClear: onClearSearch,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopbarNavCircleButton extends StatelessWidget {
  const _TopbarNavCircleButton({
    super.key,
    required this.enabled,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Opacity(
        alwaysIncludeSemantics: true,
        opacity: enabled ? 1.0 : 0.38,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _MusicMobileNavBar extends StatelessWidget {
  const _MusicMobileNavBar({
    required this.currentKind,
    required this.onSelect,
  });

  final MusicPageKind currentKind;
  final ValueChanged<MusicPageRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    const tabs = [
      (MusicPageKind.home, 'Home', MusicPageRoute.home()),
      (MusicPageKind.albums, 'Albums', MusicPageRoute.albums()),
      (MusicPageKind.artists, 'Artists', MusicPageRoute.artists()),
      (MusicPageKind.songs, 'Songs', MusicPageRoute.songs()),
      (MusicPageKind.library, 'Library', MusicPageRoute.library()),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final (kind, label, route) in tabs) ...[
              InkWell(
                onTap: () => onSelect(route),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: currentKind == kind
                            ? tokens.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: currentKind == kind
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: currentKind == kind ? tokens.text : tokens.text2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeShortcutData {
  const _HomeShortcutData({
    required this.title,
    required this.tint,
    required this.onOpen,
    required this.onPlay,
    this.openLabel = 'Open',
    this.onAddToQueue,
    this.extraMenuItems = const [],
    this.onExtraMenuSelected,
    this.artworkUri,
    this.isLiked = false,
    this.isPlaylist = false,
  });

  final String title;
  final Color tint;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final String openLabel;
  final VoidCallback? onAddToQueue;
  final List<PopupMenuEntry<String>> extraMenuItems;
  final ValueChanged<String>? onExtraMenuSelected;
  final Uri? artworkUri;
  final bool isLiked;
  final bool isPlaylist;
}

class _HomeShortcutTile extends StatefulWidget {
  const _HomeShortcutTile({
    required this.data,
    required this.onHoverChanged,
  });

  final _HomeShortcutData data;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_HomeShortcutTile> createState() => _HomeShortcutTileState();
}

class _HomeShortcutTileState extends State<_HomeShortcutTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final data = widget.data;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          widget.onHoverChanged(true);
        },
        onExit: (_) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        },
        child: InkWell(
          onTap: data.onOpen,
          onSecondaryTapDown: (d) => unawaited(
            openMusicCollectionContextMenu(
              context,
              d.globalPosition,
              openLabel: data.openLabel,
              onOpen: data.onOpen,
              onPlay: data.onPlay,
              onAddToQueue: data.onAddToQueue,
              extraItems: data.extraMenuItems,
              onExtraSelected: data.onExtraMenuSelected,
            ),
          ),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  children: [
                    MusicArtworkTile(
                      size: 56,
                      title: data.title,
                      uri: data.artworkUri,
                      borderRadius: 0,
                      isLikedCollection: data.isLiked,
                      isPlaylist: data.isPlaylist,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: _hovered ? 52 : 10),
                        child: Text(
                          data.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tokens.text,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      ignoring: !_hovered,
                      child: AnimatedOpacity(
                        alwaysIncludeSemantics: true,
                        opacity: _hovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 120),
                        child: HermesCircularPlayButton(
                          size: 38,
                          iconSize: 15,
                          onPressed: data.onPlay,
                          tooltip: 'Play ${data.title}',
                        ),
                      ),
                    ),
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

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
  });

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return AlertDialog(
      backgroundColor: tokens.surface2,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _MusicMobileSubpageBar extends StatelessWidget {
  const _MusicMobileSubpageBar({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.lineSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('music-mobile-back-btn'),
            tooltip: 'Back',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded, size: 20, color: tokens.text),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
