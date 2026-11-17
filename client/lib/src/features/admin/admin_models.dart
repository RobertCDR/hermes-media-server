String formatStorageBytes(int bytes, {bool treatZeroAsDash = false}) {
  if (bytes < 0 || (treatZeroAsDash && bytes == 0)) return '—';
  if (bytes < 1000) return '$bytes B';
  if (bytes >= 1000000000000) {
    return '${(bytes / 1000000000000).toStringAsFixed(1)} TB';
  }
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1000000) {
    return '${(bytes / 1000000).toStringAsFixed(0)} MB';
  }
  return '${(bytes / 1000).round()} KB';
}

enum HardwareAccelerationMode {
  none(0, 'None (Software x264)'),
  auto(1, 'Auto'),
  nvenc(2, 'NVIDIA NVENC'),
  vaapi(3, 'VA-API (Linux GPU)'),
  qsv(4, 'Intel Quick Sync'),
  videoToolbox(5, 'Apple VideoToolbox');

  const HardwareAccelerationMode(this.wireValue, this.label);

  final int wireValue;
  final String label;

  static HardwareAccelerationMode fromJson(Object? raw) {
    if (raw is num) {
      final intVal = raw.toInt();
      for (final mode in values) {
        if (mode.wireValue == intVal) return mode;
      }
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      return switch (normalized) {
        'auto' || '1' => HardwareAccelerationMode.auto,
        'nvenc' || 'cuda' || '2' => HardwareAccelerationMode.nvenc,
        'vaapi' || '3' => HardwareAccelerationMode.vaapi,
        'qsv' || '4' => HardwareAccelerationMode.qsv,
        'videotoolbox' || '5' => HardwareAccelerationMode.videoToolbox,
        _ => HardwareAccelerationMode.none,
      };
    }
    return HardwareAccelerationMode.none;
  }
}

class ServerSettingsModel {
  const ServerSettingsModel({
    required this.serverId,
    required this.serverName,
    required this.transcodingEnabled,
    required this.maxConcurrentVideoTranscodes,
    required this.maxConcurrentAudioTranscodes,
    this.maxRemoteVideoBitrateBps,
    required this.hardwareAccelerationMode,
    required this.updatedAtUtc,
    this.totalMediaSizeBytes = 0,
    this.libraryCount = 0,
    this.totalMovies = 0,
    this.totalSeries = 0,
    this.totalEpisodes = 0,
    this.totalSongs = 0,
  });

  final String serverId;
  final String serverName;
  final bool transcodingEnabled;
  final int maxConcurrentVideoTranscodes;
  final int maxConcurrentAudioTranscodes;
  final int? maxRemoteVideoBitrateBps;
  final HardwareAccelerationMode hardwareAccelerationMode;
  final DateTime updatedAtUtc;
  final int totalMediaSizeBytes;
  final int libraryCount;
  final int totalMovies;
  final int totalSeries;
  final int totalEpisodes;
  final int totalSongs;

  String get formattedTotalMediaSize => formatStorageBytes(totalMediaSizeBytes);

