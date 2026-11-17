import 'package:material_ui/material_ui.dart';
import '../theme/hermes_theme_tokens.dart';

String formatDurationMs(int durationMs) {
  if (durationMs <= 0) {
    return '0:00';
  }
  final totalSeconds = durationMs ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final secText = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secText';
  }
  return '$minutes:$secText';
}

class HermesArtworkImage extends StatelessWidget {
  const HermesArtworkImage({
    super.key,
    required this.uri,
    required this.fallbackTitle,
    this.fallbackIcon = Icons.movie_outlined,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.fit = BoxFit.cover,
    this.showFallbackLabel = true,
  });

  final Uri? uri;
  final String fallbackTitle;
  final IconData fallbackIcon;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final bool showFallbackLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final compact = width != null && width! <= 56;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.accentPrimary.withValues(alpha: 0.24),
            tokens.bgElevated,
            tokens.bgPrimary,
          ],
        ),
      ),
      padding: EdgeInsets.all(compact ? 4 : 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            fallbackIcon,
            size: compact ? 18 : 34,
            color: tokens.textSecondary.withValues(alpha: 0.85),
          ),
          if (showFallbackLabel && (width == null || width! > 80)) ...[
            const SizedBox(height: 8),
            Text(
              fallbackTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    final image = uri == null
        ? placeholder
        : Image.network(
            uri.toString(),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return placeholder;
            },
          );

    // Exclude async image placeholder/raw-image swaps from Semantics so network loads
    // never churn AXTree nodes during scrolling or hover on Windows desktop.
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: width,
          height: height,
          child: image,
        ),
      ),
    );
  }
}
