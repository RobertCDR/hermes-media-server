import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart' show PaintingBinding, VoidCallback;

class HermesCacheSnapshot {
  const HermesCacheSnapshot({
    required this.imageCacheBytes,
    required this.imageCacheCount,
    required this.diskCacheBytes,
    required this.capBytes,
  });

  final int imageCacheBytes;
  final int imageCacheCount;
  final int diskCacheBytes;
  final int capBytes;

  int get totalBytes => imageCacheBytes + diskCacheBytes;

  double get usageRatio {
    if (capBytes <= 0) return 0;
    return (totalBytes / capBytes).clamp(0.0, 1.0);
  }
}

class HermesCacheManager {
  HermesCacheManager({this.diskCacheDir});

  static const List<int> capOptionsMb = [128, 256, 512, 1024, 2048];

  final Directory? diskCacheDir;

  Directory get _effectiveDiskDir =>
      diskCacheDir ??
      Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}hermes_cache',
      );

  void applyCapMb(int capMb) {
    final clampedMb = capMb.clamp(128, 2048);
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = clampedMb * 1024 * 1024;
    imageCache.maximumSize = (clampedMb * 4).clamp(250, 4000);
  }

  Future<HermesCacheSnapshot> inspect({required int capMb}) async {
    final clampedMb = capMb.clamp(128, 2048);
    final imageCache = PaintingBinding.instance.imageCache;
    final diskBytes = await _measureDiskCacheBytes();

    return HermesCacheSnapshot(
      imageCacheBytes: imageCache.currentSizeBytes,
      imageCacheCount: imageCache.currentSize,
      diskCacheBytes: diskBytes,
      capBytes: clampedMb * 1024 * 1024,
    );
  }

  Future<HermesCacheSnapshot> clearAll({
    required int capMb,
    VoidCallback? onClearCatalogCaches,
  }) async {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    onClearCatalogCaches?.call();

    if (!kIsWeb) {
      try {
        final dir = _effectiveDiskDir;
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: false, followLinks: false)) {
            try {
              await entity.delete(recursive: true);
            } catch (_) {
              // Ignore in-use temp entries cleanly.
            }
          }
        }
      } catch (_) {
        // Ignore platform temp directory permission errors.
      }
    }

    return inspect(capMb: capMb);
  }

  Future<int> _measureDiskCacheBytes() async {
    if (kIsWeb) return 0;
    try {
      final dir = _effectiveDiskDir;
      if (!await dir.exists()) {
        return 0;
      }
      var total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Skip files removed concurrently.
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  static String formatCapMb(int mb) {
    if (mb >= 1024 && mb % 1024 == 0) {
      return '${mb ~/ 1024} GB';
    }
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}
