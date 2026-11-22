import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/cinema/cinema_models.dart';
import '../../features/cinema/hermes_video_player.dart';
import '../../features/music/music_models.dart';
import '../theme/hermes_theme_tokens.dart';

enum HermesTextSize {
  standard('default', 'Default', 1.0),
  large('large', 'Large', 1.1),
  larger('larger', 'Larger', 1.2);

  const HermesTextSize(this.id, this.label, this.scaleFactor);

  final String id;
  final String label;
  final double scaleFactor;

  static HermesTextSize fromId(String? value) {
    return HermesTextSize.values.firstWhere(
      (item) => item.id == value,
      orElse: () => HermesTextSize.standard,
    );
  }
}

enum SubtitleSizePreset {
  small('small', 'Small', 14.0, 20.0),
  medium('medium', 'Medium', 18.0, 26.0),
  large('large', 'Large', 24.0, 34.0),
  xl('xl', 'Extra large', 29.0, 42.0);

  const SubtitleSizePreset(
    this.apiValue,
    this.label,
    this.previewFontSize,
    this.playerFontSize,
  );

  final String apiValue;
  final String label;
  final double previewFontSize;
  final double playerFontSize;

  static SubtitleSizePreset fromApiValue(String? value) {
    return SubtitleSizePreset.values.firstWhere(
      (item) => item.apiValue.toLowerCase() == value?.toLowerCase(),
      orElse: () => SubtitleSizePreset.medium,
    );
  }
}

enum SubtitleBackgroundStyle {
  none('none', 'None'),
  shadow('shadow', 'Shadow'),
  box('box', 'Box');

  const SubtitleBackgroundStyle(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static SubtitleBackgroundStyle fromApiValue(String? value) {
    return SubtitleBackgroundStyle.values.firstWhere(
      (item) => item.apiValue.toLowerCase() == value?.toLowerCase(),
      orElse: () => SubtitleBackgroundStyle.shadow,
    );
  }
}

class HermesDevicePreferences {
  const HermesDevicePreferences({
    this.themeId = HermesThemeId.crimson,
    this.pureBlack = false,
    this.textSize = HermesTextSize.standard,
    this.reduceMotion = false,
    this.defaultVideoQuality = VideoQualityPreset.directPlay,
    this.rendererBackend = VideoRendererBackend.openGl,
    this.wifiAudioPreset = AudioQualityPreset.lossless,
    this.cellularAudioPreset = AudioQualityPreset.high160,
    this.cacheCapMb = 512,
    this.closeToTray = true,
    this.showMediaFlyout = true,
  });

  final HermesThemeId themeId;
  final bool pureBlack;
  final HermesTextSize textSize;
  final bool reduceMotion;
  final VideoQualityPreset defaultVideoQuality;
  final VideoRendererBackend rendererBackend;
  final AudioQualityPreset wifiAudioPreset;
  final AudioQualityPreset cellularAudioPreset;
  final int cacheCapMb;
  final bool closeToTray;
  final bool showMediaFlyout;

  HermesThemeTokens toThemeTokens() {
    return HermesThemeTokens.resolve(
      themeId: themeId,
      pureBlack: pureBlack,
    );
  }

  AudioQualityPolicy toAudioQualityPolicy() {
    return AudioQualityPolicy(
      wifiPreset: wifiAudioPreset,
      cellularPreset: cellularAudioPreset,
    );
  }

