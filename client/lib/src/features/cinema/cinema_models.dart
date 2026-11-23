import 'package:material_ui/material_ui.dart';

enum VideoQualityPreset {
  directPlay('DirectPlay', 'Direct Play'),
  p1080('1080p', '1080p'),
  p720('720p', '720p'),
  p480('480p', '480p');

  const VideoQualityPreset(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

enum VideoAspectMode {
  fit('Fit', BoxFit.contain),
  cover('Cover', BoxFit.cover),
  stretch('Stretch', BoxFit.fill);

  const VideoAspectMode(this.label, this.boxFit);

  final String label;
  final BoxFit boxFit;
}

class CastMemberModel {
  const CastMemberModel({
    required this.name,
    required this.role,
    this.artworkHash,
  });

  final String name;
  final String role;
  final String? artworkHash;

  factory CastMemberModel.fromJson(Map<String, dynamic> json) {
    return CastMemberModel(
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      artworkHash: json['artworkHash'] as String?,
    );
  }
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

  List<MediaStreamModel> get audioStreams =>
      streams.where((s) => s.isAudio).toList();

  List<MediaStreamModel> get subtitleStreams =>
      streams.where((s) => s.isSubtitle).toList();

  String get shortTag {
    if (height >= 2160) return isHdr ? '4K HDR' : '4K';
    if (height >= 1080) return isHdr ? '1080p HDR' : '1080p';
    if (height > 0) return '${height}p';
    return videoCodec.isEmpty ? 'Source' : videoCodec.toUpperCase();
  }

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

  int get remainingMinutes {
    if (durationMs <= 0) return 0;
    final leftMs = (durationMs - positionMs).clamp(0, durationMs);
    return (leftMs / 60000).ceil();
  }

  factory WatchProgressModel.fromJson(Map<String, dynamic> json) {
    final rawUpdated = json['updatedAtUtc'] as String?;
    return WatchProgressModel(
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      isWatched: json['isWatched'] as bool? ?? false,
      updatedAtUtc: rawUpdated != null
          ? DateTime.parse(rawUpdated)
          : DateTime.now().toUtc(),
    );
  }
}

enum CinemaResumeMode { start, resume, next, finished }

class CinemaEpisodeEntry {
  const CinemaEpisodeEntry({
    required this.seasonNumber,
    required this.episode,
  });

  final int seasonNumber;
  final EpisodeSummary episode;

  String get code => 'S$seasonNumber E${episode.episodeNumber}';
}

class CinemaResumePoint {
  const CinemaResumePoint({
    required this.mode,
    required this.progress,
    required this.durationMinutes,
    this.episodeEntry,
  });

  final CinemaResumeMode mode;
  final double progress;
  final int durationMinutes;
  final CinemaEpisodeEntry? episodeEntry;

  String get playLabel {
    if (episodeEntry == null) {
      return mode == CinemaResumeMode.resume ? 'Resume' : 'Play';
    }
    return switch (mode) {
      CinemaResumeMode.resume => 'Resume ${episodeEntry!.code}',
      CinemaResumeMode.next => 'Play ${episodeEntry!.code}',
      CinemaResumeMode.start => 'Play ${episodeEntry!.code}',
      CinemaResumeMode.finished => 'Watch again',
    };
  }

  int get remainingMinutes =>
      (durationMinutes * (1.0 - progress)).ceil().clamp(0, durationMinutes);
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
    this.addedAtUtc,
    this.rating,
    this.genres = const [],
    this.runtimeMinutes,
    this.isInWatchlist = false,
    this.cast = const [],
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
  final DateTime? addedAtUtc;
  final double? rating;
  final List<String> genres;
  final int? runtimeMinutes;
  final bool isInWatchlist;
  final List<CastMemberModel> cast;

  bool get isWatched => watchProgress?.isWatched == true;

  bool get isNew => isAddedRecently(addedAtUtc);

  int get durationMinutes {
    if (runtimeMinutes != null && runtimeMinutes! > 0) {
      return runtimeMinutes!;
    }
    final ms = sources.firstOrNull?.durationMs ?? 0;
    return ms > 0 ? (ms / 60000).round() : 0;
  }

  CinemaResumePoint get resumePoint {
    final progress = isWatched ? 0.0 : (watchProgress?.completionRatio ?? 0.0);
    return CinemaResumePoint(
      mode: progress > 0 ? CinemaResumeMode.resume : CinemaResumeMode.start,
      progress: progress,
      durationMinutes: durationMinutes,
    );
  }

  MovieSummary copyWith({
    WatchProgressModel? watchProgress,
    bool clearWatchProgress = false,
    bool? isInWatchlist,
  }) {
    return MovieSummary(
      id: id,
      title: title,
      year: year,
      overview: overview,
      tmdbId: tmdbId,
      artworkHash: artworkHash,
      backdropHash: backdropHash,
      watchProgress: clearWatchProgress
          ? null
          : (watchProgress ?? this.watchProgress),
      sources: sources,
      addedAtUtc: addedAtUtc,
      rating: rating,
      genres: genres,
      runtimeMinutes: runtimeMinutes,
      isInWatchlist: isInWatchlist ?? this.isInWatchlist,
      cast: cast,
    );
  }

  factory MovieSummary.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>? ?? const [];
    final rawProgress = json['watchProgress'] as Map<String, dynamic>?;
    final rawGenres = json['genres'] as List<dynamic>? ?? const [];
    final rawCast = json['cast'] as List<dynamic>? ?? const [];
    final rawAdded = json['addedAtUtc'] as String?;

    return MovieSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      overview: json['overview'] as String?,
      tmdbId: json['tmdbId'] as int?,
      artworkHash: json['artworkHash'] as String?,
      backdropHash: json['backdropHash'] as String?,
      watchProgress: rawProgress == null
          ? null
          : WatchProgressModel.fromJson(rawProgress),
      sources: rawSources
          .map((e) => MediaSourceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      addedAtUtc: rawAdded != null && !rawAdded.startsWith('0001-')
          ? DateTime.tryParse(rawAdded)
          : null,
      rating: (json['rating'] as num?)?.toDouble(),
      genres: rawGenres.map((g) => g.toString()).toList(),
      runtimeMinutes: json['runtimeMinutes'] as int?,
      isInWatchlist: json['isInWatchlist'] as bool? ?? false,
      cast: rawCast
          .map((c) => CastMemberModel.fromJson(c as Map<String, dynamic>))
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

  int get durationMinutes {
    final ms = sources.firstOrNull?.durationMs ?? 0;
    return ms > 0 ? (ms / 60000).round() : 0;
  }

  EpisodeSummary copyWith({WatchProgressModel? watchProgress}) {
    return EpisodeSummary(
      id: id,
      episodeNumber: episodeNumber,
      title: title,
      overview: overview,
      stillArtworkHash: stillArtworkHash,
      watchProgress: watchProgress ?? this.watchProgress,
      sources: sources,
    );
  }

  factory EpisodeSummary.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>? ?? const [];
    final rawProgress = json['watchProgress'] as Map<String, dynamic>?;
    return EpisodeSummary(
      id: json['id'] as String,
      episodeNumber: json['episodeNumber'] as int? ?? 1,
      title: json['title'] as String? ?? '',
      overview: json['overview'] as String?,
      stillArtworkHash: json['stillArtworkHash'] as String?,
      watchProgress: rawProgress == null
          ? null
          : WatchProgressModel.fromJson(rawProgress),
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
    this.expectedEpisodeCount,
  });

  final String id;
  final int seasonNumber;
  final String title;
  final String? artworkHash;
  final List<EpisodeSummary> episodes;
  final int? expectedEpisodeCount;

  int get missingEpisodeCount {
    if (expectedEpisodeCount == null || expectedEpisodeCount! <= episodes.length) {
      return 0;
    }
    return expectedEpisodeCount! - episodes.length;
  }

  TvSeasonModel copyWith({List<EpisodeSummary>? episodes}) {
    return TvSeasonModel(
      id: id,
      seasonNumber: seasonNumber,
      title: title,
      artworkHash: artworkHash,
      episodes: episodes ?? this.episodes,
      expectedEpisodeCount: expectedEpisodeCount,
    );
  }

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
      expectedEpisodeCount: json['expectedEpisodeCount'] as int?,
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
    this.addedAtUtc,
    this.rating,
    this.genres = const [],
    this.isInWatchlist = false,
    this.cast = const [],
  });

