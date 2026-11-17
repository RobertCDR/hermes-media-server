import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import 'cinema_models.dart';

String formatDurationShort(int durationMs) {
  if (durationMs <= 0) return '0m';
  final totalMin = (durationMs / 60000).round();
  return formatCinemaMinutes(totalMin);
}

class CinemaPlayPillButton extends StatelessWidget {
  const CinemaPlayPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        onTap: onPressed,
        child: SizedBox(
          height: compact ? 34 : 46,
          child: Padding(
            padding: EdgeInsets.only(
              left: compact ? 14 : 22,
              right: compact ? 14 : 26,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HermesPlayIcon(
                  size: compact ? 16 : 20,
                  color: const Color(0xFF0B0B0B),
                ),
                SizedBox(width: compact ? 6 : 10),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0B0B0B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CinemaGlassButton extends StatelessWidget {
  const CinemaGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        hoverColor: Colors.white.withValues(alpha: 0.22),
        onTap: onPressed,
        child: SizedBox(
          height: compact ? 34 : 46,
          child: Padding(
            padding: EdgeInsets.only(
              left: compact ? 12 : 16,
              right: compact ? 14 : 20,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                SizedBox(width: compact ? 6 : 9),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CinemaGlassIconButton extends StatelessWidget {
  const CinemaGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filledWhite = false,
    this.highlightedAccent = false,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filledWhite;
  final bool highlightedAccent;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final bgColor = filledWhite
        ? Colors.white
        : highlightedAccent
            ? Colors.white.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.14);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        button: true,
        excludeSemantics: true,
        label: tooltip,
        child: Material(
          color: bgColor,
          shape: CircleBorder(
            side: highlightedAccent && !filledWhite
                ? BorderSide(color: tokens.accent.withValues(alpha: 0.65))
                : BorderSide.none,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: filledWhite
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.22),
            onTap: onPressed,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}

class CinemaHeroMetaLine extends StatelessWidget {
  const CinemaHeroMetaLine({
    super.key,
    this.rating,
    this.year,
    required this.lengthLabel,
    this.genres = const [],
    this.qualityTag,
  });

  final double? rating;
  final int? year;
  final String lengthLabel;
  final List<String> genres;
  final String? qualityTag;

  @override
  Widget build(BuildContext context) {
    final dot = Text(
      '·',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontWeight: FontWeight.w700,
      ),
    );

    final items = <Widget>[];
    void addWithDot(Widget child) {
      if (items.isNotEmpty) {
        items.add(dot);
      }
      items.add(child);
    }

    if (rating != null && rating! > 0) {
      addWithDot(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF5C518),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'IMDb',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              rating!.toStringAsFixed(1),
              style: const TextStyle(
                fontFamily: 'Figtree',
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (year != null) {
      addWithDot(_metaText('$year'));
    }

    if (lengthLabel.isNotEmpty) {
      addWithDot(_metaText(lengthLabel));
    }

    if (genres.isNotEmpty) {
      addWithDot(_metaText(genres.take(3).join(', ')));
    }

    if (qualityTag != null && qualityTag!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
          ),
          child: Text(
            qualityTag!,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  Widget _metaText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.82),
      ),
    );
  }
}

class CinemaPosterCard extends StatefulWidget {
  const CinemaPosterCard({
    super.key,
    required this.itemKey,
    required this.title,
    required this.subtitle,
    required this.artworkUri,
    required this.fallbackIcon,
    required this.inWatchlist,
    required this.onTap,
    this.onToggleWatchlist,
    this.isWatched = false,
    this.isNew = false,
    this.isPartial = false,
    this.progress,
    this.reduceMotion = false,
    this.width = 172,
  });

  final String itemKey;
  final String title;
  final String subtitle;
  final Uri? artworkUri;
  final IconData fallbackIcon;
  final bool inWatchlist;
  final VoidCallback onTap;
  final VoidCallback? onToggleWatchlist;
  final bool isWatched;
  final bool isNew;
  final bool isPartial;
  final double? progress;
  final bool reduceMotion;
  final double width;

  @override
  State<CinemaPosterCard> createState() => _CinemaPosterCardState();
}

class _CinemaPosterCardState extends State<CinemaPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final showBookmark = widget.inWatchlist || _hovered;
    final posterHeight = widget.width * 1.5;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: widget.width,
                  height: posterHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: AnimatedScale(
                          scale: (_hovered && !widget.reduceMotion) ? 1.04 : 1.0,
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: HermesArtworkImage(
                            uri: widget.artworkUri,
                            fallbackTitle: widget.title,
                            fallbackIcon: widget.fallbackIcon,
                            width: widget.width,
                            height: posterHeight,
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      if (widget.isNew || widget.isPartial)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: widget.isNew
                                  ? tokens.accent
                                  : Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.isNew ? 'New' : 'Partial',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: widget.isNew
                                    ? tokens.accentInk
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      if (widget.onToggleWatchlist != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Semantics(
                            container: true,
                            button: true,
                            excludeSemantics: true,
                            label: widget.inWatchlist
                                ? 'Remove from Watchlist'
                                : 'Add to Watchlist',
                            onTap: widget.onToggleWatchlist,
                            child: IgnorePointer(
                              ignoring: !showBookmark,
                              child: AnimatedOpacity(
                                alwaysIncludeSemantics: true,
                                opacity: showBookmark ? 1.0 : 0.0,
                                duration: widget.reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                child: InkWell(
                                  key: Key('poster-bookmark-${widget.itemKey}'),
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onToggleWatchlist,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: widget.inWatchlist
                                          ? Colors.white
                                          : Colors.black.withValues(alpha: 0.62),
                                    ),
                                    child: HermesBookmarkIcon(
                                      size: 15,
                                      filled: widget.inWatchlist,
                                      color: widget.inWatchlist
                                          ? const Color(0xFF0B0B0B)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.isWatched)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Watched',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      if (widget.progress != null && widget.progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: widget.progress,
                              minHeight: 4,
                              color: tokens.accent,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  color: tokens.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class CinemaLandscapeCard extends StatefulWidget {
  const CinemaLandscapeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.artworkUri,
    required this.onTap,
    this.progress = 0,
    this.isUpNext = false,
    this.reduceMotion = false,
  });

  final String title;
  final String subtitle;
  final Uri? artworkUri;
  final VoidCallback onTap;
  final double progress;
  final bool isUpNext;
  final bool reduceMotion;

  @override
  State<CinemaLandscapeCard> createState() => _CinemaLandscapeCardState();
}

class _CinemaLandscapeCardState extends State<CinemaLandscapeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 300,
                  height: 168.75,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: AnimatedScale(
                          scale: (_hovered && !widget.reduceMotion) ? 1.04 : 1.0,
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: HermesArtworkImage(
                            uri: widget.artworkUri,
                            fallbackTitle: widget.title,
                            width: 300,
                            height: 168.75,
                            borderRadius: BorderRadius.zero,
                            showFallbackLabel: false,
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: AnimatedOpacity(
                          alwaysIncludeSemantics: true,
                          opacity: _hovered ? 1.0 : 0.0,
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.35),
                            alignment: Alignment.center,
                            child: const HermesPlayIcon(
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      if (widget.isUpNext)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Up next',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B0B0B),
                              ),
                            ),
                          ),
                        )
                      else if (widget.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ExcludeSemantics(
                            child: LinearProgressIndicator(
                              value: widget.progress,
                              minHeight: 4,
                              color: tokens.accent,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  color: tokens.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
