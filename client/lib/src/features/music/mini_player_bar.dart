import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
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
  });

  final PlaybackSessionState? session;
  final SongModel? currentSong;
  final String localDeviceId;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSkipNext;
  final VoidCallback onOpenDevicePicker;

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

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: const Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.music_note, color: tokens.accentPrimary),
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
          IconButton(
            tooltip: 'Connect Devices',
            icon: Icon(
              Icons.devices,
              color: isRemote ? tokens.accentPrimary : tokens.textSecondary,
            ),
            onPressed: onOpenDevicePicker,
          ),
          IconButton(
            tooltip: s.state == PlaybackState.playing ? 'Pause' : 'Play',
            icon: Icon(s.state == PlaybackState.playing ? Icons.pause_circle : Icons.play_circle),
            onPressed: onTogglePlayPause,
          ),
          IconButton(
            tooltip: 'Next Track',
            icon: const Icon(Icons.skip_next),
            onPressed: onSkipNext,
          ),
        ],
      ),
    );
  }
}
