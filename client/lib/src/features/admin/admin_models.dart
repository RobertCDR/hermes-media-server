class LibraryRootModel {
  const LibraryRootModel({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.rootPath,
    required this.watchEnabled,
    required this.createdAtUtc,
    this.lastScanCompletedAtUtc,
    this.itemCount = 0,
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
  final DateTime createdAtUtc;
  final DateTime? lastScanCompletedAtUtc;
  final int itemCount;
  final int totalSizeBytes;
  final bool isScanning;
  final int scanProcessedFiles;
  final int scanTotalFiles;

  String get contentsLabel {
    if (lastScanCompletedAtUtc == null && itemCount == 0 && !isScanning) {
      return 'Not scanned yet';
    }
    return switch (mediaType) {
      0 => '$itemCount ${itemCount == 1 ? 'movie' : 'movies'}',
      1 => '$itemCount ${itemCount == 1 ? 'series' : 'series'}',
      _ => '$itemCount ${itemCount == 1 ? 'track' : 'tracks'}',
    };
  }

  String get formattedSize {
    if (totalSizeBytes <= 0) return '—';
    if (totalSizeBytes >= 1000000000000) {
      return '${(totalSizeBytes / 1000000000000).toStringAsFixed(1)} TB';
    }
    if (totalSizeBytes >= 1000000000) {
      return '${(totalSizeBytes / 1000000000).toStringAsFixed(1)} GB';
    }
    if (totalSizeBytes >= 1000000) {
      return '${(totalSizeBytes / 1000000).toStringAsFixed(0)} MB';
    }
    return '${(totalSizeBytes / 1000).round()} KB';
  }

  factory LibraryRootModel.fromJson(Map<String, dynamic> json) {
    final lastScan = json['lastScanCompletedAtUtc'] as String?;
    return LibraryRootModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      mediaType: json['mediaType'] as int? ?? 0,
      rootPath: json['rootPath'] as String? ?? '',
      watchEnabled: json['watchEnabled'] as bool? ?? true,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      lastScanCompletedAtUtc: lastScan == null ? null : DateTime.parse(lastScan),
      itemCount: json['itemCount'] as int? ?? 0,
      totalSizeBytes: (json['totalSizeBytes'] as num?)?.toInt() ?? 0,
      isScanning: json['isScanning'] as bool? ?? false,
      scanProcessedFiles: json['scanProcessedFiles'] as int? ?? 0,
      scanTotalFiles: json['scanTotalFiles'] as int? ?? 0,
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
