import 'package:material_ui/material_ui.dart' show Color, HSLColor;

enum AudioQualityPreset {
  lossless('Lossless', 'Lossless'),
  veryHigh320('VeryHigh320', 'Very High (320k)'),
  high160('High160', 'High (160k)'),
  medium96('Medium96', 'Medium (96k)'),
  low64('Low64', 'Low (64k)');

  const AudioQualityPreset(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

enum NetworkTransportMode {
  wifi('Wi-Fi'),
  cellular('Cellular');

  const NetworkTransportMode(this.label);
  final String label;
}

class AudioQualityPolicy {
  const AudioQualityPolicy({
    this.wifiPreset = AudioQualityPreset.lossless,
    this.cellularPreset = AudioQualityPreset.high160,
  });

  final AudioQualityPreset wifiPreset;
  final AudioQualityPreset cellularPreset;

  AudioQualityPreset presetFor(NetworkTransportMode mode) =>
      mode == NetworkTransportMode.wifi ? wifiPreset : cellularPreset;
}

enum PlaybackState {
  stopped,
  playing,
  paused;

  static PlaybackState fromApiInt(int value) => switch (value) {
        1 => PlaybackState.playing,
        2 => PlaybackState.paused,
        _ => PlaybackState.stopped,
      };
}

enum HermesRepeatMode {
  off,
  all,
  one;

  static HermesRepeatMode fromApiInt(int value) => switch (value) {
        1 => HermesRepeatMode.all,
        2 => HermesRepeatMode.one,
        _ => HermesRepeatMode.off,
      };
}

class ArtistSummaryModel {
  const ArtistSummaryModel({
    required this.id,
    required this.name,
    this.artworkHash,
    required this.albumCount,
  });

  final String id;
  final String name;
  final String? artworkHash;
  final int albumCount;

  factory ArtistSummaryModel.fromJson(Map<String, dynamic> json) {
    return ArtistSummaryModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      artworkHash: json['artworkHash'] as String?,
      albumCount: json['albumCount'] as int? ?? 0,
    );
  }
}

class AlbumSummaryModel {
  const AlbumSummaryModel({
    required this.id,
    required this.artistId,
    required this.artistName,
    required this.title,
    this.year,
    this.artworkHash,
    required this.songCount,
  });

  final String id;
  final String artistId;
  final String artistName;
  final String title;
  final int? year;
  final String? artworkHash;
  final int songCount;

  factory AlbumSummaryModel.fromJson(Map<String, dynamic> json) {
    return AlbumSummaryModel(
      id: json['id'] as String,
      artistId: json['artistId'] as String,
      artistName: json['artistName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      artworkHash: json['artworkHash'] as String?,
      songCount: json['songCount'] as int? ?? 0,
    );
  }
}

class ArtistCreditModel {
  const ArtistCreditModel({
    required this.artistId,
    required this.name,
  });

  final String artistId;
  final String name;

