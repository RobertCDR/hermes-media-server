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
    );
  }

  factory SongModel.fromJson(Map<String, dynamic> json) {
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