  HermesDevicePreferences copyWith({
    HermesThemeId? themeId,
    bool? pureBlack,
    HermesTextSize? textSize,
    bool? reduceMotion,
    VideoQualityPreset? defaultVideoQuality,
    VideoRendererBackend? rendererBackend,
    AudioQualityPreset? wifiAudioPreset,
    AudioQualityPreset? cellularAudioPreset,
    int? cacheCapMb,
    bool? closeToTray,
    bool? showMediaFlyout,
  }) {
    return HermesDevicePreferences(
      themeId: themeId ?? this.themeId,
      pureBlack: pureBlack ?? this.pureBlack,
      textSize: textSize ?? this.textSize,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      defaultVideoQuality: defaultVideoQuality ?? this.defaultVideoQuality,
      rendererBackend: rendererBackend ?? this.rendererBackend,
      wifiAudioPreset: wifiAudioPreset ?? this.wifiAudioPreset,
      cellularAudioPreset: cellularAudioPreset ?? this.cellularAudioPreset,
      cacheCapMb: cacheCapMb ?? this.cacheCapMb,
      closeToTray: closeToTray ?? this.closeToTray,
      showMediaFlyout: showMediaFlyout ?? this.showMediaFlyout,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeId': themeId.id,
      'pureBlack': pureBlack,
      'textSize': textSize.id,
      'reduceMotion': reduceMotion,
      'defaultVideoQuality': defaultVideoQuality.apiValue,
      'rendererBackend': rendererBackend.name,
      'wifiAudioPreset': wifiAudioPreset.apiValue,
      'cellularAudioPreset': cellularAudioPreset.apiValue,
      'cacheCapMb': cacheCapMb,
      'closeToTray': closeToTray,
      'showMediaFlyout': showMediaFlyout,
    };
  }

  factory HermesDevicePreferences.fromJson(Map<String, dynamic> json) {
    final qualityValue = json['defaultVideoQuality'] as String?;
    final rendererName = json['rendererBackend'] as String?;
    final wifiValue = json['wifiAudioPreset'] as String?;
    final cellValue = json['cellularAudioPreset'] as String?;
    final rawCacheMb = (json['cacheCapMb'] as num?)?.toInt() ?? 512;

    return HermesDevicePreferences(
      themeId: HermesThemeId.fromId(json['themeId'] as String?),
      pureBlack: json['pureBlack'] as bool? ?? false,
      textSize: HermesTextSize.fromId(json['textSize'] as String?),
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      defaultVideoQuality: VideoQualityPreset.values.firstWhere(
        (q) => q.apiValue == qualityValue,
        orElse: () => VideoQualityPreset.directPlay,
      ),
      rendererBackend: VideoRendererBackend.values.firstWhere(
        (r) => r.name == rendererName,
        orElse: () => VideoRendererBackend.openGl,
      ),
      wifiAudioPreset: AudioQualityPreset.values.firstWhere(
        (a) => a.apiValue == wifiValue,
        orElse: () => AudioQualityPreset.lossless,
      ),
      cellularAudioPreset: AudioQualityPreset.values.firstWhere(
        (a) => a.apiValue == cellValue,
        orElse: () => AudioQualityPreset.high160,
      ),
      cacheCapMb: rawCacheMb.clamp(128, 10240),
      closeToTray: json['closeToTray'] as bool? ?? true,
      showMediaFlyout: json['showMediaFlyout'] as bool? ?? true,
    );
  }
}

class HermesAccountPreferences {
  const HermesAccountPreferences({
    this.autoplayNextEpisode = true,
    this.normalizeVolume = false,
    this.matchTitleColors = true,
    this.subtitleSize = SubtitleSizePreset.medium,
    this.subtitleBackground = SubtitleBackgroundStyle.shadow,
  });

  final bool autoplayNextEpisode;
  final bool normalizeVolume;
  final bool matchTitleColors;
  final SubtitleSizePreset subtitleSize;
  final SubtitleBackgroundStyle subtitleBackground;

  HermesAccountPreferences copyWith({
    bool? autoplayNextEpisode,
    bool? normalizeVolume,
    bool? matchTitleColors,
    SubtitleSizePreset? subtitleSize,
    SubtitleBackgroundStyle? subtitleBackground,
  }) {
    return HermesAccountPreferences(
      autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
      normalizeVolume: normalizeVolume ?? this.normalizeVolume,
      matchTitleColors: matchTitleColors ?? this.matchTitleColors,
      subtitleSize: subtitleSize ?? this.subtitleSize,
      subtitleBackground: subtitleBackground ?? this.subtitleBackground,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoplayNextEpisode': autoplayNextEpisode,
      'normalizeVolume': normalizeVolume,
      'matchTitleColors': matchTitleColors,
      'subtitleSize': subtitleSize.apiValue,
      'subtitleBackground': subtitleBackground.apiValue,
    };
  }