  final String id;
  final String title;
  final int? year;
  final String? overview;
  final int? tmdbId;
  final String? artworkHash;
  final String? backdropHash;
  final List<TvSeasonModel> seasons;
  final DateTime? addedAtUtc;
  final double? rating;
  final List<String> genres;
  final bool isInWatchlist;
  final List<CastMemberModel> cast;

  List<CinemaEpisodeEntry> get allEpisodes => [
        for (final season in seasons)
          for (final ep in season.episodes)
            CinemaEpisodeEntry(seasonNumber: season.seasonNumber, episode: ep),
      ];

  int get availableEpisodeCount => allEpisodes.length;

  int get expectedTotalEpisodeCount => seasons.fold<int>(
        0,
        (sum, s) =>
            sum +
            (s.expectedEpisodeCount != null &&
                    s.expectedEpisodeCount! > s.episodes.length
                ? s.expectedEpisodeCount!
                : s.episodes.length),
      );

  bool get isPartial =>
      expectedTotalEpisodeCount > availableEpisodeCount && seasons.isNotEmpty;

  bool get isNew => isAddedRecently(addedAtUtc);

  bool get isWatched {
    final eps = allEpisodes;
    return eps.isNotEmpty && eps.every((e) => e.episode.watchProgress?.isWatched == true);
  }

