class LibraryRootModel {
  const LibraryRootModel({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.rootPath,
    required this.watchEnabled,
    required this.createdAtUtc,
    this.lastScanCompletedAtUtc,
  });

  final String id;
  final String name;
  final int mediaType;
  final String rootPath;
  final bool watchEnabled;
  final DateTime createdAtUtc;
  final DateTime? lastScanCompletedAtUtc;

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
