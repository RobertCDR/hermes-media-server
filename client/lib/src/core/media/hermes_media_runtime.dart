import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:media_kit/media_kit.dart';

/// Coordinates one-time `media_kit` (`libmpv`) initialization so application
/// launches enable native playback while headless unit and widget tests remain
/// isolated from platform dynamic libraries.
abstract final class HermesMediaRuntime {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static bool ensureInitialized({
    String? libmpv,
    void Function({String? libmpv})? initializer,
  }) {
    if (_initialized) {
      return true;
    }
    try {
      (initializer ?? MediaKit.ensureInitialized)(libmpv: libmpv);
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void setInitializedForTest(bool value) {
    _initialized = value;
  }
}
