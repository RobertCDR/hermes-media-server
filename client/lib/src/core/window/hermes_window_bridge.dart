import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String hermesWindowChannelName = 'hermes.window/control';
const String _windowBoundsPrefsKey = 'hermes.window.bounds.v1';

class HermesMediaFlyoutData {
  const HermesMediaFlyoutData({
    required this.title,
    required this.artist,
    required this.isPlaying,
    this.artBgra,
    this.artWidth = 0,
    this.artHeight = 0,
  });

  final String title;
  final String artist;
  final bool isPlaying;
  final Uint8List? artBgra;
  final int artWidth;
  final int artHeight;
}

/// Bridges Dart UI chrome, keyboard/mouse commands, tray state, and the subtle
/// Windows always-on-top media flyout to `windows/runner/hermes_desktop_window.cpp`.
class HermesWindowBridge {
  HermesWindowBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(hermesWindowChannelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final HermesWindowBridge instance = HermesWindowBridge();

  final MethodChannel _channel;
  final ValueNotifier<bool> isFullscreen = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isMaximized = ValueNotifier<bool>(false);
  final ValueNotifier<String> title = ValueNotifier<String>('Hermes');
  final ValueNotifier<String?> activeTrackSummary = ValueNotifier<String?>(null);

  void Function(String action)? onTrayAction;
  void Function(String action)? onFlyoutAction;
  void Function(String direction)? onAppCommand;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onWindowStateChanged':
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final max = args['isMaximized'] as bool?;
          final fs = args['isFullscreen'] as bool?;
          if (max != null && max != isMaximized.value) {
            isMaximized.value = max;
          }
          if (fs != null && fs != isFullscreen.value) {
            isFullscreen.value = fs;
          }
        }
      case 'onTrayAction':
        final action = call.arguments as String?;
        if (action != null && action.isNotEmpty) {
          onTrayAction?.call(action);
        }
      case 'onFlyoutAction':
        final action = call.arguments as String?;
        if (action != null && action.isNotEmpty) {
          onFlyoutAction?.call(action);
        }
      case 'onAppCommand':
        final direction = call.arguments as String?;
        if (direction != null && direction.isNotEmpty) {
          onAppCommand?.call(direction);
        }
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } catch (err) {
      if (kDebugMode) {
        // Non-fatal in headless or unsupported test hosts.
        assert(() {
          return true;
        }());
      }
      return null;
    }
  }

  Future<void> startDragging() => _invoke<void>('startDragging');

  Future<void> startTopResize() => _invoke<void>('startTopResize');

  Future<void> minimize() => _invoke<void>('minimize');

  Future<void> toggleMaximize() => _invoke<void>('toggleMaximize');

  Future<void> setFullscreen(bool fullscreen) async {
    if (isFullscreen.value != fullscreen) {
      isFullscreen.value = fullscreen;
    }
    await _invoke<void>('setFullscreen', fullscreen);
  }

  Future<void> closeWindow() => _invoke<void>('closeWindow');

  Future<void> quitApp() => _invoke<void>('quitApp');

  Future<void> showWindow() => _invoke<void>('showWindow');

  Future<void> setTitle(String nextTitle) async {
    final clean = nextTitle.trim().isEmpty ? 'Hermes' : nextTitle.trim();
    if (title.value != clean) {
      title.value = clean;
    }
    await _invoke<void>('setTitle', clean);
  }

  Future<void> setCloseToTray(bool enabled) =>
      _invoke<void>('setCloseToTray', enabled);

  Future<void> updateTrayState({
    required String title,
    required String artist,
    required bool isPlaying,
  }) async {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    final summary = cleanTitle.isEmpty
        ? null
        : (cleanArtist.isEmpty ? cleanTitle : '$cleanTitle · $cleanArtist');
    if (activeTrackSummary.value != summary) {
      activeTrackSummary.value = summary;
    }
    await _invoke<void>('updateTrayState', <String, dynamic>{
      'title': cleanTitle,
      'artist': cleanArtist,
      'isPlaying': isPlaying,
    });
  }

  Future<void> showMediaFlyout(HermesMediaFlyoutData data) {
    return _invoke<void>('showMediaFlyout', <String, dynamic>{
      'title': data.title,
      'artist': data.artist,
      'isPlaying': data.isPlaying,
      if (data.artBgra != null) 'artBgra': data.artBgra,
      'artWidth': data.artWidth,
      'artHeight': data.artHeight,
    });
  }

  Future<void> hideMediaFlyout() => _invoke<void>('hideMediaFlyout');

  Future<Map<String, dynamic>?> getBounds() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getBounds');
    if (raw == null || raw.isEmpty) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> restoreSavedBounds(SharedPreferences prefs) async {
    final rawJson = prefs.getString(_windowBoundsPrefsKey);
    if (rawJson == null || rawJson.isEmpty) return;
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      await _invoke<void>('setBounds', decoded);
    } catch (_) {}
  }

  Future<void> saveCurrentBounds(SharedPreferences prefs) async {
    final bounds = await getBounds();
    if (bounds == null) return;
    await prefs.setString(_windowBoundsPrefsKey, jsonEncode(bounds));
  }

  /// Decodes compressed image bytes into premultiplied-safe BGRA32 pixels for
  /// GDI `StretchDIBits` inside the native media flyout.
  static Future<({Uint8List bgra, int width, int height})?> decodeArtworkBgra(
    Uint8List encodedBytes, {
    int targetSize = 96,
  }) async {
    if (encodedBytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        encodedBytes,
        targetWidth: targetSize,
        targetHeight: targetSize,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = img.width;
      final height = img.height;
      img.dispose();
      codec.dispose();
      if (byteData == null) return null;

      final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i];
        final b = bytes[i + 2];
        bytes[i] = b;
        bytes[i + 2] = r;
        bytes[i + 3] = 255;
      }
      return (bgra: bytes, width: width, height: height);
    } catch (_) {
      return null;
    }
  }
}