  factory ServerSettingsModel.fromJson(Map<String, dynamic> json) {
    final updatedRaw = json['updatedAtUtc'] as String?;
    return ServerSettingsModel(
      serverId: json['serverId'] as String? ?? '',
      serverName: json['serverName'] as String? ?? 'Hermes Media Server',
      transcodingEnabled: json['transcodingEnabled'] as bool? ?? true,
      maxConcurrentVideoTranscodes: (json['maxConcurrentVideoTranscodes'] as num?)?.toInt() ?? 2,
      maxConcurrentAudioTranscodes: (json['maxConcurrentAudioTranscodes'] as num?)?.toInt() ?? 4,
      maxRemoteVideoBitrateBps: (json['maxRemoteVideoBitrateBps'] as num?)?.toInt(),
      hardwareAccelerationMode: HardwareAccelerationMode.fromJson(json['hardwareAccelerationMode']),
      updatedAtUtc: updatedRaw == null ? DateTime.now().toUtc() : DateTime.parse(updatedRaw),
      totalMediaSizeBytes: (json['totalMediaSizeBytes'] as num?)?.toInt() ?? 0,
      libraryCount: (json['libraryCount'] as num?)?.toInt() ?? 0,
      totalMovies: (json['totalMovies'] as num?)?.toInt() ?? 0,
      totalSeries: (json['totalSeries'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt() ?? 0,
      totalSongs: (json['totalSongs'] as num?)?.toInt() ?? 0,
    );
  }
}

class UpdateServerSettingsInput {
  const UpdateServerSettingsInput({
    required this.serverName,
    required this.transcodingEnabled,
    required this.maxConcurrentVideoTranscodes,
    required this.maxConcurrentAudioTranscodes,
    this.maxRemoteVideoBitrateBps,
    required this.hardwareAccelerationMode,
  });

  final String serverName;
  final bool transcodingEnabled;
  final int maxConcurrentVideoTranscodes;
  final int maxConcurrentAudioTranscodes;
  final int? maxRemoteVideoBitrateBps;
  final HardwareAccelerationMode hardwareAccelerationMode;

  Map<String, dynamic> toJson() => {
        'serverName': serverName,
        'transcodingEnabled': transcodingEnabled,
        'maxConcurrentVideoTranscodes': maxConcurrentVideoTranscodes,
        'maxConcurrentAudioTranscodes': maxConcurrentAudioTranscodes,
        'maxRemoteVideoBitrateBps': maxRemoteVideoBitrateBps,
        'hardwareAccelerationMode': hardwareAccelerationMode.wireValue,
      };
}

class LibraryRootModel {
  const LibraryRootModel({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.rootPath,
    required this.watchEnabled,
    this.fetchMetadata = true,
    required this.createdAtUtc,
    this.lastScanCompletedAtUtc,
    this.itemCount = 0,
    this.hasReportedCount = true,
    this.totalSizeBytes = 0,
    this.isScanning = false,
    this.scanProcessedFiles = 0,
    this.scanTotalFiles = 0,
  });

  final String id;
  final String name;
  final int mediaType;
  final String rootPath;
  final bool watchEnabled;
  final bool fetchMetadata;
  final DateTime createdAtUtc;
  final DateTime? lastScanCompletedAtUtc;
  final int itemCount;
  final bool hasReportedCount;
  final int totalSizeBytes;
  final bool isScanning;
  final int scanProcessedFiles;
  final int scanTotalFiles;

  LibraryRootModel copyWith({
    String? id,
    String? name,
    int? mediaType,
    String? rootPath,
    bool? watchEnabled,
    bool? fetchMetadata,
    DateTime? createdAtUtc,
    DateTime? lastScanCompletedAtUtc,
    int? itemCount,
    bool? hasReportedCount,
    int? totalSizeBytes,
    bool? isScanning,
    int? scanProcessedFiles,
    int? scanTotalFiles,
  }) {
    return LibraryRootModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mediaType: mediaType ?? this.mediaType,
      rootPath: rootPath ?? this.rootPath,
      watchEnabled: watchEnabled ?? this.watchEnabled,
      fetchMetadata: fetchMetadata ?? this.fetchMetadata,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      lastScanCompletedAtUtc: lastScanCompletedAtUtc ?? this.lastScanCompletedAtUtc,
      itemCount: itemCount ?? this.itemCount,
      hasReportedCount: hasReportedCount ?? this.hasReportedCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      isScanning: isScanning ?? this.isScanning,
      scanProcessedFiles: scanProcessedFiles ?? this.scanProcessedFiles,
      scanTotalFiles: scanTotalFiles ?? this.scanTotalFiles,
    );
  }

  String get contentsLabel {
    if (isScanning && itemCount == 0) {
      return 'Scanning…';
    }
    if (lastScanCompletedAtUtc == null && itemCount == 0 && !isScanning) {
      return 'Not scanned yet';
    }
    if (!hasReportedCount) {
      return 'Scanned';
    }
    return switch (mediaType) {
      0 => '$itemCount ${itemCount == 1 ? 'movie' : 'movies'}',
      1 => '$itemCount ${itemCount == 1 ? 'series' : 'series'}',
      _ => '$itemCount ${itemCount == 1 ? 'track' : 'tracks'}',
    };
  }

  String get formattedSize {
    if (totalSizeBytes <= 0) return '—';
    return formatStorageBytes(totalSizeBytes);
  }

  static int _parseMediaType(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) {
      return switch (raw.trim().toLowerCase()) {
        'movies' || 'movie' || '0' => 0,
        'series' || 'tv' || 'shows' || '1' => 1,
        'music' || 'audio' || '2' => 2,
        _ => int.tryParse(raw.trim()) ?? 0,
      };
    }
    return 0;
  }

  factory LibraryRootModel.fromJson(Map<String, dynamic> json) {
    final lastScan = json['lastScanCompletedAtUtc'] as String?;
    final rawItemCount = json['itemCount'];
    final hasCount = rawItemCount is num;
    return LibraryRootModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      mediaType: _parseMediaType(json['mediaType']),
      rootPath: json['rootPath'] as String? ?? '',
      watchEnabled: json['watchEnabled'] as bool? ?? true,
      fetchMetadata: json['fetchMetadata'] as bool? ?? true,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      lastScanCompletedAtUtc: lastScan == null ? null : DateTime.parse(lastScan),
      itemCount: hasCount ? rawItemCount.toInt() : 0,
      hasReportedCount: hasCount,
      totalSizeBytes: (json['totalSizeBytes'] as num?)?.toInt() ?? 0,
      isScanning: json['isScanning'] as bool? ?? false,
      scanProcessedFiles: (json['scanProcessedFiles'] as num?)?.toInt() ?? 0,
      scanTotalFiles: (json['scanTotalFiles'] as num?)?.toInt() ?? 0,
    );
  }
}

class LibraryScanSummaryModel {
  const LibraryScanSummaryModel({
    required this.libraryRootId,
    required this.filesDiscovered,
    required this.sourcesUpserted,
    required this.sourcesMarkedMissing,
    required this.completedAtUtc,
  });

