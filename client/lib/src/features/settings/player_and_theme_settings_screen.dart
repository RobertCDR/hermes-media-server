import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../cinema/cinema_models.dart';
import '../cinema/hermes_video_player.dart';
import '../music/music_models.dart';

class PlayerAndThemeSettingsScreen extends StatefulWidget {
  const PlayerAndThemeSettingsScreen({
    super.key,
    required this.tokens,
    required this.rendererBackend,
    required this.defaultVideoQuality,
    required this.onThemeChanged,
    required this.onRendererChanged,
    required this.onDefaultVideoQualityChanged,
    this.networkMode = NetworkTransportMode.wifi,
    this.audioQualityPolicy = const AudioQualityPolicy(),
    this.onNetworkModeChanged,
    this.onAudioQualityPolicyChanged,
  });

  final HermesThemeTokens tokens;
  final VideoRendererBackend rendererBackend;
  final VideoQualityPreset defaultVideoQuality;
  final ValueChanged<HermesThemeTokens> onThemeChanged;
  final ValueChanged<VideoRendererBackend> onRendererChanged;
  final ValueChanged<VideoQualityPreset> onDefaultVideoQualityChanged;
  final NetworkTransportMode networkMode;
  final AudioQualityPolicy audioQualityPolicy;
  final ValueChanged<NetworkTransportMode>? onNetworkModeChanged;
  final ValueChanged<AudioQualityPolicy>? onAudioQualityPolicyChanged;

  @override
  State<PlayerAndThemeSettingsScreen> createState() => _PlayerAndThemeSettingsScreenState();
}

class _PlayerAndThemeSettingsScreenState extends State<PlayerAndThemeSettingsScreen> {
  late HermesThemeTokens _tokens;
  late VideoRendererBackend _renderer;
  late VideoQualityPreset _defaultQuality;
  late NetworkTransportMode _networkMode;
  late AudioQualityPolicy _audioPolicy;

  @override
  void initState() {
    super.initState();
    _tokens = widget.tokens;
    _renderer = widget.rendererBackend;
    _defaultQuality = widget.defaultVideoQuality;
    _networkMode = widget.networkMode;
    _audioPolicy = widget.audioQualityPolicy;
  }

  void _updateTheme({SurfacePreset? surface, HermesAccentKind? accent}) {
    final next = HermesThemeTokens.resolve(
      surfacePreset: surface ?? _tokens.surfacePreset,
      accentKind: accent ?? _tokens.accentKind,
    );
    setState(() => _tokens = next);
    widget.onThemeChanged(next);
  }

  void _updateAudioPreset(AudioQualityPreset preset) {
    final next = _networkMode == NetworkTransportMode.wifi
        ? AudioQualityPolicy(
            wifiPreset: preset,
            cellularPreset: _audioPolicy.cellularPreset,
          )
        : AudioQualityPolicy(
            wifiPreset: _audioPolicy.wifiPreset,
            cellularPreset: preset,
          );
    setState(() => _audioPolicy = next);
    widget.onAudioQualityPolicyChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final activeAudioPreset = _audioPolicy.presetFor(_networkMode);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Preferences')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              _SettingsSectionCard(
                title: 'Appearance & Theme',
                icon: Icons.palette_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Surface Theme Preset', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: SurfacePreset.values.map((preset) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(preset.label),
                          selected: _tokens.surfacePreset == preset,
                          onSelected: (_) => _updateTheme(surface: preset),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text('Accent Color', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: HermesAccentKind.values.map((accent) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(accent.label),
                          selected: _tokens.accentKind == accent,
                          onSelected: (_) => _updateTheme(accent: accent),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SettingsSectionCard(
                title: 'Cinema Video Playback',
                icon: Icons.movie_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video Renderer Backend (HDR Subtitle Fix)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: VideoRendererBackend.values.map((backend) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(backend.label),
                          selected: _renderer == backend,
                          onSelected: (_) {
                            setState(() => _renderer = backend);
                            widget.onRendererChanged(backend);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text('Default Video Quality', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: VideoQualityPreset.values.map((quality) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(quality.label),
                          selected: _defaultQuality == quality,
                          onSelected: (_) {
                            setState(() => _defaultQuality = quality);
                            widget.onDefaultVideoQualityChanged(quality);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SettingsSectionCard(
                title: 'Music Streaming Quality',
                subtitle: 'Separate bitrates for Wi-Fi / LAN and Cellular.',
                icon: Icons.graphic_eq_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Network Profile', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: NetworkTransportMode.values.map((mode) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(mode.label),
                          selected: _networkMode == mode,
                          onSelected: (_) {
                            setState(() => _networkMode = mode);
                            widget.onNetworkModeChanged?.call(mode);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Audio Quality (${_networkMode.label}: ${activeAudioPreset.label})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: AudioQualityPreset.values.map((preset) {
                        return ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(preset.label),
                          selected: activeAudioPreset == preset,
                          onSelected: (_) => _updateAudioPreset(preset),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: tokens.accentPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: tokens.textSecondary, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
