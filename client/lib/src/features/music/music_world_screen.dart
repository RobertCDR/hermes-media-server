import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';
import 'music_service.dart';

class MusicWorldScreen extends StatefulWidget {
  const MusicWorldScreen({
    super.key,
    required this.musicService,
    required this.coordinator,
  });

  final MusicService musicService;
  final MusicPlaybackCoordinator coordinator;

  @override
  State<MusicWorldScreen> createState() => _MusicWorldScreenState();
}

class _MusicWorldScreenState extends State<MusicWorldScreen> {
  List<SongModel> _songs = [];
  List<PlaylistSummaryModel> _playlists = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await widget.musicService.listSongs();
      final playlists = await widget.musicService.listPlaylists();
      widget.coordinator.indexSongs(songs);
      if (mounted) {
        setState(() {
          _songs = songs;
          _playlists = playlists;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load Music library: $_error'),
            const SizedBox(height: 10),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final effective = widget.coordinator.effectiveQuality;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio Streaming Quality (${widget.coordinator.networkMode.label}: ${effective.label})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...NetworkTransportMode.values.map(
                          (m) => ChoiceChip(
                            label: Text(m.label),
                            selected: widget.coordinator.networkMode == m,
                            onSelected: (_) => widget.coordinator.setNetworkMode(m),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...AudioQualityPreset.values.map(
                          (preset) => ChoiceChip(
                            label: Text(preset.label),
                            selected: effective == preset,
                            onSelected: (_) {
                              final current = widget.coordinator.audioQualityPolicy;
                              final next = widget.coordinator.networkMode == NetworkTransportMode.wifi
                                  ? AudioQualityPolicy(
                                      wifiPreset: preset,
                                      cellularPreset: current.cellularPreset,
                                    )
                                  : AudioQualityPolicy(
                                      wifiPreset: current.wifiPreset,
                                      cellularPreset: preset,
                                    );
                              widget.coordinator.updateQualityPolicy(next);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Playlists (${_playlists.length})', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_playlists.isEmpty)
              Text('No playlists yet.', style: TextStyle(color: tokens.textSecondary))
            else
              ..._playlists.map(
                (p) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name),
                    subtitle: Text('${p.trackCount} track(s)'),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text('Songs (${_songs.length})', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_songs.isEmpty)
              Text(
                'No songs scanned yet. Open Admin Dashboard to scan a Music library.',
                style: TextStyle(color: tokens.textSecondary),
              )
            else
              ..._songs.asMap().entries.map((entry) {
                final idx = entry.key;
                final song = entry.value;
                return Card(
                  child: ListTile(
                    title: Text(song.title),
                    subtitle: Text('${song.artistName} • ${song.albumTitle} (${song.codec.toUpperCase()})'),
                    trailing: IconButton(
                      icon: Icon(
                        song.isLiked ? Icons.favorite : Icons.favorite_border,
                        color: song.isLiked ? tokens.accentPrimary : tokens.textSecondary,
                      ),
                      onPressed: () async {
                        final liked = await widget.musicService.toggleLikeSong(song.id);
                        if (mounted) {
                          setState(() {
                            _songs[idx] = song.copyWith(isLiked: liked);
                          });
                        }
                      },
                    ),
                    onTap: () => unawaited(widget.coordinator.startQueue(_songs, idx)),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