  final String libraryRootId;
  final int filesDiscovered;
  final int sourcesUpserted;
  final int sourcesMarkedMissing;
  final DateTime completedAtUtc;

  factory LibraryScanSummaryModel.fromJson(Map<String, dynamic> json) {
    return LibraryScanSummaryModel(
      libraryRootId: json['libraryRootId'] as String,
      filesDiscovered: json['filesDiscovered'] as int? ?? 0,
      sourcesUpserted: json['sourcesUpserted'] as int? ?? 0,
      sourcesMarkedMissing: json['sourcesMarkedMissing'] as int? ?? 0,
      completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
    );
  }
}

class InviteModel {
  const InviteModel({
    required this.id,
    required this.code,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAtUtc,
    required this.isRevoked,
  });

  final String id;
  final String code;
  final int maxUses;
  final int usedCount;
  final DateTime expiresAtUtc;
  final bool isRevoked;

  factory InviteModel.fromJson(Map<String, dynamic> json) {
    return InviteModel(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      maxUses: json['maxUses'] as int? ?? 1,
      usedCount: json['usedCount'] as int? ?? 0,
      expiresAtUtc: DateTime.parse(json['expiresAtUtc'] as String),
      isRevoked: json['isRevoked'] as bool? ?? false,
    );
  }
}

class UserSummaryModel {
  const UserSummaryModel({
    required this.id,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAtUtc,
  });

  final String id;
  final String username;
  final String role;
  final bool isActive;
  final DateTime createdAtUtc;

  factory UserSummaryModel.fromJson(Map<String, dynamic> json) {
    return UserSummaryModel(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? 'Member',
      isActive: json['isActive'] as bool? ?? true,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
    );
  }
}

class ResetCodeModel {
  const ResetCodeModel({
    required this.resetCode,
    required this.expiresAtUtc,
  });

  final String resetCode;
  final DateTime expiresAtUtc;

  factory ResetCodeModel.fromJson(Map<String, dynamic> json) {
    return ResetCodeModel(
      resetCode: json['resetCode'] as String,
      expiresAtUtc: DateTime.parse(json['expiresAtUtc'] as String),
    );
  }
}

class IdentifyMediaResult {
  const IdentifyMediaResult({
    required this.id,
    required this.tmdbId,
    required this.title,
    this.year,
    required this.isMetadataLocked,
  });

  final String id;
  final int tmdbId;
  final String title;
  final int? year;
  final bool isMetadataLocked;

  factory IdentifyMediaResult.fromJson(Map<String, dynamic> json) {
    return IdentifyMediaResult(
      id: json['id'] as String,
      tmdbId: json['tmdbId'] as int,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      isMetadataLocked: json['isMetadataLocked'] as bool? ?? true,
    );
  }
}

class ActiveStreamSessionModel {
  const ActiveStreamSessionModel({
    required this.sessionId,
    required this.kind,
    required this.userId,
    required this.username,
    required this.deviceName,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.mode,
    required this.bitrate,
    required this.isPaused,
    required this.canStop,
    this.artworkHash,
  });

  final String sessionId;
  final String kind;
  final String userId;
  final String username;
  final String deviceName;
  final String title;
  final String subtitle;
  final double progress;
  final String mode;
  final String bitrate;
  final bool isPaused;
  final bool canStop;
  final String? artworkHash;

  bool get isMusic => kind == 'music';

  factory ActiveStreamSessionModel.fromJson(Map<String, dynamic> json) {
    return ActiveStreamSessionModel(
      sessionId: json['sessionId'] as String? ?? '',
      kind: json['kind'] as String? ?? 'video',
      userId: json['userId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Client',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      progress: ((json['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      mode: json['mode'] as String? ?? 'Direct Play',
      bitrate: json['bitrate'] as String? ?? '',
      isPaused: json['isPaused'] as bool? ?? false,
      canStop: json['canStop'] as bool? ?? true,
      artworkHash: json['artworkHash'] as String?,
    );
  }
}

class UnmatchedMediaModel {
  const UnmatchedMediaModel({
    required this.id,
    required this.mediaType,
    required this.title,
    this.year,
    required this.libraryName,
    required this.filePath,
  });

  final String id;
  final int mediaType;
  final String title;
  final int? year;
  final String libraryName;
  final String filePath;

  factory UnmatchedMediaModel.fromJson(Map<String, dynamic> json) {
    return UnmatchedMediaModel(
      id: json['id'] as String,
      mediaType: json['mediaType'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      libraryName: json['libraryName'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
    );
  }
}

class TmdbCandidateModel {
  const TmdbCandidateModel({
    required this.tmdbId,
    required this.title,
    this.year,
    this.overview,
  });

  final int tmdbId;
  final String title;
  final int? year;
  final String? overview;

  factory TmdbCandidateModel.fromJson(Map<String, dynamic> json) {
    return TmdbCandidateModel(
      tmdbId: json['tmdbId'] as int,
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      overview: json['overview'] as String?,
    );
  }
}
