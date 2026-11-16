import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import 'music_models.dart';

class MiniPlayerBar extends StatelessWidget {
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
  });

  final PlaybackSessionState? session;
  final SongModel? currentSong;
  final String localDeviceId;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onOpenDevicePicker;
  final Uri? artworkUri;
  final VoidCallback? onSkipPrevious;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final song = currentSong;
    if (s == null || song == null || s.state == PlaybackState.stopped) {
      return const SizedBox.shrink();
    }

    final tokens = HermesThemeTokens.of(context);
    final isRemote = s.activeRendererDeviceId != null && s.activeRendererDeviceId != localDeviceId;
    final rendererLabel = isRemote
        ? 'Playing on ${s.activeRendererDeviceName ?? s.activeRendererDeviceId}'
        : 'Playing on This Device';
    final progressRatio = song.durationMs > 0
        ? (s.positionMs / song.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: const Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progressRatio,
            minHeight: 2.5,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                HermesArtworkImage(
                  uri: artworkUri,
                  fallbackTitle: song.albumTitle,
                  fallbackIcon: Icons.music_note,
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.circular(8),
                  showFallbackLabel: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${song.artistName} • $rendererLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isRemote ? tokens.accentHover : tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${formatDurationMs(s.positionMs)} / ${formatDurationMs(song.durationMs)}',
                    style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                  ),
                ),
                if (onSkipPrevious != null)
                  IconButton(
                    tooltip: 'Previous Track',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: onSkipPrevious,
                  ),
                IconButton(
                  tooltip: s.state == PlaybackState.playing ? 'Pause' : 'Play',
                  icon: Icon(
                    s.state == PlaybackState.playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 32,
                    color: tokens.accentPrimary,
                  ),
                  onPressed: onTogglePlayPause,
                ),
                IconButton(
                  tooltip: 'Next Track',
                  icon: const Icon(Icons.skip_next),
                  onPressed: onSkipNext,
                ),
                IconButton(
                  tooltip: 'Connect Devices',
                  icon: Icon(
                    Icons.devices,
                    color: isRemote ? tokens.accentPrimary : tokens.textSecondary,
                  ),
                  onPressed: onOpenDevicePicker,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