  CinemaEpisodeEntry? nextEpisodeAfter(int seasonNumber, int episodeNumber) {
    final eps = allEpisodes;
    final idx = eps.indexWhere(
      (e) =>
          e.seasonNumber == seasonNumber &&
          e.episode.episodeNumber == episodeNumber,
    );
    if (idx < 0 || idx + 1 >= eps.length) {
      return null;
    }
    return eps[idx + 1];
  }

  CinemaResumePoint? get resumePoint {
    final eps = allEpisodes;
    if (eps.isEmpty) return null;

    final inProgressList = eps.where((e) {
      final wp = e.episode.watchProgress;
      return wp != null && !wp.isWatched && wp.positionMs > 0;
    }).toList();
    if (inProgressList.isNotEmpty) {
      inProgressList.sort(
        (a, b) => b.episode.watchProgress!.updatedAtUtc
            .compareTo(a.episode.watchProgress!.updatedAtUtc),
      );
      final inProgress = inProgressList.first;
      return CinemaResumePoint(
        mode: CinemaResumeMode.resume,
        progress: inProgress.episode.watchProgress!.completionRatio,
        durationMinutes: inProgress.episode.durationMinutes,
        episodeEntry: inProgress,
      );
    }

    var lastDoneIndex = -1;
    for (var i = 0; i < eps.length; i++) {
      if (eps[i].episode.watchProgress?.isWatched == true) {
        lastDoneIndex = i;
      }
    }

    if (lastDoneIndex >= 0 && lastDoneIndex + 1 < eps.length) {
      final upNext = eps[lastDoneIndex + 1];
      return CinemaResumePoint(
        mode: CinemaResumeMode.next,
        progress: 0,
        durationMinutes: upNext.episode.durationMinutes,
        episodeEntry: upNext,
      );
    }

    final first = eps.first;
    return CinemaResumePoint(
      mode: lastDoneIndex >= 0
          ? CinemaResumeMode.finished
          : CinemaResumeMode.start,
      progress: 0,
      durationMinutes: first.episode.durationMinutes,
      episodeEntry: first,
    );
  }

  TvSeriesSummary copyWith({
    List<TvSeasonModel>? seasons,
    bool? isInWatchlist,
  }) {
    return TvSeriesSummary(
      id: id,
      title: title,
      year: year,
      overview: overview,
      tmdbId: tmdbId,
      artworkHash: artworkHash,
      backdropHash: backdropHash,
      seasons: seasons ?? this.seasons,
      addedAtUtc: addedAtUtc,
      rating: rating,
      genres: genres,
      isInWatchlist: isInWatchlist ?? this.isInWatchlist,
      cast: cast,
    );
  }

