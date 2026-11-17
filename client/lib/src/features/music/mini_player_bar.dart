import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import 'music_models.dart';

/// Figma v4 `.now-bar`: aligned transport controls with optically centered [HermesPlayIcon],
/// interactive scrubber, like toggle, Now Playing toggle, Connect Devices button, and volume control.
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({
    super.key,
    required this.session,
    required this.currentSong,
    required this.localDeviceId,
    required this.onTogglePlayPause,
    required this.onSkipNext,
    required this.onOpenDevicePicker,
    this.artworkUri,
    this.onSkipPrevious,
    this.onToggleShuffle,
    this.onCycleRepeat,
    this.onSeekMs,
    this.onVolumeChanged,
    this.onToggleMute,
    this.onToggleLike,
    this.onToggleNowPlaying,
    this.nowPlayingOpen = false,
    this.onTapTitle,
    this.onTapArtist,
  });

  final PlaybackSessionState? session;
  final SongModel? currentSong;
  final String localDeviceId;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onOpenDevicePicker;
  final Uri? artworkUri;
  final VoidCallback? onSkipPrevious;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onCycleRepeat;
  final ValueChanged<int>? onSeekMs;
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleLike;
  final VoidCallback? onToggleNowPlaying;
  final bool nowPlayingOpen;
  final VoidCallback? onTapTitle;
  final VoidCallback? onTapArtist;

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  double? _scrubDragMs;
  double? _volumeDrag;
  bool _volumeHover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final song = widget.currentSong;
    if (s == null || song == null || s.state == PlaybackState.stopped) {
      return const SizedBox.shrink();
    }

    final tokens = HermesThemeTokens.of(context);
    final isRemote = s.activeRendererDeviceId != null &&
        s.activeRendererDeviceId != widget.localDeviceId;
    final deviceName = s.activeRendererDeviceName ?? s.activeRendererDeviceId;
    final rendererLabel =
        isRemote ? 'Playing on $deviceName' : 'Playing on This Device';
    final isPlaying = s.state == PlaybackState.playing;
    final maxMs = song.durationMs > 0 ? song.durationMs.toDouble() : 1.0;
    final activeMs = (_scrubDragMs ?? s.positionMs.toDouble()).clamp(0.0, maxMs);
    final effectiveVolume = (_volumeDrag ?? s.volume).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        border: Border(top: BorderSide(color: tokens.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;

              if (!wide) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: activeMs / maxMs,
                      minHeight: 2.5,
                      color: tokens.accent,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: widget.onToggleNowPlaying ?? widget.onTapTitle,
                            child: HermesArtworkImage(
                              uri: widget.artworkUri,
                              fallbackTitle: song.albumTitle,
                              fallbackIcon: Icons.music_note_rounded,
                              width: 44,
                              height: 44,
                              borderRadius: BorderRadius.circular(4),
                              showFallbackLabel: false,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TrackIdentityMeta(
                              song: song,
                              onTapTitle: widget.onTapTitle,
                              onTapArtist: widget.onTapArtist,
                            ),
                          ),
                          if (widget.onToggleLike != null)
                            _CompactIconSlot(
                              tooltip: song.isLiked
                                  ? 'Remove from Liked Songs'
                                  : 'Save to Liked Songs',
                              icon: song.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: song.isLiked ? tokens.accent : tokens.text2,
                              onPressed: widget.onToggleLike,
                            ),
                          if (widget.onSkipPrevious != null)
                            _CompactIconSlot(
                              tooltip: 'Previous Track',
                              icon: Icons.skip_previous_rounded,
                              color: tokens.text,
                              onPressed: widget.onSkipPrevious,
                            ),
                          _CircularTransportPlayButton(
                            isPlaying: isPlaying,
                            onPressed: widget.onTogglePlayPause,
                          ),
                          _CompactIconSlot(
                            tooltip: 'Next Track',
                            icon: Icons.skip_next_rounded,
                            color: tokens.text,
                            onPressed: widget.onSkipNext,
                          ),
                          _CompactIconSlot(
                            tooltip: 'Connect Devices',
                            icon: Icons.devices_rounded,
                            color: isRemote ? tokens.accent : tokens.text2,
                            onPressed: widget.onOpenDevicePicker,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left section (.now-left)
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: widget.onToggleNowPlaying ?? widget.onTapTitle,
                            child: HermesArtworkImage(
                              uri: widget.artworkUri,
                              fallbackTitle: song.albumTitle,
                              fallbackIcon: Icons.music_note_rounded,
                              width: 52,
                              height: 52,
                              borderRadius: BorderRadius.circular(4),
                              showFallbackLabel: false,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TrackIdentityMeta(
                              song: song,
                              onTapTitle: widget.onTapTitle,
                              onTapArtist: widget.onTapArtist,
                            ),
                          ),
                          if (widget.onToggleLike != null)
                            _CompactIconSlot(
                              tooltip: song.isLiked
                                  ? 'Remove from Liked Songs'
                                  : 'Save to Liked Songs',
                              icon: song.isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: song.isLiked ? tokens.accent : tokens.text2,
                              onPressed: widget.onToggleLike,
                            ),
                        ],
                      ),
                    ),

                    // Center section (.now-center): strictly single-line aligned transport + scrubber
                    Expanded(
                      flex: 5,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 36,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CompactIconSlot(
                                    tooltip: s.shuffle ? 'Shuffle on' : 'Shuffle off',
                                    icon: Icons.shuffle_rounded,
                                    size: 18,
                                    color: s.shuffle ? tokens.accent : tokens.text2,
                                    showActiveDot: s.shuffle,
                                    onPressed: widget.onToggleShuffle,
                                  ),
                                  const SizedBox(width: 10),
                                  _CompactIconSlot(
                                    tooltip: 'Previous Track',
                                    icon: Icons.skip_previous_rounded,
                                    size: 22,
                                    color: tokens.text2,
                                    onPressed: widget.onSkipPrevious,
                                  ),
                                  const SizedBox(width: 12),
                                  _CircularTransportPlayButton(
                                    isPlaying: isPlaying,
                                    onPressed: widget.onTogglePlayPause,
                                  ),
                                  const SizedBox(width: 12),
                                  _CompactIconSlot(
                                    tooltip: 'Next Track',
                                    icon: Icons.skip_next_rounded,
                                    size: 22,
                                    color: tokens.text2,
                                    onPressed: widget.onSkipNext,
                                  ),
                                  const SizedBox(width: 10),
                                  _RepeatModeSlot(
                                    mode: s.repeatMode,
                                    onPressed: widget.onCycleRepeat,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    formatDurationMs(activeMs.round()),
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      color: tokens.text2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      activeTrackColor: _scrubDragMs != null
                                          ? tokens.accent
                                          : tokens.text,
                                      inactiveTrackColor:
                                          tokens.text.withValues(alpha: 0.25),
                                      thumbColor: tokens.text,
                                      overlayColor:
                                          tokens.accent.withValues(alpha: 0.14),
                                      thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius:
                                            _scrubDragMs != null ? 6 : 4,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 10,
                                      ),
                                    ),
                                    child: SizedBox(
                                      height: 18,
                                      child: Slider(
                                        value: activeMs,
                                        min: 0,
                                        max: maxMs,
                                        onChanged: widget.onSeekMs == null
                                            ? null
                                            : (v) => setState(() => _scrubDragMs = v),
                                        onChangeEnd: widget.onSeekMs == null
                                            ? null
                                            : (v) {
                                                setState(() => _scrubDragMs = null);
                                                widget.onSeekMs!(v.round());
                                              },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 40,
                                  child: Text(
                                    formatDurationMs(song.durationMs),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      color: tokens.text2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Right section (.now-right): Queue/Lyrics toggle, Connect Devices, Volume
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.onToggleNowPlaying != null)
                            _CompactIconSlot(
                              tooltip: 'Now playing & queue',
                              icon: Icons.queue_music_rounded,
                              size: 19,
                              color: widget.nowPlayingOpen
                                  ? tokens.accent
                                  : tokens.text2,
                              onPressed: widget.onToggleNowPlaying,
                            ),
                          _CompactIconSlot(
                            tooltip: 'Connect Devices',
                            icon: Icons.devices_rounded,
                            size: 19,
                            color: isRemote ? tokens.accent : tokens.text2,
                            onPressed: widget.onOpenDevicePicker,
                          ),
                          MouseRegion(
                            onEnter: (_) => setState(() => _volumeHover = true),
                            onExit: (_) => setState(() => _volumeHover = false),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _CompactIconSlot(
                                  tooltip: effectiveVolume == 0 ? 'Unmute' : 'Mute',
                                  icon: effectiveVolume == 0
                                      ? Icons.volume_off_rounded
                                      : effectiveVolume < 0.5
                                          ? Icons.volume_down_rounded
                                          : Icons.volume_up_rounded,
                                  size: 19,
                                  color: tokens.text2,
                                  onPressed: widget.onToggleMute,
                                ),
                                SizedBox(
                                  width: 84,
                                  height: 18,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      activeTrackColor:
                                          (_volumeHover || _volumeDrag != null)
                                              ? tokens.accent
                                              : tokens.text,
                                      inactiveTrackColor:
                                          tokens.text.withValues(alpha: 0.25),
                                      thumbColor: tokens.text,
                                      thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius:
                                            (_volumeHover || _volumeDrag != null)
                                                ? 5.5
                                                : 3.5,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 9,
                                      ),
                                    ),
                                    child: Slider(
                                      value: effectiveVolume,
                                      min: 0.0,
                                      max: 1.0,
                                      onChanged: widget.onVolumeChanged == null
                                          ? null
                                          : (v) {
                                              setState(() => _volumeDrag = v);
                                              widget.onVolumeChanged!(v);
                                            },
                                      onChangeEnd: widget.onVolumeChanged == null
                                          ? null
                                          : (_) => setState(() => _volumeDrag = null),
                                    ),
                                  ),
                                ),
                                ExcludeSemantics(
                                  child: AnimatedOpacity(
                                    alwaysIncludeSemantics: true,
                                    opacity: (_volumeHover || _volumeDrag != null) ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 140),
                                    child: SizedBox(
                                      width: 34,
                                      child: Text(
                                        '${(effectiveVolume * 100).round()}%',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                          color: tokens.text2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (isRemote)
            InkWell(
              onTap: widget.onOpenDevicePicker,
              child: Container(
                width: double.infinity,
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                color: tokens.accent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.speaker_group_rounded,
                      size: 13,
                      color: tokens.accentInk,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        rendererLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.accentInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackIdentityMeta extends StatelessWidget {
  const _TrackIdentityMeta({
    required this.song,
    this.onTapTitle,
    this.onTapArtist,
  });

  final SongModel song;
  final VoidCallback? onTapTitle;
  final VoidCallback? onTapArtist;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTapTitle,
          child: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.text,
            ),
          ),
        ),
        const SizedBox(height: 1),
        InkWell(
          onTap: onTapArtist,
          child: Text(
            song.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: tokens.text2,
            ),
          ),
        ),
      ],
    );
  }
}

