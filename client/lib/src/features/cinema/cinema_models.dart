enum VideoQualityPreset {
  directPlay('DirectPlay', 'Direct Play'),
  p1080('1080p', '1080p'),
  p720('720p', '720p'),
  p480('480p', '480p');

  const VideoQualityPreset(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class MediaStreamModel {
  const MediaStreamModel({
    required this.streamIndex,
    required this.kind,
    required this.codec,
    required this.language,
    required this.title,
    required this.isDefault,
  });

  final int streamIndex;
  final int kind; // 0: Video, 1: Audio, 2: Subtitle
  final String codec;
  final String language;
  final String title;
  final bool isDefault;

  bool get isAudio => kind == 1;
  bool get isSubtitle => kind == 2;

  factory MediaStreamModel.fromJson(Map<String, dynamic> json) {
    return MediaStreamModel(
      streamIndex: json['streamIndex'] as int,
      kind: json['kind'] as int,
      codec: json['codec'] as String? ?? '',
      language: json['language'] as String? ?? 'und',
      title: json['title'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

class MediaSourceModel {
  const MediaSourceModel({
    required this.id,
    required this.sourceLabel,
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.width,
    required this.height,
    required this.isHdr,
    required this.bitrateBps,
    required this.durationMs,
    required this.isAvailable,
    required this.streams,
  });

  final String id;
  final String sourceLabel;
  final String container;
  final String videoCodec;
  final String audioCodec;
  final int width;
  final int height;
  final bool isHdr;
  final int bitrateBps;
  final int durationMs;
  final bool isAvailable;
  final List<MediaStreamModel> streams;

  List<MediaStreamModel> get audioStreams => streams.where((s) => s.isAudio).toList();
  List<MediaStreamModel> get subtitleStreams => streams.where((s) => s.isSubtitle).toList();

  factory MediaSourceModel.fromJson(Map<String, dynamic> json) {
    final rawStreams = json['streams'] as List<dynamic>? ?? const [];
    return MediaSourceModel(
      id: json['id'] as String,
      sourceLabel: json['sourceLabel'] as String? ?? '',
      container: json['container'] as String? ?? '',
      videoCodec: json['videoCodec'] as String? ?? '',
      audioCodec: json['audioCodec'] as String? ?? '',
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      isHdr: json['isHdr'] as bool? ?? false,
      bitrateBps: (json['bitrateBps'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      isAvailable: json['isAvailable'] as bool? ?? true,
      streams: rawStreams
          .map((e) => MediaStreamModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WatchProgressModel {
  const WatchProgressModel({
    required this.positionMs,
    required this.durationMs,
    required this.isWatched,
    required this.updatedAtUtc,
  });

  final int positionMs;
  final int durationMs;
  final bool isWatched;
  final DateTime updatedAtUtc;

  double get completionRatio {
    if (durationMs <= 0) {
      return 0;
    }
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  factory WatchProgressModel.fromJson(Map<String, dynamic> json) {
    return WatchProgressModel(
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      isWatched: json['isWatched'] as bool? ?? false,
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }
}

class MovieSummary {
  const MovieSummary({
    required this.id,
    required this.title,
    this.year,
    this.overview,
    this.tmdbId,
    this.artworkHash,
    this.backdropHash,
    this.watchProgress,
    required this.sources,
  });

  final String id;
  final String title;
  final int? year;
  final String? overview;
  final int? tmdbId;
  final String? artworkHash;
  final String? backdropHash;
  final WatchProgressModel? watchProgress;
  final List<MediaSourceModel> sources;

  factory MovieSummary.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>? ?? const [];
    final rawProgress = json['watchProgress'] as Map<String, dynamic>?;
    return MovieSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      overview: json['overview'] as String?,
      tmdbId: json['tmdbId'] as int?,
      artworkHash: json['artworkHash'] as String?,
      backdropHash: json['backdropHash'] as String?,
      watchProgress: rawProgress == null ? null : WatchProgressModel.fromJson(rawProgress),
      sources: rawSources
          .map((e) => MediaSourceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class EpisodeSummary {
  const EpisodeSummary({
    required this.id,
    required this.episodeNumber,
    required this.title,
    this.overview,
    this.stillArtworkHash,
    this.watchProgress,
    required this.sources,
  });

  final String id;
  final int episodeNumber;
  final String title;
  final String? overview;
  final String? stillArtworkHash;
  final WatchProgressModel? watchProgress;
  final List<MediaSourceModel> sources;

  factory EpisodeSummary.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>? ?? const [];
    final rawProgress = json['watchProgress'] as Map<String, dynamic>?;
    return EpisodeSummary(
      id: json['id'] as String,
      episodeNumber: json['episodeNumber'] as int? ?? 1,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      stillArtworkHash: json['stillArtworkHash'] as String?,
      watchProgress: rawProgress == null ? null : WatchProgressModel.fromJson(rawProgress),
      sources: rawSources
          .map((e) => MediaSourceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TvSeasonModel {
  const TvSeasonModel({
    required this.id,
    required this.seasonNumber,
    required this.title,
    this.artworkHash,
    required this.episodes,
  });

  final String id;
  final int seasonNumber;
  final String title;
  final String? artworkHash;
  final List<EpisodeSummary> episodes;

  factory TvSeasonModel.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? const [];
    return TvSeasonModel(
      id: json['id'] as String,
      seasonNumber: json['seasonNumber'] as int? ?? 1,
      title: json['title'] as String? ?? '',
      artworkHash: json['artworkHash'] as String?,
      episodes: rawEpisodes
          .map((e) => EpisodeSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TvSeriesSummary {
  const TvSeriesSummary({
    required this.id,
    required this.title,
    this.year,
    this.overview,
    this.tmdbId,
    this.artworkHash,
    this.backdropHash,
    required this.seasons,
  });

  final String id;
  final String title;
  final int? year;
  final String? overview;
  final int? tmdbId;
  final String? artworkHash;
  final String? backdropHash;
  final List<TvSeasonModel> seasons;

  factory TvSeriesSummary.fromJson(Map<String, dynamic> json) {
    final rawSeasons = json['seasons'] as List<dynamic>? ?? const [];
    return TvSeriesSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      overview: json['overview'] as String?,
      tmdbId: json['tmdbId'] as int?,
      artworkHash: json['artworkHash'] as String?,
      backdropHash: json['backdropHash'] as String?,
      seasons: rawSeasons
          .map((e) => TvSeasonModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