  factory TvSeriesSummary.fromJson(Map<String, dynamic> json) {
    final rawSeasons = json['seasons'] as List<dynamic>? ?? const [];
    final rawGenres = json['genres'] as List<dynamic>? ?? const [];
    final rawCast = json['cast'] as List<dynamic>? ?? const [];
    final rawAdded = json['addedAtUtc'] as String?;

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
      addedAtUtc: rawAdded != null && !rawAdded.startsWith('0001-')
          ? DateTime.tryParse(rawAdded)
          : null,
      rating: (json['rating'] as num?)?.toDouble(),
      genres: rawGenres.map((g) => g.toString()).toList(),
      isInWatchlist: json['isInWatchlist'] as bool? ?? false,
      cast: rawCast
          .map((c) => CastMemberModel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

bool isAddedRecently(DateTime? addedAtUtc) {
  if (addedAtUtc == null) return false;
  return DateTime.now().toUtc().difference(addedAtUtc.toUtc()).inDays <= 7;
}

String formatCinemaMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
}

class CustomListItemModel {
  const CustomListItemModel({
    required this.id,
    this.movieId,
    this.tvSeriesId,
    required this.mediaKind,
    required this.title,
    this.year,
    this.artworkHash,
    this.rating,
    required this.position,
    required this.addedAtUtc,
  });

  final String id;
  final String? movieId;
  final String? tvSeriesId;
  final String mediaKind;
  final String title;
  final int? year;
  final String? artworkHash;
  final double? rating;
  final int position;
  final DateTime addedAtUtc;

  bool get isMovie => mediaKind == 'movie' || movieId != null;

  factory CustomListItemModel.fromJson(Map<String, dynamic> json) {
    return CustomListItemModel(
      id: json['id'] as String? ?? '',
      movieId: json['movieId'] as String?,
      tvSeriesId: json['tvSeriesId'] as String?,
      mediaKind: json['mediaKind'] as String? ?? 'movie',
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      artworkHash: json['artworkHash'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      position: json['position'] as int? ?? 0,
      addedAtUtc: DateTime.parse(json['addedAtUtc'] as String),
    );
  }
}

class CustomListModel {
  const CustomListModel({
    required this.id,
    required this.name,
    this.description,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.items = const [],
  });

  final String id;
  final String name;
  final String? description;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final List<CustomListItemModel> items;

  factory CustomListModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return CustomListModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
      items: rawItems
          .map((e) => CustomListItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

const List<Color> _titleTintPalette = [
  Color(0xFFDC143C),
  Color(0xFF5B8CFF),
  Color(0xFF3DD68C),
  Color(0xFFA678FF),
  Color(0xFFF2A93B),
  Color(0xFF38BDF8),
  Color(0xFFF472B6),
];

/// Derives a consistent title accent tint from the title string when
/// artwork palette extraction is unavailable.
Color deriveTitleTint(String title) {
  if (title.isEmpty) return _titleTintPalette.first;
  var hash = 0;
  for (final code in title.codeUnits) {
    hash = (hash * 31 + code) & 0x7FFFFFFF;
  }
  return _titleTintPalette[hash % _titleTintPalette.length];
}

enum CinemaMobileTab { home, search, library }

class CinemaNavigationController {
  CinemaNavigationController({
    this.onSelectMobileTab,
    this.onHandleBack,
    this.onOpenMovie,
    this.onOpenSeries,
  });

  final ValueNotifier<CinemaMobileTab> mobileTabNotifier =
      ValueNotifier<CinemaMobileTab>(CinemaMobileTab.home);

  void Function(CinemaMobileTab tab)? onSelectMobileTab;
  bool Function()? onHandleBack;
  void Function(String movieId)? onOpenMovie;
  void Function(String seriesId)? onOpenSeries;
  String? _pendingMovieId;
  String? _pendingSeriesId;

  void selectMobileTab(CinemaMobileTab tab) {
    mobileTabNotifier.value = tab;
    onSelectMobileTab?.call(tab);
  }

  void openMovie(String movieId) {
    if (onOpenMovie != null) {
      _pendingMovieId = null;
      _pendingSeriesId = null;
      onOpenMovie!(movieId);
    } else {
      _pendingMovieId = movieId;
      _pendingSeriesId = null;
    }
  }

  void openSeries(String seriesId) {
    if (onOpenSeries != null) {
      _pendingMovieId = null;
      _pendingSeriesId = null;
      onOpenSeries!(seriesId);
    } else {
      _pendingSeriesId = seriesId;
      _pendingMovieId = null;
    }
  }

  ({String? movieId, String? seriesId}) takePendingSelection() {
    final res = (movieId: _pendingMovieId, seriesId: _pendingSeriesId);
    _pendingMovieId = null;
    _pendingSeriesId = null;
    return res;
  }

  bool handleBack() => onHandleBack?.call() ?? false;

  void dispose() {
    mobileTabNotifier.dispose();
  }
}
