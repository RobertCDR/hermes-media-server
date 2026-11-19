import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/storage/search_history_store.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_search_pill.dart';
import 'music_detail_views.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';
import 'music_shared_widgets.dart';

enum _LibraryFilter {
  playlists('Playlists'),
  albums('Albums');

  const _LibraryFilter(this.label);
  final String label;
}

/// Spotify-style Music world matching Figma v4 `.music-layout`: left library sidebar,
/// top color-wash surface with inline search, Home shortcuts, and dedicated inline Album,
/// Artist, Playlist, Liked Songs, and Smart playlist pages.
class MusicWorldScreen extends StatefulWidget {
  const MusicWorldScreen({
    super.key,
    required this.musicService,
    required this.coordinator,
    this.navigationController,
    this.searchHistoryStore,
    this.reduceMotion = false,
    this.externalMobileNav = false,
  });

  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;
  final MusicNavigationController? navigationController;
  final SearchHistoryStore? searchHistoryStore;
  final bool reduceMotion;
  final bool externalMobileNav;

  @override
  State<MusicWorldScreen> createState() => _MusicWorldScreenState();
}

class _MusicWorldScreenState extends State<MusicWorldScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<SongModel> _songs = [];
  List<AlbumSummaryModel> _albums = [];
  List<ArtistSummaryModel> _artists = [];
  List<PlaylistSummaryModel> _playlists = [];
  List<ListeningHistoryItemModel> _historyEntries = [];
  List<MusicSearchHistoryItem> _musicSearchHistory = const [];
  final Map<String, PlaylistDetailModel> _playlistDetails = {};

  final List<MusicPageRoute> _history = [const MusicPageRoute.home()];
  int _historyIdx = 0;

  _LibraryFilter? _libraryFilter;
  String _searchQuery = '';
  bool _searchFocused = false;
  Color? _hoverTint;
  bool _scrolled = false;
  bool _loading = true;
  String? _error;
  String? _lastActiveSongId;
  bool _lastIsPlaying = false;
  bool _lastShuffle = false;

  SearchHistoryStore get _searchHistoryStore =>
      widget.searchHistoryStore ?? SharedPrefsSearchHistoryStore();

  MusicPageRoute get _currentRoute => _history[_historyIdx];

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(_loadMusicSearchHistory());
    _lastActiveSongId = widget.coordinator.currentSong?.id;
    _lastIsPlaying =
        widget.coordinator.session?.state == PlaybackState.playing;
    _lastShuffle = widget.coordinator.session?.shuffle ?? false;
    if (widget.musicService.hasCachedCatalog) {
      _songs = List<SongModel>.from(widget.musicService.cachedSongs!);
      _albums =
          List<AlbumSummaryModel>.from(widget.musicService.cachedAlbums!);
      _artists =
          List<ArtistSummaryModel>.from(widget.musicService.cachedArtists!);
      _playlists = List<PlaylistSummaryModel>.from(
        widget.musicService.cachedPlaylists ?? const [],
      );
      _historyEntries = List<ListeningHistoryItemModel>.from(
        widget.musicService.cachedHistory ?? const [],
      );
      widget.coordinator.indexSongs(_songs);
      _loading = false;
    }
    widget.coordinator.addListener(_onCoordinatorChanged);
    _attachNavigationController(widget.navigationController);
    final pending = widget.navigationController?.takePendingRoute();
    if (pending != null && pending != _currentRoute) {
      _history.add(pending);
      _historyIdx = _history.length - 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _publishCurrentRoute();
      }
    });
    _scrollController.addListener(_onScroll);
    unawaited(_performLoad(silent: !_loading));
  }

  @override
  void didUpdateWidget(covariant MusicWorldScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != widget.coordinator) {
      oldWidget.coordinator.removeListener(_onCoordinatorChanged);
      widget.coordinator.addListener(_onCoordinatorChanged);
    }
    if (oldWidget.navigationController != widget.navigationController) {
      _detachNavigationController(oldWidget.navigationController);
      _attachNavigationController(widget.navigationController);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _publishCurrentRoute();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _detachNavigationController(widget.navigationController);
    widget.coordinator.removeListener(_onCoordinatorChanged);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    final next = _searchFocusNode.hasFocus;
    if (next != _searchFocused) {
      setState(() => _searchFocused = next);
    }
  }

  Future<void> _loadMusicSearchHistory() async {
    final loaded = await _searchHistoryStore.loadMusicHistory();
    if (!mounted) return;
    setState(() => _musicSearchHistory = loaded);
  }

  Future<void> _recordMusicSearchItem(MusicSearchHistoryItem item) async {
    final updated = await _searchHistoryStore.addMusicItem(item);
    if (!mounted) return;
    setState(() => _musicSearchHistory = updated);
  }

  Future<void> _removeMusicSearchItem(String id) async {
    final updated = await _searchHistoryStore.removeMusicItem(id);
    if (!mounted) return;
    setState(() => _musicSearchHistory = updated);
  }

  Future<void> _clearMusicSearchHistory() async {
    await _searchHistoryStore.clearMusicHistory();
    if (!mounted) return;
    setState(() => _musicSearchHistory = const []);
  }

  void _openMusicSearchHistoryItem(MusicSearchHistoryItem item) {
    final touched = MusicSearchHistoryItem(
      id: item.id,
      kind: item.kind,
      title: item.title,
      subtitle: item.subtitle,
      artworkHash: item.artworkHash,
      targetId: item.targetId,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    unawaited(_recordMusicSearchItem(touched));

    switch (item.kind) {
      case MusicSearchHistoryKind.song:
        final found = _songs.where((s) => s.id == item.targetId).firstOrNull;
        if (found != null) {
          _searchFocusNode.unfocus();
          unawaited(
            _playCollection(
              [found],
              startIndex: 0,
              sourceLabel: 'Search results',
            ),
          );
          return;
        }
      case MusicSearchHistoryKind.album:
        if (item.targetId != null && item.targetId!.isNotEmpty) {
          _searchFocusNode.unfocus();
          _navigate(MusicPageRoute.album(item.targetId!));
          return;
        }
      case MusicSearchHistoryKind.artist:
        if (item.targetId != null && item.targetId!.isNotEmpty) {
          _searchFocusNode.unfocus();
          _navigate(MusicPageRoute.artist(item.targetId!));
          return;
        }
      case MusicSearchHistoryKind.playlist:
        if (item.targetId != null && item.targetId!.isNotEmpty) {
          _searchFocusNode.unfocus();
          _navigate(MusicPageRoute.playlist(item.targetId!));
          return;
        }
      case MusicSearchHistoryKind.query:
        break;
    }

    _searchController.value = TextEditingValue(
      text: item.title,
      selection: TextSelection.collapsed(offset: item.title.length),
    );
    setState(() => _searchQuery = item.title.trim());
  }

  void _attachNavigationController(MusicNavigationController? controller) {
    if (controller == null) return;
    controller.onRequestRoute = _navigate;
    controller.onHandleBack = _handleBack;
  }

  void _detachNavigationController(MusicNavigationController? controller) {
    if (controller == null) return;
    if (controller.onRequestRoute == _navigate) {
      controller.onRequestRoute = null;
    }
    if (controller.onHandleBack == _handleBack) {
      controller.onHandleBack = null;
    }
  }

  void _publishCurrentRoute() {
    final controller = widget.navigationController;
    if (controller != null &&
        controller.currentRouteNotifier.value != _currentRoute) {
      controller.currentRouteNotifier.value = _currentRoute;
    }
  }

  bool _handleBack() {
    if (!mounted) return false;
    if (_searchQuery.isNotEmpty) {
      _searchController.clear();
      setState(() => _searchQuery = '');
      return true;
    }
    if (_historyIdx > 0) {
      _goBack();
      return true;
    }
    if (_currentRoute.kind != MusicPageKind.home) {
      setState(() {
        _hoverTint = null;
        _history
          ..clear()
          ..add(const MusicPageRoute.home());
        _historyIdx = 0;
      });
      _publishCurrentRoute();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      return true;
    }
    return false;
  }

  void _onCoordinatorChanged() {
    if (!mounted) return;
    final activeId = widget.coordinator.currentSong?.id;
    final isPlaying =
        widget.coordinator.session?.state == PlaybackState.playing;
    final shuffle = widget.coordinator.session?.shuffle ?? false;
    var songsChanged = activeId != _lastActiveSongId ||
        isPlaying != _lastIsPlaying ||
        shuffle != _lastShuffle;

    for (var i = 0; i < _songs.length; i++) {
      final updated = widget.coordinator.songById(_songs[i].id);
      if (updated != null && updated.isLiked != _songs[i].isLiked) {
        _songs[i] = updated;
        songsChanged = true;
      }
    }

    _lastActiveSongId = activeId;
    _lastIsPlaying = isPlaying;
    _lastShuffle = shuffle;
    if (songsChanged) {
      setState(() {});
    }
  }

  void _onScroll() {
    final scrolled = _scrollController.hasClients && _scrollController.offset > 16;
    if (scrolled != _scrolled) {
      setState(() => _scrolled = scrolled);
    }
  }

  Future<List<T>> _safeOptionalList<T>(Future<List<T>> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return <T>[];
    }
  }

  Future<void> _load() => _performLoad(silent: false);

  Future<void> _performLoad({required bool silent}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.musicService.listSongs(),
        widget.musicService.listAlbums(),
        widget.musicService.listArtists(),
        widget.musicService.listPlaylists(),
        _safeOptionalList(widget.musicService.listHistory),
      ]);
      if (!mounted) return;

      final songs = results[0] as List<SongModel>;
      final albums = results[1] as List<AlbumSummaryModel>;
      final artists = results[2] as List<ArtistSummaryModel>;
      final playlists = results[3] as List<PlaylistSummaryModel>;
      final historyEntries = results[4] as List<ListeningHistoryItemModel>;

      widget.coordinator.indexSongs(songs);
      setState(() {
        _songs = songs;
        _albums = albums;
        _artists = artists;
        _playlists = playlists;
        _historyEntries = historyEntries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _songs.isEmpty) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshHistory() async {
    final historyEntries = await _safeOptionalList(widget.musicService.listHistory);
    if (!mounted) return;
    setState(() => _historyEntries = historyEntries);
  }

  void _navigate(MusicPageRoute route) {
    setState(() {
      _hoverTint = null;
      _searchQuery = '';
      _searchController.clear();
      if (_currentRoute != route) {
        if (_historyIdx < _history.length - 1) {
          _history.removeRange(_historyIdx + 1, _history.length);
        }
        _history.add(route);
        _historyIdx = _history.length - 1;
      }
    });
    _publishCurrentRoute();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (route.kind == MusicPageKind.playlist && route.targetId != null) {
      unawaited(_ensurePlaylistLoaded(route.targetId!));
    } else if (route.kind == MusicPageKind.history) {
      unawaited(_refreshHistory());
    }
  }

  void _goBack() {
    if (_historyIdx <= 0) return;
    setState(() {
      _hoverTint = null;
      _historyIdx--;
    });
    _publishCurrentRoute();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _ensurePlaylistLoaded(String playlistId) async {
    try {
      final detail = await widget.musicService.getPlaylist(playlistId);
      widget.coordinator.indexSongs(detail.tracks.map((t) => t.song).toList());
      if (mounted) {
        setState(() => _playlistDetails[playlistId] = detail);
      }
    } catch (_) {
      // Keep cached detail or summary fallback cleanly if offline.
    }
  }

  List<SongModel> _albumSongs(String albumId) {
    final tracks = _songs.where((s) => s.albumId == albumId).toList()
      ..sort((a, b) {
        final discCmp = a.discNumber.compareTo(b.discNumber);
        if (discCmp != 0) return discCmp;
        final trackCmp = a.trackNumber.compareTo(b.trackNumber);
        return trackCmp != 0 ? trackCmp : a.title.compareTo(b.title);
      });
    return tracks;
  }

  List<SongModel> _artistSongs(String artistId) {
    final tracks = _songs
        .where(
          (s) =>
              s.artistId == artistId ||
              s.artistCredits.any((c) => c.artistId == artistId),
        )
        .toList()
      ..sort((a, b) {
        final likedCmp = (b.isLiked ? 1 : 0).compareTo(a.isLiked ? 1 : 0);
        return likedCmp != 0 ? likedCmp : a.title.compareTo(b.title);
      });
    return tracks;
  }

  List<SongModel> _likedSongs() {
    return _songs
        .where((s) => widget.coordinator.songById(s.id)?.isLiked ?? s.isLiked)
        .toList();
  }

  List<SongModel> _smartSongs(SmartPlaylistKind kind) {
    final list = List<SongModel>.from(_songs);
    switch (kind) {
      case SmartPlaylistKind.recentlyAdded:
        list.sort((a, b) {
          final da = a.fileLastWriteUtc;
          final db = b.fileLastWriteUtc;
          if (da != null && db != null) {
            return db.compareTo(da);
          }
          if (db != null) return 1;
          if (da != null) return -1;
          return a.title.compareTo(b.title);
        });
        return list.take(40).toList();
      case SmartPlaylistKind.losslessMasters:
        return list
            .where((s) => const {'flac', 'alac', 'wav', 'aiff'}.contains(s.codec.toLowerCase()))
            .toList();
      case SmartPlaylistKind.freshMix:
        list.sort((a, b) => a.title.compareTo(b.title));
        return list.take(30).toList();
    }
  }

  Future<void> _playCollection(
    List<SongModel> songs, {
    int startIndex = 0,
    String? sourceLabel,
    MusicPageRoute? sourceRoute,
  }) async {
    if (songs.isEmpty) return;
    try {
      await widget.coordinator.startQueue(
        songs,
        startIndex,
        sourceLabel: sourceLabel,
        sourceRoute: sourceRoute,
      );
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not start playback: $e');
      }
    }
  }

  void _queueCollection(List<SongModel> songs, String label) {
    if (songs.isEmpty) return;
    widget.coordinator.addAllToQueue(songs);
    if (mounted) {
      showMusicToast(context, 'Added "$label" (${songs.length}) to queue');
    }
  }

  Future<List<SongModel>> _loadPlaylistSongs(PlaylistSummaryModel pl) async {
    final cached = _playlistDetails[pl.id];
    if (cached != null) {
      return cached.tracks.map((t) => t.song).toList();
    }
    final detail = await widget.musicService.getPlaylist(pl.id);
    if (mounted) {
      _playlistDetails[pl.id] = detail;
    }
    return detail.tracks.map((t) => t.song).toList();
  }

  Future<void> _playPlaylist(PlaylistSummaryModel pl) async {
    try {
      final songs = await _loadPlaylistSongs(pl);
      if (!mounted) return;
      await _playCollection(
        songs,
        sourceLabel: pl.name,
        sourceRoute: MusicPageRoute.playlist(pl.id),
      );
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not play playlist: $e');
      }
    }
  }

  Future<void> _queuePlaylist(PlaylistSummaryModel pl) async {
    try {
      final songs = await _loadPlaylistSongs(pl);
      if (!mounted) return;
      _queueCollection(songs, pl.name);
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not queue playlist: $e');
      }
    }
  }

  Future<void> _toggleLike(SongModel song) async {
    try {
      final liked = await widget.coordinator.toggleLikeSong(song.id);
      if (!mounted) return;
      setState(() {
        _songs = _songs
            .map((s) => s.id == song.id ? s.copyWith(isLiked: liked) : s)
            .toList();
      });
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not update Liked Songs: $e');
      }
    }
  }

  Future<void> _promptCreatePlaylist() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PlaylistNameDialog(
        title: 'New playlist',
        confirmLabel: 'Create',
      ),
    );
    if (name == null || name.isEmpty) return;

    try {
      final created = await widget.musicService.createPlaylist(name: name);
      if (!mounted) return;
      final summary = PlaylistSummaryModel(
        id: created.id,
        name: created.name,
        description: created.description,
        trackCount: created.tracks.length,
        createdAtUtc: DateTime.now().toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      );
      setState(() {
        _playlists = [summary, ..._playlists];
        _playlistDetails[created.id] = created;
      });
      _navigate(MusicPageRoute.playlist(created.id));
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not create playlist: $e');
      }
    }
  }

  Future<void> _promptRenamePlaylist(PlaylistSummaryModel playlist) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(
        title: 'Rename playlist',
        confirmLabel: 'Save',
        initialName: playlist.name,
      ),
    );
    if (name == null || name.isEmpty || name == playlist.name) return;

    try {
      final updated = await widget.musicService.renamePlaylist(
        playlistId: playlist.id,
        name: name,
      );
      if (!mounted) return;
      setState(() {
        _playlistDetails[playlist.id] = updated;
        _playlists = _playlists
            .map(
              (p) => p.id == playlist.id
                  ? PlaylistSummaryModel(
                      id: p.id,
                      name: updated.name,
                      description: updated.description,
                      trackCount: updated.tracks.length,
                      createdAtUtc: p.createdAtUtc,
                      updatedAtUtc: DateTime.now().toUtc(),
                    )
                  : p,
            )
            .toList();
      });
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Rename failed: $e');
      }
    }
  }

  Future<void> _deletePlaylist(PlaylistSummaryModel playlist) async {
    try {
      await widget.musicService.deletePlaylist(playlist.id);
      if (!mounted) return;
      setState(() {
        _playlists = _playlists.where((p) => p.id != playlist.id).toList();
        _playlistDetails.remove(playlist.id);
      });
      _navigate(const MusicPageRoute.home());
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Delete failed: $e');
      }
    }
  }

  Future<void> _addToPlaylist(String playlistId, SongModel song) async {
    try {
      final updated = await widget.musicService.addTrackToPlaylist(
        playlistId: playlistId,
        songId: song.id,
      );
      if (!mounted) return;
      setState(() {
        _playlistDetails[playlistId] = updated;
        _playlists = _playlists
            .map(
              (p) => p.id == playlistId
                  ? PlaylistSummaryModel(
                      id: p.id,
                      name: updated.name,
                      description: updated.description,
                      trackCount: updated.tracks.length,
                      createdAtUtc: p.createdAtUtc,
                      updatedAtUtc: DateTime.now().toUtc(),
                    )
                  : p,
            )
            .toList();
      });
      showMusicToast(context, 'Added "${song.title}" to ${updated.name}');
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not add track: $e');
      }
    }
  }

  Future<void> _removeFromPlaylist(String playlistId, int position) async {
    try {
      final updated = await widget.musicService.removePlaylistTrack(
        playlistId: playlistId,
        position: position,
      );
      if (!mounted) return;
      setState(() {
        _playlistDetails[playlistId] = updated;
        _playlists = _playlists
            .map(
              (p) => p.id == playlistId
                  ? PlaylistSummaryModel(
                      id: p.id,
                      name: updated.name,
                      description: updated.description,
                      trackCount: updated.tracks.length,
                      createdAtUtc: p.createdAtUtc,
                      updatedAtUtc: DateTime.now().toUtc(),
                    )
                  : p,
            )
            .toList();
      });
    } catch (e) {
      if (mounted) {
        showMusicToast(context, 'Could not remove track: $e');
      }
    }
  }

  Color _routeTint(HermesThemeTokens tokens) {
    if (_hoverTint != null) return _hoverTint!;
    final r = _currentRoute;
    switch (r.kind) {
      case MusicPageKind.home:
        if (_albums.isNotEmpty) {
          return deriveMusicTint(_albums.first.title, fallback: tokens.surface3);
        }
        return tokens.surface3;
      case MusicPageKind.liked:
        return tokens.accent;
      case MusicPageKind.album:
        final alb = _albums.where((a) => a.id == r.targetId).firstOrNull;
        return alb == null
            ? tokens.surface3
            : deriveMusicTint(alb.title, fallback: tokens.surface3);
      case MusicPageKind.artist:
        final art = _artists.where((a) => a.id == r.targetId).firstOrNull;
        return art == null
            ? tokens.surface3
            : deriveMusicTint(art.name, fallback: tokens.surface3);
      case MusicPageKind.playlist:
        final pl = _playlists.where((p) => p.id == r.targetId).firstOrNull;
        return pl == null
            ? tokens.accent
            : deriveMusicTint(pl.name, fallback: tokens.accent);
      case MusicPageKind.smart:
        return tokens.accent;
      default:
        return tokens.surface3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    if (_loading) {
      return Container(
        color: tokens.bgSunken,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Container(
        color: tokens.bgSunken,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Music library failed to load: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final tint = _routeTint(tokens);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final useExternalMobile = !wide && widget.externalMobileNav;
        final isMobileMainTab = useExternalMobile &&
            (_currentRoute.kind == MusicPageKind.home ||
                _currentRoute.kind == MusicPageKind.search ||
                _currentRoute.kind == MusicPageKind.library);

        final mainSurface = Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(wide ? 8 : 0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 300,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tint.withValues(alpha: 0.42),
                          tint.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  if (!useExternalMobile) ...[
                    _MusicTopbar(
                      canGoBack: _historyIdx > 0,
                      scrolled: _scrolled,
                      tint: tint,
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hasQuery: _searchQuery.isNotEmpty,
                      onBack: _goBack,
                      onQueryChanged: (val) =>
                          setState(() => _searchQuery = val.trim()),
                      onSubmitted: _submitMusicSearchQuery,
                      onClearSearch: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                    if (!wide)
                      _MusicMobileNavBar(
                        currentKind: _currentRoute.kind,
                        onSelect: _navigate,
                      ),
                  ] else if (!isMobileMainTab)
                    _MusicMobileSubpageBar(
                      title: _routeTitle(_currentRoute),
                      onBack: () {
                        if (!_handleBack()) {
                          _navigate(const MusicPageRoute.home());
                        }
                      },
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        controller: _scrollController,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(650),
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 24 : 16,
                              12,
                              wide ? 24 : 16,
                              40,
                            ),
                            sliver: SliverMainAxisGroup(
                              slivers: _buildMainSlivers(
                                context,
                                tokens,
                                contentWidth:
                                    ((wide
                                                ? constraints.maxWidth - 272
                                                : constraints.maxWidth) -
                                            (wide ? 48 : 32))
                                        .clamp(240.0, 2000.0),
                                useExternalMobile: useExternalMobile,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (!useExternalMobile &&
                  _searchFocused &&
                  _searchQuery.isEmpty &&
                  _musicSearchHistory.isNotEmpty)
                Positioned(
                  top: 62,
                  left: 60,
                  width: math.min(
                    420.0,
                    math.max(
                      240.0,
                      (wide ? constraints.maxWidth - 272 : constraints.maxWidth) - 76,
                    ),
                  ),
                  child: TextFieldTapRegion(
                    child: _buildMusicSearchHistoryCard(tokens, isDropdown: true),
                  ),
                ),
            ],
          ),
        );

        if (!wide) {
          return Container(color: tokens.bgSunken, child: mainSurface);
        }

        return Container(
          color: tokens.bgSunken,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 248,
                child: _MusicSidebar(
                  currentRoute: _currentRoute,
                  libraryFilter: _libraryFilter,
                  likedSongs: _likedSongs(),
                  playlists: _playlists,
                  albums: _albums,
                  musicService: widget.musicService,
                  coordinator: widget.coordinator,
                  onNavigate: _navigate,
                  onPlaySongs: _playCollection,
                  onQueueSongs: _queueCollection,
                  onPlayPlaylist: _playPlaylist,
                  onQueuePlaylist: _queuePlaylist,
                  onRenamePlaylist: _promptRenamePlaylist,
                  onDeletePlaylist: _deletePlaylist,
                  albumSongsOf: _albumSongs,
                  smartSongsOf: _smartSongs,
                  onToggleFilter: (f) => setState(
                    () => _libraryFilter = _libraryFilter == f ? null : f,
                  ),
                  onCreatePlaylist: _promptCreatePlaylist,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: mainSurface),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildMainSlivers(
    BuildContext context,
    HermesThemeTokens tokens, {
    required double contentWidth,
    required bool useExternalMobile,
  }) {
    if (useExternalMobile && _currentRoute.kind == MusicPageKind.search) {
      return _buildMobileSearchViewSlivers(context, tokens, contentWidth);
    }
    if (_searchQuery.isNotEmpty) {
      return _buildSearchResultsSlivers(context, tokens, contentWidth);
    }
    return _buildRouteSlivers(context, tokens, contentWidth);
  }

  List<Widget> _buildSearchResultsSlivers(
    BuildContext context,
    HermesThemeTokens tokens,
    double contentWidth,
  ) {
    final q = _searchQuery.toLowerCase();
    final songs = _songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artistName.toLowerCase().contains(q) ||
              s.albumTitle.toLowerCase().contains(q),
        )
        .toList();
    final albums = _albums
        .where(
          (a) =>
              a.title.toLowerCase().contains(q) ||
              a.artistName.toLowerCase().contains(q),
        )
        .toList();
    final artists = _artists
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
    final playlists = _playlists
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();

    if (songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Center(
              child: Column(
                children: [
                  Text(
                    'No results for "$_searchQuery"',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try a song title, artist, album or playlist name.',
                    style: TextStyle(fontSize: 14, color: tokens.text2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      if (songs.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ShelfTitle('Songs', tokens),
          ),
        ),
        ...buildMusicTrackTableSlivers(
          context: context,
          contentWidth: contentWidth,
          songs: songs,
          musicService: widget.musicService,
          coordinator: widget.coordinator,
          playlists: _playlists,
          onPlayTrackAt: (idx) {
            final tapped = songs[idx];
            unawaited(
              _recordMusicSearchItem(
                MusicSearchHistoryItem(
                  id: 'song:${tapped.id}',
                  kind: MusicSearchHistoryKind.song,
                  title: tapped.title,
                  subtitle: 'Song • ${tapped.artistName}',
                  artworkHash: tapped.artworkHash,
                  targetId: tapped.id,
                  timestampMs: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
            );
            unawaited(
              _playCollection(
                songs,
                startIndex: idx,
                sourceLabel: 'Search results',
              ),
            );
          },
          onToggleLike: _toggleLike,
          onAddToPlaylist: _addToPlaylist,
          onNavigate: _navigate,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (albums.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShelfTitle('Albums', tokens),
          ),
        ),
        _buildAlbumSliverGrid(
          albums,
          onOpened: (alb) => unawaited(
            _recordMusicSearchItem(
              MusicSearchHistoryItem(
                id: 'album:${alb.id}',
                kind: MusicSearchHistoryKind.album,
                title: alb.title,
                subtitle: 'Album • ${alb.artistName}',
                artworkHash: alb.artworkHash,
                targetId: alb.id,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (artists.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShelfTitle('Artists', tokens),
          ),
        ),
        _buildArtistSliverGrid(
          artists,
          onOpened: (art) => unawaited(
            _recordMusicSearchItem(
              MusicSearchHistoryItem(
                id: 'artist:${art.id}',
                kind: MusicSearchHistoryKind.artist,
                title: art.name,
                subtitle: 'Artist',
                artworkHash: art.artworkHash,
                targetId: art.id,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (playlists.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShelfTitle('Playlists', tokens),
          ),
        ),
        _buildPlaylistSliverGrid(
          playlists,
          onOpened: (pl) => unawaited(
            _recordMusicSearchItem(
              MusicSearchHistoryItem(
                id: 'playlist:${pl.id}',
                kind: MusicSearchHistoryKind.playlist,
                title: pl.name,
                subtitle: 'Playlist • ${pl.trackCount} songs',
                targetId: pl.id,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildRouteSlivers(
    BuildContext context,
    HermesThemeTokens tokens,
    double contentWidth,
  ) {
    final route = _currentRoute;
    switch (route.kind) {
      case MusicPageKind.home:
        return _buildHomeSlivers(context, tokens, contentWidth);
      case MusicPageKind.search:
        return _buildHomeSlivers(context, tokens, contentWidth);
      case MusicPageKind.albums:
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ShelfTitle('Albums', tokens),
            ),
          ),
          _buildAlbumSliverGrid(_albums),
        ];
      case MusicPageKind.artists:
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ShelfTitle('Artists', tokens),
            ),
          ),
          _buildArtistSliverGrid(_artists),
        ];
      case MusicPageKind.songs:
        return [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShelfTitle('Songs', tokens),
                const SizedBox(height: 4),
                Text(
                  '${_songs.length} ${_songs.length == 1 ? 'track' : 'tracks'} in your library',
                  style: TextStyle(fontSize: 13, color: tokens.text2),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          ...buildMusicTrackTableSlivers(
            context: context,
            contentWidth: contentWidth,
            songs: _songs,
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            onPlayTrackAt: (idx) => _playCollection(
              _songs,
              startIndex: idx,
              sourceLabel: 'All songs',
              sourceRoute: const MusicPageRoute.songs(),
            ),
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
          ),
        ];
      case MusicPageKind.library:
        return _buildMobileLibraryViewSlivers(context, tokens);
      case MusicPageKind.liked:
        return [
          MusicCollectionPage(
            kindLabel: 'Playlist',
            title: 'Liked Songs',
            description: 'Songs you saved',
            songs: _likedSongs(),
            route: const MusicPageRoute.liked(),
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            isLikedCollection: true,
            onPlayCollection: _playCollection,
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
      case MusicPageKind.history:
        final historySongs = _historyEntries.map((h) => h.song).toList();
        return [
          MusicCollectionPage(
            kindLabel: 'Listening history',
            title: 'Recently played',
            description: historySongs.isEmpty
                ? 'Tracks you listen to will appear here'
                : 'Your latest played tracks across Hermes devices',
            songs: historySongs,
            route: const MusicPageRoute.history(),
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            onPlayCollection: _playCollection,
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
      case MusicPageKind.smart:
        final kind = SmartPlaylistKind.values.firstWhere(
          (k) => k.id == route.targetId,
          orElse: () => SmartPlaylistKind.recentlyAdded,
        );
        return [
          MusicCollectionPage(
            kindLabel: 'Smart playlist',
            title: kind.title,
            description: kind.description,
            songs: _smartSongs(kind),
            route: MusicPageRoute.smart(kind.id),
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            smartKind: kind,
            onPlayCollection: _playCollection,
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
      case MusicPageKind.album:
        final album = _albums.where((a) => a.id == route.targetId).firstOrNull;
        if (album == null) {
          return _buildHomeSlivers(context, tokens, contentWidth);
        }
        final songs = _albumSongs(album.id);
        final more = _albums
            .where((a) => a.artistId == album.artistId && a.id != album.id)
            .toList();
        return [
          MusicAlbumPage(
            album: album,
            songs: songs,
            moreByArtist: more,
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            onPlayCollection: _playCollection,
            onPlayAlbum: (alb) => _playCollection(
              _albumSongs(alb.id),
              sourceLabel: alb.title,
              sourceRoute: MusicPageRoute.album(alb.id),
            ),
            onQueueAlbum: (alb) => _queueCollection(_albumSongs(alb.id), alb.title),
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
      case MusicPageKind.artist:
        final artist = _artists.where((a) => a.id == route.targetId).firstOrNull;
        if (artist == null) {
          return _buildHomeSlivers(context, tokens, contentWidth);
        }
        final songs = _artistSongs(artist.id);
        final featuredAlbumIds = songs.map((s) => s.albumId).toSet();
        final albums = _albums
            .where((a) => a.artistId == artist.id || featuredAlbumIds.contains(a.id))
            .toList();
        return [
          MusicArtistPage(
            artist: artist,
            albums: albums,
            songs: songs,
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            onPlayCollection: _playCollection,
            onPlayAlbum: (alb) => _playCollection(
              _albumSongs(alb.id),
              sourceLabel: alb.title,
              sourceRoute: MusicPageRoute.album(alb.id),
            ),
            onQueueAlbum: (alb) => _queueCollection(_albumSongs(alb.id), alb.title),
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
      case MusicPageKind.playlist:
        final pl = _playlists.where((p) => p.id == route.targetId).firstOrNull;
        if (pl == null) {
          return _buildHomeSlivers(context, tokens, contentWidth);
        }
        final detail = _playlistDetails[pl.id];
        final plSongs = detail?.tracks.map((t) => t.song).toList() ?? const <SongModel>[];
        return [
          MusicCollectionPage(
            kindLabel: 'Playlist',
            title: detail?.name ?? pl.name,
            description: detail?.description ?? pl.description ?? '',
            songs: plSongs,
            route: MusicPageRoute.playlist(pl.id),
            playlistId: pl.id,
            coverArtworkHash: plSongs.isNotEmpty ? plSongs.first.artworkHash : null,
            musicService: widget.musicService,
            coordinator: widget.coordinator,
            playlists: _playlists,
            onPlayCollection: _playCollection,
            onToggleLike: _toggleLike,
            onAddToPlaylist: _addToPlaylist,
            onRenamePlaylist: () => unawaited(_promptRenamePlaylist(pl)),
            onDeletePlaylist: () => unawaited(_deletePlaylist(pl)),
            onRemoveFromPlaylist: _removeFromPlaylist,
            onNavigate: _navigate,
            asSliver: true,
            sliverContentWidth: contentWidth,
          ),
        ];
    }
  }

  List<Widget> _buildHomeSlivers(
    BuildContext context,
    HermesThemeTokens tokens,
    double contentWidth,
  ) {
    final likedSongs = _likedSongs();
    final shortcuts = <_HomeShortcutData>[
      _HomeShortcutData(
        title: 'Liked Songs',
        tint: tokens.accent,
        isLiked: true,
        openLabel: 'Open Liked Songs',
        onOpen: () => _navigate(const MusicPageRoute.liked()),
        onPlay: () => _playCollection(
          likedSongs,
          sourceLabel: 'Liked Songs',
          sourceRoute: const MusicPageRoute.liked(),
        ),
        onAddToQueue: () => _queueCollection(likedSongs, 'Liked Songs'),
      ),
      for (final pl in _playlists.take(4))
        _HomeShortcutData(
          title: pl.name,
          tint: deriveMusicTint(pl.name, fallback: tokens.surface3),
          isPlaylist: true,
          openLabel: 'Open playlist',
          onOpen: () => _navigate(MusicPageRoute.playlist(pl.id)),
          onPlay: () => unawaited(_playPlaylist(pl)),
          onAddToQueue: () => unawaited(_queuePlaylist(pl)),
          extraMenuItems: const [
            PopupMenuItem(value: 'rename', child: Text('Rename playlist')),
            PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
          ],
          onExtraMenuSelected: (action) {
            if (action == 'rename') {
              unawaited(_promptRenamePlaylist(pl));
            } else if (action == 'delete') {
              unawaited(_deletePlaylist(pl));
            }
          },
        ),
      for (final alb in _albums.take(6))
        _HomeShortcutData(
          title: alb.title,
          tint: deriveMusicTint(alb.title, fallback: tokens.surface3),
          artworkUri: widget.musicService.buildArtworkUri(alb.artworkHash),
          openLabel: 'Open album',
          onOpen: () => _navigate(MusicPageRoute.album(alb.id)),
          onPlay: () => _playCollection(
            _albumSongs(alb.id),
            sourceLabel: alb.title,
            sourceRoute: MusicPageRoute.album(alb.id),
          ),
          onAddToQueue: () => _queueCollection(_albumSongs(alb.id), alb.title),
        ),
    ].take(8).toList();

    final shortcutCols = contentWidth >= 920
        ? 4
        : contentWidth >= 600
            ? 3
            : contentWidth >= 340
                ? 2
                : 1;

    return [
      if (shortcuts.isNotEmpty) ...[
        SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: shortcutCols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 56,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => RepaintBoundary(
              child: _HomeShortcutTile(
                data: shortcuts[index],
                onHoverChanged: (hovering) => setState(
                  () => _hoverTint = hovering ? shortcuts[index].tint : null,
                ),
              ),
            ),
            childCount: shortcuts.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (_historyEntries.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ShelfTitle('Recently played', tokens),
                TextButton(
                  onPressed: () => _navigate(const MusicPageRoute.history()),
                  child: Text(
                    'See all',
                    style: TextStyle(fontSize: 13, color: tokens.text2),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...buildMusicTrackTableSlivers(
          context: context,
          contentWidth: contentWidth,
          songs: _historyEntries.take(8).map((e) => e.song).toList(),
          musicService: widget.musicService,
          coordinator: widget.coordinator,
          playlists: _playlists,
          onPlayTrackAt: (idx) => _playCollection(
            _historyEntries.map((e) => e.song).toList(),
            startIndex: idx,
            sourceLabel: 'Recently played',
            sourceRoute: const MusicPageRoute.history(),
          ),
          onToggleLike: _toggleLike,
          onAddToPlaylist: _addToPlaylist,
          onNavigate: _navigate,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (_albums.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShelfTitle('Recently added', tokens),
          ),
        ),
        _buildAlbumSliverGrid(_albums.take(12).toList()),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ShelfTitle('Made from your library', tokens),
        ),
      ),
      _buildSmartSliverGrid(),
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
      if (_artists.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ShelfTitle('Your artists', tokens),
          ),
        ),
        _buildArtistSliverGrid(_artists),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      if (_songs.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ShelfTitle('Songs', tokens),
          ),
        ),
        ...buildMusicTrackTableSlivers(
          context: context,
          contentWidth: contentWidth,
          songs: _songs.take(15).toList(),
          musicService: widget.musicService,
          coordinator: widget.coordinator,
          playlists: _playlists,
          onPlayTrackAt: (idx) => _playCollection(
            _songs,
            startIndex: idx,
            sourceLabel: 'Library songs',
            sourceRoute: const MusicPageRoute.songs(),
          ),
          onToggleLike: _toggleLike,
          onAddToPlaylist: _addToPlaylist,
          onNavigate: _navigate,
        ),
      ],
    ];
  }

  String _routeTitle(MusicPageRoute route) => switch (route.kind) {
        MusicPageKind.home => 'Home',
        MusicPageKind.search => 'Search',
        MusicPageKind.albums => 'Albums',
        MusicPageKind.artists => 'Artists',
        MusicPageKind.songs => 'Songs',
        MusicPageKind.library => 'Your Library',
        MusicPageKind.liked => 'Liked Songs',
        MusicPageKind.history => 'Recently played',
        MusicPageKind.smart => SmartPlaylistKind.values
            .firstWhere(
              (k) => k.id == route.targetId,
              orElse: () => SmartPlaylistKind.recentlyAdded,
            )
            .title,
        MusicPageKind.album => _albums
                .where((a) => a.id == route.targetId)
                .firstOrNull
                ?.title ??
            'Album',
        MusicPageKind.artist => _artists
                .where((a) => a.id == route.targetId)
                .firstOrNull
                ?.name ??
            'Artist',
        MusicPageKind.playlist => _playlists
                .where((p) => p.id == route.targetId)
                .firstOrNull
                ?.name ??
            'Playlist',
      };

  void _submitMusicSearchQuery(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return;
    unawaited(
      _recordMusicSearchItem(
        MusicSearchHistoryItem(
          id: 'query:${clean.toLowerCase()}',
          kind: MusicSearchHistoryKind.query,
          title: clean,
          subtitle: 'Search',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Widget _buildMusicSearchHistoryCard(
    HermesThemeTokens tokens, {
    required bool isDropdown,
  }) {
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isDropdown ? 14 : 0, isDropdown ? 10 : 0, isDropdown ? 8 : 0, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
              ),
              TextButton(
                key: const Key('music-clear-search-history'),
                onPressed: () => unawaited(_clearMusicSearchHistory()),
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
        for (final item in _musicSearchHistory)
          InkWell(
            onTap: () => _openMusicSearchHistoryItem(item),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDropdown ? 12 : 4,
                vertical: 6,
              ),
              child: Row(
                children: [
                  if (item.kind == MusicSearchHistoryKind.query)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tokens.surface3,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: tokens.text2,
                      ),
                    )
                  else
                    MusicArtworkTile(
                      size: 44,
                      title: item.title,
                      uri: widget.musicService.buildArtworkUri(item.artworkHash),
                      circular: item.kind == MusicSearchHistoryKind.artist,
                      isPlaylist: item.kind == MusicSearchHistoryKind.playlist,
                      borderRadius: 4,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove from recent searches',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_removeMusicSearchItem(item.id)),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: tokens.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (!isDropdown) {
      return Container(
        key: const Key('music-recent-searches'),
        child: list,
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('music-recent-searches'),
        constraints: const BoxConstraints(maxHeight: 360),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(child: list),
      ),
    );
  }

  List<Widget> _buildMobileSearchViewSlivers(
    BuildContext context,
    HermesThemeTokens tokens,
    double contentWidth,
  ) {
    return [
      SliverToBoxAdapter(
        child: Column(
          key: const Key('music-mobile-search-view'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShelfTitle('Search', tokens),
            const SizedBox(height: 12),
            HermesSearchPill(
              inputKey: const Key('music-search-input'),
              clearKey: const Key('music-search-clear'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'Songs, artists, albums, playlists...',
              hasQuery: _searchQuery.isNotEmpty,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              onSubmitted: _submitMusicSearchQuery,
              onClear: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      if (_searchQuery.isNotEmpty)
        ..._buildSearchResultsSlivers(context, tokens, contentWidth)
      else
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_musicSearchHistory.isNotEmpty) ...[
                _buildMusicSearchHistoryCard(tokens, isDropdown: false),
                const SizedBox(height: 22),
              ],
              Text(
                'Browse your music',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ActionChip(
                    avatar: Icon(Icons.favorite_rounded, size: 16, color: tokens.accent),
                    label: const Text('Liked Songs'),
                    onPressed: () => _navigate(const MusicPageRoute.liked()),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.music_note_rounded, size: 16, color: tokens.text2),
                    label: const Text('Songs'),
                    onPressed: () => _navigate(const MusicPageRoute.songs()),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.album_rounded, size: 16, color: tokens.text2),
                    label: const Text('Albums'),
                    onPressed: () => _navigate(const MusicPageRoute.albums()),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.person_rounded, size: 16, color: tokens.text2),
                    label: const Text('Artists'),
                    onPressed: () => _navigate(const MusicPageRoute.artists()),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.history_rounded, size: 16, color: tokens.text2),
                    label: const Text('Recently played'),
                    onPressed: () => _navigate(const MusicPageRoute.history()),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildMobileLibraryViewSlivers(
    BuildContext context,
    HermesThemeTokens tokens,
  ) {
    final liked = _likedSongs();
    final rowBuilders = <Widget Function()>[
      () => _LibraryRowButton(
            title: 'Liked Songs',
            subtitle: 'Playlist • ${liked.length} songs',
            active: false,
            playing: false,
            isLiked: true,
            onTap: () => _navigate(const MusicPageRoute.liked()),
            onSecondaryTapDown: (d) => unawaited(
              openMusicCollectionContextMenu(
                context,
                d.globalPosition,
                openLabel: 'Open Liked Songs',
                onOpen: () => _navigate(const MusicPageRoute.liked()),
                onPlay: () => unawaited(
                  _playCollection(
                    liked,
                    sourceLabel: 'Liked Songs',
                    sourceRoute: const MusicPageRoute.liked(),
                  ),
                ),
                onAddToQueue: () => _queueCollection(liked, 'Liked Songs'),
              ),
            ),
          ),
      for (final pl in _playlists)
        () => _LibraryRowButton(
              title: pl.name,
              subtitle: 'Playlist • ${pl.trackCount} songs',
              active: false,
              playing: false,
              isPlaylist: true,
              onTap: () => _navigate(MusicPageRoute.playlist(pl.id)),
              onSecondaryTapDown: (d) => unawaited(
                openMusicCollectionContextMenu(
                  context,
                  d.globalPosition,
                  openLabel: 'Open playlist',
                  onOpen: () => _navigate(MusicPageRoute.playlist(pl.id)),
                  onPlay: () => unawaited(_playPlaylist(pl)),
                  onAddToQueue: () => unawaited(_queuePlaylist(pl)),
                  extraItems: const [
                    PopupMenuItem(value: 'rename', child: Text('Rename playlist')),
                    PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                  ],
                  onExtraSelected: (action) {
                    if (action == 'rename') {
                      unawaited(_promptRenamePlaylist(pl));
                    } else if (action == 'delete') {
                      unawaited(_deletePlaylist(pl));
                    }
                  },
                ),
              ),
            ),
      for (final smart in SmartPlaylistKind.values)
        () => _LibraryRowButton(
              title: smart.title,
              subtitle: 'Smart playlist',
              active: false,
              playing: false,
              smartKind: smart,
              onTap: () => _navigate(MusicPageRoute.smart(smart.id)),
              onSecondaryTapDown: (d) {
                final songs = _smartSongs(smart);
                unawaited(
                  openMusicCollectionContextMenu(
                    context,
                    d.globalPosition,
                    openLabel: 'Open playlist',
                    onOpen: () => _navigate(MusicPageRoute.smart(smart.id)),
                    onPlay: () => unawaited(
                      _playCollection(
                        songs,
                        sourceLabel: smart.title,
                        sourceRoute: MusicPageRoute.smart(smart.id),
                      ),
                    ),
                    onAddToQueue: () => _queueCollection(songs, smart.title),
                  ),
                );
              },
            ),
      for (final alb in _albums)
        () => _LibraryRowButton(
              title: alb.title,
              subtitle: 'Album • ${alb.artistName}',
              active: false,
              playing: false,
              artworkUri: widget.musicService.buildArtworkUri(alb.artworkHash),
              onTap: () => _navigate(MusicPageRoute.album(alb.id)),
              onSecondaryTapDown: (d) {
                final songs = _albumSongs(alb.id);
                unawaited(
                  openMusicCollectionContextMenu(
                    context,
                    d.globalPosition,
                    openLabel: 'Open album',
                    onOpen: () => _navigate(MusicPageRoute.album(alb.id)),
                    onPlay: () => unawaited(
                      _playCollection(
                        songs,
                        sourceLabel: alb.title,
                        sourceRoute: MusicPageRoute.album(alb.id),
                      ),
                    ),
                    onAddToQueue: () => _queueCollection(songs, alb.title),
                  ),
                );
              },
            ),
    ];

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _ShelfTitle('Your Library', tokens),
                FilledButton.tonalIcon(
                  onPressed: _promptCreatePlaylist,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New playlist'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    key: const Key('music-lib-songs'),
                    avatar: Icon(Icons.music_note_rounded, size: 16, color: tokens.text2),
                    label: const Text('Songs'),
                    onPressed: () => _navigate(const MusicPageRoute.songs()),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('music-lib-albums'),
                    avatar: Icon(Icons.album_rounded, size: 16, color: tokens.text2),
                    label: const Text('Albums'),
                    onPressed: () => _navigate(const MusicPageRoute.albums()),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('music-lib-artists'),
                    avatar: Icon(Icons.person_rounded, size: 16, color: tokens.text2),
                    label: const Text('Artists'),
                    onPressed: () => _navigate(const MusicPageRoute.artists()),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('music-lib-history'),
                    avatar: Icon(Icons.history_rounded, size: 16, color: tokens.text2),
                    label: const Text('History'),
                    onPressed: () => _navigate(const MusicPageRoute.history()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, index) => RepaintBoundary(child: rowBuilders[index]()),
          childCount: rowBuilders.length,
        ),
      ),
    ];
  }

  Widget _buildMusicCardSliverGrid({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 204,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => RepaintBoundary(child: itemBuilder(context, index)),
        childCount: itemCount,
      ),
    );
  }

  Widget _buildAlbumSliverGrid(
    List<AlbumSummaryModel> albums, {
    ValueChanged<AlbumSummaryModel>? onOpened,
  }) {
    return _buildMusicCardSliverGrid(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final alb = albums[index];
        final year = alb.year != null ? '${alb.year} • ' : '';
        final songs = _albumSongs(alb.id);
        return MusicBrowseCard(
          title: alb.title,
          subtitle: '$year${alb.artistName}',
          openLabel: 'Open album',
          artworkUri: widget.musicService.buildArtworkUri(alb.artworkHash),
          onOpen: () {
            onOpened?.call(alb);
            _navigate(MusicPageRoute.album(alb.id));
          },
          onPlay: () => _playCollection(
            songs,
            sourceLabel: alb.title,
            sourceRoute: MusicPageRoute.album(alb.id),
          ),
          onAddToQueue: () => _queueCollection(songs, alb.title),
        );
      },
    );
  }

  Widget _buildSmartSliverGrid() {
    const smarts = SmartPlaylistKind.values;
    return _buildMusicCardSliverGrid(
      itemCount: smarts.length,
      itemBuilder: (context, index) {
        final smart = smarts[index];
        final songs = _smartSongs(smart);
        return MusicBrowseCard(
          title: smart.title,
          subtitle: smart.description,
          openLabel: 'Open playlist',
          smartKind: smart,
          onOpen: () => _navigate(MusicPageRoute.smart(smart.id)),
          onPlay: () => _playCollection(
            songs,
            sourceLabel: smart.title,
            sourceRoute: MusicPageRoute.smart(smart.id),
          ),
          onAddToQueue: () => _queueCollection(songs, smart.title),
        );
      },
    );
  }

  Widget _buildArtistSliverGrid(
    List<ArtistSummaryModel> artists, {
    ValueChanged<ArtistSummaryModel>? onOpened,
  }) {
    return _buildMusicCardSliverGrid(
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final art = artists[index];
        final songs = _artistSongs(art.id);
        return MusicBrowseCard(
          title: art.name,
          subtitle:
              'Artist • ${art.albumCount} ${art.albumCount == 1 ? 'album' : 'albums'}',
          openLabel: 'Open artist',
          artworkUri: widget.musicService.buildArtworkUri(art.artworkHash),
          circular: true,
          onOpen: () {
            onOpened?.call(art);
            _navigate(MusicPageRoute.artist(art.id));
          },
          onPlay: () => _playCollection(
            songs,
            sourceLabel: art.name,
            sourceRoute: MusicPageRoute.artist(art.id),
          ),
          onAddToQueue: () => _queueCollection(songs, art.name),
        );
      },
    );
  }

  Widget _buildPlaylistSliverGrid(
    List<PlaylistSummaryModel> playlists, {
    ValueChanged<PlaylistSummaryModel>? onOpened,
  }) {
    return _buildMusicCardSliverGrid(
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return MusicBrowseCard(
          title: pl.name,
          subtitle: 'Playlist • ${pl.trackCount} songs',
          openLabel: 'Open playlist',
          isPlaylist: true,
          onOpen: () {
            onOpened?.call(pl);
            _navigate(MusicPageRoute.playlist(pl.id));
          },
          onPlay: () => unawaited(_playPlaylist(pl)),
          onAddToQueue: () => unawaited(_queuePlaylist(pl)),
          extraMenuItems: const [
            PopupMenuItem(value: 'rename', child: Text('Rename playlist')),
            PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
          ],
          onExtraMenuSelected: (action) {
            if (action == 'rename') {
              unawaited(_promptRenamePlaylist(pl));
            } else if (action == 'delete') {
              unawaited(_deletePlaylist(pl));
            }
          },
        );
      },
    );
  }
}

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
    required this.scrolled,
    required this.tint,
    required this.controller,
    required this.focusNode,
    required this.hasQuery,
    required this.onBack,
    required this.onQueryChanged,
    required this.onSubmitted,
    required this.onClearSearch,
  });

  final bool canGoBack;
  final bool scrolled;
  final Color tint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasQuery;
  final VoidCallback onBack;
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
          Opacity(
            alwaysIncludeSemantics: true,
            opacity: canGoBack ? 1.0 : 0.45,
            child: InkWell(
              onTap: canGoBack ? onBack : null,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
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