  factory HermesAccountPreferences.fromJson(Map<String, dynamic> json) {
    return HermesAccountPreferences(
      autoplayNextEpisode: json['autoplayNextEpisode'] as bool? ?? true,
      normalizeVolume: json['normalizeVolume'] as bool? ?? false,
      matchTitleColors: json['matchTitleColors'] as bool? ?? true,
      subtitleSize: SubtitleSizePreset.fromApiValue(
        json['subtitleSize'] as String?,
      ),
      subtitleBackground: SubtitleBackgroundStyle.fromApiValue(
        json['subtitleBackground'] as String?,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HermesAccountPreferences &&
            other.autoplayNextEpisode == autoplayNextEpisode &&
            other.normalizeVolume == normalizeVolume &&
            other.matchTitleColors == matchTitleColors &&
            other.subtitleSize == subtitleSize &&
            other.subtitleBackground == subtitleBackground;
  }

  @override
  int get hashCode => Object.hash(
        autoplayNextEpisode,
        normalizeVolume,
        matchTitleColors,
        subtitleSize,
        subtitleBackground,
      );
}

class AccountPreferencesService {
  AccountPreferencesService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<HermesAccountPreferences> fetch({
    required String baseUrl,
    required String accessToken,
  }) async {
    final uri = Uri.parse('${_normalizeBase(baseUrl)}/api/v1/auth/me/preferences');
    final response = await _http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Failed to load account preferences (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return HermesAccountPreferences.fromJson(json);
  }

  Future<HermesAccountPreferences> save({
    required String baseUrl,
    required String accessToken,
    required HermesAccountPreferences preferences,
  }) async {
    final uri = Uri.parse('${_normalizeBase(baseUrl)}/api/v1/auth/me/preferences');
    final response = await _http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(preferences.toJson()),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Failed to save account preferences (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return HermesAccountPreferences.fromJson(json);
  }

  String _normalizeBase(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

abstract interface class DevicePreferencesStore {
  Future<HermesDevicePreferences> load();
  Future<void> save(HermesDevicePreferences preferences);
  Future<String> getOrCreateDeviceId(String platformTag);
}

class InMemoryDevicePreferencesStore implements DevicePreferencesStore {
  HermesDevicePreferences _prefs = const HermesDevicePreferences();
  String? _deviceId;

  @override
  Future<HermesDevicePreferences> load() async => _prefs;

  @override
  Future<void> save(HermesDevicePreferences preferences) async {
    _prefs = preferences;
  }

  @override
  Future<String> getOrCreateDeviceId(String platformTag) async {
    return _deviceId ??= _generateDeviceId(platformTag);
  }
}

/// Persists device appearance, player preferences, and stable per-install device ID.
class SharedPrefsDevicePreferencesStore implements DevicePreferencesStore {
  static const _prefsKey = 'hermes.device_prefs.v1';
  static const _deviceIdKey = 'hermes.device_id.v1';

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<HermesDevicePreferences> load() async {
    final prefs = await _prefsOrNull();
    final raw = prefs?.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const HermesDevicePreferences();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const HermesDevicePreferences();
      }
      return HermesDevicePreferences.fromJson(decoded);
    } catch (_) {
      return const HermesDevicePreferences();
    }
  }

  @override
  Future<void> save(HermesDevicePreferences preferences) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    await prefs.setString(_prefsKey, jsonEncode(preferences.toJson()));
  }

  @override
  Future<String> getOrCreateDeviceId(String platformTag) async {
    final prefs = await _prefsOrNull();
    final existing = prefs?.getString(_deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    final generated = _generateDeviceId(platformTag);
    await prefs?.setString(_deviceIdKey, generated);
    return generated;
  }
}

String _generateDeviceId(String platformTag) {
  final sanitizedPlatform = platformTag.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9_-]'),
    '',
  );
  final prefix = sanitizedPlatform.isEmpty ? 'client' : sanitizedPlatform;
  final rng = Random();
  final suffix = List.generate(
    8,
    (_) => rng.nextInt(16).toRadixString(16),
  ).join();
  return 'hermes-$prefix-$suffix';
}
