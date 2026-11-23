import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MusicSearchHistoryKind { query, song, album, artist, playlist }

class MusicSearchHistoryItem {
  const MusicSearchHistoryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.artworkHash,
    this.targetId,
    required this.timestampMs,
  });

  final String id;
  final MusicSearchHistoryKind kind;
  final String title;
  final String subtitle;
  final String? artworkHash;
  final String? targetId;
  final int timestampMs;

  String get dedupKey {
    if (kind == MusicSearchHistoryKind.query) {
      return 'query:${title.trim().toLowerCase()}';
    }
    final target = (targetId ?? id).trim();
    return '${kind.name}:$target';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'subtitle': subtitle,
      'artworkHash': artworkHash,
      'targetId': targetId,
      'timestampMs': timestampMs,
    };
  }

  factory MusicSearchHistoryItem.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'query';
    final kind = MusicSearchHistoryKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => MusicSearchHistoryKind.query,
    );
    return MusicSearchHistoryItem(
      id: json['id'] as String? ?? '',
      kind: kind,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      artworkHash: json['artworkHash'] as String?,
      targetId: json['targetId'] as String?,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract interface class SearchHistoryStore {
  Future<List<MusicSearchHistoryItem>> loadMusicHistory();
  Future<List<MusicSearchHistoryItem>> addMusicItem(MusicSearchHistoryItem item);
  Future<List<MusicSearchHistoryItem>> removeMusicItem(String id);
  Future<void> clearMusicHistory();

  Future<List<String>> loadCinemaHistory();
  Future<List<String>> addCinemaQuery(String query);
  Future<List<String>> removeCinemaQuery(String query);
  Future<void> clearCinemaHistory();
}

class SharedPrefsSearchHistoryStore implements SearchHistoryStore {
  static const String _musicKey = 'hermes.search_history.music.v1';
  static const String _cinemaKey = 'hermes.search_history.cinema.v1';
  static const int maxItems = 20;

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MusicSearchHistoryItem>> loadMusicHistory() async {
    final prefs = await _prefsOrNull();
    final raw = prefs?.getString(_musicKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MusicSearchHistoryItem.fromJson)
          .where((item) => item.title.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<MusicSearchHistoryItem>> _saveMusicHistory(
    List<MusicSearchHistoryItem> items,
  ) async {
    final trimmed = items.take(maxItems).toList(growable: false);
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      try {
        await prefs.setString(
          _musicKey,
          jsonEncode(trimmed.map((e) => e.toJson()).toList(growable: false)),
        );
      } catch (_) {}
    }
    return trimmed;
  }

  @override
  Future<List<MusicSearchHistoryItem>> addMusicItem(
    MusicSearchHistoryItem item,
  ) async {
    if (item.title.trim().isEmpty) {
      return loadMusicHistory();
    }
    final current = await loadMusicHistory();
    final key = item.dedupKey;
    final next = [
      item,
      ...current.where((e) => e.dedupKey != key && e.id != item.id),
    ];
    return _saveMusicHistory(next);
  }

  @override
  Future<List<MusicSearchHistoryItem>> removeMusicItem(String id) async {
    final current = await loadMusicHistory();
    final next = current.where((e) => e.id != id).toList(growable: false);
    return _saveMusicHistory(next);
  }

  @override
  Future<void> clearMusicHistory() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    try {
      await prefs.remove(_musicKey);
    } catch (_) {}
  }

  @override
  Future<List<String>> loadCinemaHistory() async {
    final prefs = await _prefsOrNull();
    final raw = prefs?.getStringList(_cinemaKey);
    if (raw == null) return const [];
    return raw.where((q) => q.trim().isNotEmpty).toList(growable: false);
  }

  Future<List<String>> _saveCinemaHistory(List<String> queries) async {
    final trimmed = queries.take(maxItems).toList(growable: false);
    final prefs = await _prefsOrNull();
    if (prefs != null) {
      try {
        await prefs.setStringList(_cinemaKey, trimmed);
      } catch (_) {}
    }
    return trimmed;
  }

  @override
  Future<List<String>> addCinemaQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return loadCinemaHistory();
    }
    final lower = clean.toLowerCase();
    final current = await loadCinemaHistory();
    final next = [
      clean,
      ...current.where((e) => e.trim().toLowerCase() != lower),
    ];
    return _saveCinemaHistory(next);
  }

  @override
  Future<List<String>> removeCinemaQuery(String query) async {
    final lower = query.trim().toLowerCase();
    final current = await loadCinemaHistory();
    final next = current
        .where((e) => e.trim().toLowerCase() != lower)
        .toList(growable: false);
    return _saveCinemaHistory(next);
  }

  @override
  Future<void> clearCinemaHistory() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    try {
      await prefs.remove(_cinemaKey);
    } catch (_) {}
  }
}

class InMemorySearchHistoryStore implements SearchHistoryStore {
  InMemorySearchHistoryStore({
    List<MusicSearchHistoryItem> initialMusic = const [],
    List<String> initialCinema = const [],
  })  : _music = List<MusicSearchHistoryItem>.from(initialMusic),
        _cinema = List<String>.from(initialCinema);

  static const int maxItems = 20;

  List<MusicSearchHistoryItem> _music;
  List<String> _cinema;

  @override
  Future<List<MusicSearchHistoryItem>> loadMusicHistory() async =>
      List<MusicSearchHistoryItem>.unmodifiable(_music);

  @override
  Future<List<MusicSearchHistoryItem>> addMusicItem(
    MusicSearchHistoryItem item,
  ) async {
    if (item.title.trim().isEmpty) return loadMusicHistory();
    final key = item.dedupKey;
    _music = [
      item,
      ..._music.where((e) => e.dedupKey != key && e.id != item.id),
    ].take(maxItems).toList(growable: false);
    return loadMusicHistory();
  }

  @override
  Future<List<MusicSearchHistoryItem>> removeMusicItem(String id) async {
    _music = _music.where((e) => e.id != id).toList(growable: false);
    return loadMusicHistory();
  }

  @override
  Future<void> clearMusicHistory() async {
    _music = const [];
  }

  @override
  Future<List<String>> loadCinemaHistory() async =>
      List<String>.unmodifiable(_cinema);

  @override
  Future<List<String>> addCinemaQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return loadCinemaHistory();
    final lower = clean.toLowerCase();
    _cinema = [
      clean,
      ..._cinema.where((e) => e.trim().toLowerCase() != lower),
    ].take(maxItems).toList(growable: false);
    return loadCinemaHistory();
  }

  @override
  Future<List<String>> removeCinemaQuery(String query) async {
    final lower = query.trim().toLowerCase();
    _cinema = _cinema
        .where((e) => e.trim().toLowerCase() != lower)
        .toList(growable: false);
    return loadCinemaHistory();
  }

  @override
  Future<void> clearCinemaHistory() async {
    _cinema = const [];
  }
}