class _CircularTransportPlayButton extends StatefulWidget {
  const _CircularTransportPlayButton({
    required this.isPlaying,
    required this.onPressed,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  State<_CircularTransportPlayButton> createState() =>
      _CircularTransportPlayButtonState();
}

class _CircularTransportPlayButtonState
    extends State<_CircularTransportPlayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Tooltip(
      message: widget.isPlaying ? 'Pause' : 'Play',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Material(
            color: tokens.text,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: widget.isPlaying
                      ? HermesPauseIcon(size: 16, color: tokens.bgSunken)
                      : HermesPlayIcon(size: 16, color: tokens.bgSunken),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactIconSlot extends StatelessWidget {
  const _CompactIconSlot({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 19,
    this.showActiveDot = false,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final double size;
  final bool showActiveDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 32,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: size,
                color: onPressed == null ? color.withValues(alpha: 0.4) : color,
              ),
              if (showActiveDot)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatModeSlot extends StatelessWidget {
  const _RepeatModeSlot({required this.mode, required this.onPressed});

  final HermesRepeatMode mode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final active = mode != HermesRepeatMode.off;
    final color = active ? tokens.accent : tokens.text2;
    final tooltip = switch (mode) {
      HermesRepeatMode.off => 'Repeat off',
      HermesRepeatMode.all => 'Repeat all',
      HermesRepeatMode.one => 'Repeat one',
    };

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 32,
          height: 34,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.repeat_rounded,
                size: 18,
                color: onPressed == null ? color.withValues(alpha: 0.4) : color,
              ),
              if (mode == HermesRepeatMode.one)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Text(
                    '1',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: tokens.accent,
                      height: 1.0,
                    ),
                  ),
                ),
              if (active)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