  factory ArtistCreditModel.fromJson(Map<String, dynamic> json) {
    return ArtistCreditModel(
      artistId: json['artistId'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

class SongModel {
  const SongModel({
    required this.id,
    required this.artistId,
    required this.artistName,
    required this.albumId,
    required this.albumTitle,
    required this.title,
    required this.trackNumber,
    required this.discNumber,
    required this.durationMs,
    required this.codec,
    required this.bitrateBps,
    required this.sampleRateHz,
    required this.bitDepth,
    this.artworkHash,
    required this.isLiked,
    required this.isMissing,
    this.fileLastWriteUtc,
    this.artistCredits = const [],
  });

  final String id;
  final String artistId;
  final String artistName;
  final String albumId;
  final String albumTitle;
  final String title;
  final int trackNumber;
  final int discNumber;
  final int durationMs;
  final String codec;
  final int bitrateBps;
  final int sampleRateHz;
  final int bitDepth;
  final String? artworkHash;
  final bool isLiked;
  final bool isMissing;
  final DateTime? fileLastWriteUtc;
  final List<ArtistCreditModel> artistCredits;

  List<ArtistCreditModel> get effectiveArtistCredits {
    if (artistCredits.isNotEmpty) return artistCredits;
    if (artistName.trim().isEmpty) return const [];
    return [ArtistCreditModel(artistId: artistId, name: artistName)];
  }

  SongModel copyWith({bool? isLiked}) {
    return SongModel(
      id: id,
      artistId: artistId,
      artistName: artistName,
      albumId: albumId,
      albumTitle: albumTitle,
      title: title,
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationMs: durationMs,
      codec: codec,
      bitrateBps: bitrateBps,
      sampleRateHz: sampleRateHz,
      bitDepth: bitDepth,
      artworkHash: artworkHash,
      isLiked: isLiked ?? this.isLiked,
      isMissing: isMissing,
      fileLastWriteUtc: fileLastWriteUtc,
      artistCredits: artistCredits,
    );
  }

  factory SongModel.fromJson(Map<String, dynamic> json) {
    final rawModified = json['fileLastWriteUtc'] as String?;
    final rawCredits = json['artistCredits'] as List<dynamic>? ?? const [];
    return SongModel(
      id: json['id'] as String,
      artistId: json['artistId'] as String,
      artistName: json['artistName'] as String? ?? '',
      albumId: json['albumId'] as String,
      albumTitle: json['albumTitle'] as String? ?? '',
      title: json['title'] as String? ?? '',
      trackNumber: json['trackNumber'] as int? ?? 1,
      discNumber: json['discNumber'] as int? ?? 1,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      codec: json['codec'] as String? ?? '',
      bitrateBps: (json['bitrateBps'] as num?)?.toInt() ?? 0,
      sampleRateHz: json['sampleRateHz'] as int? ?? 44100,
      bitDepth: json['bitDepth'] as int? ?? 16,
      artworkHash: json['artworkHash'] as String?,
      isLiked: json['isLiked'] as bool? ?? false,
      isMissing: json['isMissing'] as bool? ?? false,
      fileLastWriteUtc: rawModified == null ? null : DateTime.tryParse(rawModified),
      artistCredits: rawCredits
          .map((e) => ArtistCreditModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ListeningHistoryItemModel {
  const ListeningHistoryItemModel({
    required this.id,
    required this.listenedAtUtc,
    this.deviceId,
    this.contextLabel,
    required this.song,
  });

  final String id;
  final DateTime listenedAtUtc;
  final String? deviceId;
  final String? contextLabel;
  final SongModel song;

  factory ListeningHistoryItemModel.fromJson(Map<String, dynamic> json) {
    return ListeningHistoryItemModel(
      id: json['id'] as String? ?? '',
      listenedAtUtc: DateTime.parse(json['listenedAtUtc'] as String),
      deviceId: json['deviceId'] as String?,
      contextLabel: json['contextLabel'] as String?,
      song: SongModel.fromJson(json['song'] as Map<String, dynamic>),
    );
  }
}

class PlaylistSummaryModel {
  const PlaylistSummaryModel({
    required this.id,
    required this.name,
    this.description,
    required this.trackCount,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final String name;
  final String? description;
  final int trackCount;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  factory PlaylistSummaryModel.fromJson(Map<String, dynamic> json) {
    return PlaylistSummaryModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      trackCount: json['trackCount'] as int? ?? 0,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }
}

class PlaylistTrackModel {
  const PlaylistTrackModel({required this.position, required this.song});

  final int position;
  final SongModel song;

  factory PlaylistTrackModel.fromJson(Map<String, dynamic> json) {
    return PlaylistTrackModel(
      position: json['position'] as int,
      song: SongModel.fromJson(json['song'] as Map<String, dynamic>),
    );
  }
}

class PlaylistDetailModel {
  const PlaylistDetailModel({
    required this.id,
    required this.name,
    this.description,
    required this.tracks,
  });

  final String id;
  final String name;
  final String? description;
  final List<PlaylistTrackModel> tracks;

  factory PlaylistDetailModel.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? const [];
    return PlaylistDetailModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      tracks: rawTracks
          .map((e) => PlaylistTrackModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OnlineDeviceModel {
  const OnlineDeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.connectedAtUtc,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime connectedAtUtc;

  factory OnlineDeviceModel.fromJson(Map<String, dynamic> json) {
    return OnlineDeviceModel(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String? ?? 'Hermes Client',
      platform: json['platform'] as String? ?? 'Unknown',
      connectedAtUtc: DateTime.parse(json['connectedAtUtc'] as String),
    );
  }
}

class PlaybackSessionState {
  const PlaybackSessionState({
    required this.sessionId,
    required this.version,
    this.activeRendererDeviceId,
    this.activeRendererDeviceName,
    required this.state,
    required this.repeatMode,
    required this.shuffle,
    required this.volume,
    required this.currentIndex,
    this.currentSongId,
    required this.positionMs,
    required this.queueSongIds,
  });

  final String sessionId;
  final int version;
  final String? activeRendererDeviceId;
  final String? activeRendererDeviceName;
  final PlaybackState state;
  final HermesRepeatMode repeatMode;
  final bool shuffle;
  final double volume;
  final int currentIndex;
  final String? currentSongId;
  final int positionMs;
  final List<String> queueSongIds;

  factory PlaybackSessionState.fromJson(Map<String, dynamic> json) {
    final rawQueue = json['queueSongIds'] as List<dynamic>? ?? const [];
    return PlaybackSessionState(
      sessionId: json['sessionId'] as String,
      version: (json['version'] as num).toInt(),
      activeRendererDeviceId: json['activeRendererDeviceId'] as String?,
      activeRendererDeviceName: json['activeRendererDeviceName'] as String?,
      state: PlaybackState.fromApiInt((json['state'] as num?)?.toInt() ?? 0),
      repeatMode: HermesRepeatMode.fromApiInt((json['repeatMode'] as num?)?.toInt() ?? 0),
      shuffle: json['shuffle'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      currentIndex: json['currentIndex'] as int? ?? 0,
      currentSongId: json['currentSongId'] as String?,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      queueSongIds: rawQueue.cast<String>(),
    );
  }
}

class UnifiedSearchMovieHit {
  const UnifiedSearchMovieHit({
    required this.id,
    required this.title,
    this.year,
    this.artworkHash,
  });

  final String id;
  final String title;
  final int? year;
  final String? artworkHash;

  factory UnifiedSearchMovieHit.fromJson(Map<String, dynamic> json) {
    return UnifiedSearchMovieHit(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      artworkHash: json['artworkHash'] as String?,
    );
  }
}

class UnifiedSearchSeriesHit {
  const UnifiedSearchSeriesHit({
    required this.id,
    required this.title,
    this.year,
    this.artworkHash,
  });

  final String id;
  final String title;
  final int? year;
  final String? artworkHash;

  factory UnifiedSearchSeriesHit.fromJson(Map<String, dynamic> json) {
    return UnifiedSearchSeriesHit(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      artworkHash: json['artworkHash'] as String?,
    );
  }
}

class UnifiedSearchResult {
  const UnifiedSearchResult({
    required this.query,
    required this.movies,
    required this.series,
    required this.artists,
    required this.albums,
    required this.songs,
  });

  final String query;
  final List<UnifiedSearchMovieHit> movies;
  final List<UnifiedSearchSeriesHit> series;
  final List<ArtistSummaryModel> artists;
  final List<AlbumSummaryModel> albums;
  final List<SongModel> songs;

  bool get isEmpty =>
      movies.isEmpty && series.isEmpty && artists.isEmpty && albums.isEmpty && songs.isEmpty;

  factory UnifiedSearchResult.fromJson(Map<String, dynamic> json) {
    final rawMovies = json['movies'] as List<dynamic>? ?? const [];
    final rawSeries = json['series'] as List<dynamic>? ?? const [];
    final rawArtists = json['artists'] as List<dynamic>? ?? const [];
    final rawAlbums = json['albums'] as List<dynamic>? ?? const [];
    final rawSongs = json['songs'] as List<dynamic>? ?? const [];
    return UnifiedSearchResult(
      query: json['query'] as String? ?? '',
      movies: rawMovies
          .map((e) => UnifiedSearchMovieHit.fromJson(e as Map<String, dynamic>))
          .toList(),
      series: rawSeries
          .map((e) => UnifiedSearchSeriesHit.fromJson(e as Map<String, dynamic>))
          .toList(),
      artists: rawArtists
          .map((e) => ArtistSummaryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      albums: rawAlbums
          .map((e) => AlbumSummaryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: rawSongs
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AlbumDetailModel {
  const AlbumDetailModel({
    required this.id,
    required this.artistId,
    required this.artistName,
    required this.title,
    this.year,
    this.artworkHash,
    required this.songs,
  });

  final String id;
  final String artistId;
  final String artistName;
  final String title;
  final int? year;
  final String? artworkHash;
  final List<SongModel> songs;

  factory AlbumDetailModel.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'] as List<dynamic>? ?? const [];
    return AlbumDetailModel(
      id: json['id'] as String,
      artistId: json['artistId'] as String,
      artistName: json['artistName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      artworkHash: json['artworkHash'] as String?,
      songs: rawSongs
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ArtistDetailModel {
  const ArtistDetailModel({
    required this.id,
    required this.name,
    this.artworkHash,
    required this.albums,
    required this.songs,
  });

  final String id;
  final String name;
  final String? artworkHash;
  final List<AlbumSummaryModel> albums;
  final List<SongModel> songs;

  factory ArtistDetailModel.fromJson(Map<String, dynamic> json) {
    final rawAlbums = json['albums'] as List<dynamic>? ?? const [];
    final rawSongs = json['songs'] as List<dynamic>? ?? const [];
    return ArtistDetailModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      artworkHash: json['artworkHash'] as String?,
      albums: rawAlbums
          .map((e) => AlbumSummaryModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      songs: rawSongs
          .map((e) => SongModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SongLyricLineModel {
  const SongLyricLineModel({this.timestampMs, required this.text});

  final int? timestampMs;
  final String text;

  factory SongLyricLineModel.fromJson(Map<String, dynamic> json) {
    return SongLyricLineModel(
      timestampMs: (json['timestampMs'] as num?)?.toInt(),
      text: json['text'] as String? ?? '',
    );
  }
}

class SongLyricsModel {
  const SongLyricsModel({
    required this.songId,
    required this.isSynced,
    required this.source,
    required this.lines,
  });

  final String songId;
  final bool isSynced;
  final String source;
  final List<SongLyricLineModel> lines;

  factory SongLyricsModel.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? const [];
    return SongLyricsModel(
      songId: json['songId'] as String? ?? '',
      isSynced: json['isSynced'] as bool? ?? false,
      source: json['source'] as String? ?? 'none',
      lines: rawLines
          .map((e) => SongLyricLineModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum SmartPlaylistKind {
  recentlyAdded(
    id: 'recent',
    title: 'Recently added',
    description: 'Latest additions to your music library',
  ),
  losslessMasters(
    id: 'lossless',
    title: 'Lossless masters',
    description: 'Bit-perfect FLAC, ALAC and WAV tracks',
  ),
  freshMix(
    id: 'mix',
    title: 'Deep cuts mix',
    description: 'Varied picks across albums in your collection',
  );

  const SmartPlaylistKind({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}

enum MusicPageKind {
  home,
  albums,
  artists,
  songs,
  library,
  liked,
  history,
  album,
  artist,
  playlist,
  smart,
}

class MusicPageRoute {
  const MusicPageRoute._({required this.kind, this.targetId});

  const MusicPageRoute.home() : this._(kind: MusicPageKind.home);
  const MusicPageRoute.albums() : this._(kind: MusicPageKind.albums);
  const MusicPageRoute.artists() : this._(kind: MusicPageKind.artists);
  const MusicPageRoute.songs() : this._(kind: MusicPageKind.songs);
  const MusicPageRoute.library() : this._(kind: MusicPageKind.library);
  const MusicPageRoute.liked() : this._(kind: MusicPageKind.liked);
  const MusicPageRoute.history() : this._(kind: MusicPageKind.history);
  const MusicPageRoute.album(String id) : this._(kind: MusicPageKind.album, targetId: id);
  const MusicPageRoute.artist(String id) : this._(kind: MusicPageKind.artist, targetId: id);
  const MusicPageRoute.playlist(String id) : this._(kind: MusicPageKind.playlist, targetId: id);
  const MusicPageRoute.smart(String id) : this._(kind: MusicPageKind.smart, targetId: id);

  final MusicPageKind kind;
  final String? targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicPageRoute &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          targetId == other.targetId;

  @override
  int get hashCode => Object.hash(kind, targetId);
}

/// Coordinates cross-surface navigation into Music routes (e.g. clicking song title -> Album).
class MusicNavigationController {
  MusicNavigationController({this.onRequestRoute});

  void Function(MusicPageRoute route)? onRequestRoute;
  MusicPageRoute? _pendingRoute;

  void navigate(MusicPageRoute route) {
    final handler = onRequestRoute;
    if (handler != null) {
      _pendingRoute = null;
      handler(route);
    } else {
      _pendingRoute = route;
    }
  }

  MusicPageRoute? takePendingRoute() {
    final next = _pendingRoute;
    _pendingRoute = null;
    return next;
  }
}

/// Deterministic dark-surface wash tint matching Figma v4 `--tint` backdrops.
Color deriveMusicTint(String seed, {Color fallback = const Color(0xFF42362C)}) {
  final trimmed = seed.trim();
  if (trimmed.isEmpty) return fallback;
  var hash = 2166136261;
  for (final unit in trimmed.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  final sat = 0.34 + ((hash >> 8) % 24) / 100.0;
  final light = 0.25 + ((hash >> 16) % 10) / 100.0;
  return HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
}
