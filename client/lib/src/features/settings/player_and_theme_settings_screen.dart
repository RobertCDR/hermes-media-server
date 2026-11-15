import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../cinema/cinema_models.dart';
import '../cinema/hermes_video_player.dart';

class PlayerAndThemeSettingsScreen extends StatefulWidget {
  const PlayerAndThemeSettingsScreen({
    super.key,
    required this.tokens,
    required this.rendererBackend,
    required this.defaultVideoQuality,
    required this.onThemeChanged,
    required this.onRendererChanged,
    required this.onDefaultVideoQualityChanged,
  });

  final HermesThemeTokens tokens;
  final VideoRendererBackend rendererBackend;
  final VideoQualityPreset defaultVideoQuality;
  final ValueChanged<HermesThemeTokens> onThemeChanged;
  final ValueChanged<VideoRendererBackend> onRendererChanged;
  final ValueChanged<VideoQualityPreset> onDefaultVideoQualityChanged;

  @override
  State<PlayerAndThemeSettingsScreen> createState() => _PlayerAndThemeSettingsScreenState();
}

class _PlayerAndThemeSettingsScreenState extends State<PlayerAndThemeSettingsScreen> {
  late HermesThemeTokens _tokens;
  late VideoRendererBackend _renderer;
  late VideoQualityPreset _defaultQuality;

  @override
  void initState() {
    super.initState();
    _tokens = widget.tokens;
    _renderer = widget.rendererBackend;
    _defaultQuality = widget.defaultVideoQuality;
  }

  void _updateTheme({SurfacePreset? surface, HermesAccentKind? accent}) {
    final next = HermesThemeTokens.resolve(
      surfacePreset: surface ?? _tokens.surfacePreset,
      accentKind: accent ?? _tokens.accentKind,
    );
    setState(() => _tokens = next);
    widget.onThemeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player & Theme Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Surface Theme Preset', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SurfacePreset.values.map((preset) {
              return ChoiceChip(
                label: Text(preset.label),
                selected: _tokens.surfacePreset == preset,
                onSelected: (_) => _updateTheme(surface: preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Accent Color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: HermesAccentKind.values.map((accent) {
              return ChoiceChip(
                label: Text(accent.label),
                selected: _tokens.accentKind == accent,
                onSelected: (_) => _updateTheme(accent: accent),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Video Renderer Backend (HDR Subtitle Fix)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: VideoRendererBackend.values.map((backend) {
              return ChoiceChip(
                label: Text(backend.label),
                selected: _renderer == backend,
                onSelected: (_) {
                  setState(() => _renderer = backend);
                  widget.onRendererChanged(backend);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Default Video Quality', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: VideoQualityPreset.values.map((quality) {
              return ChoiceChip(
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
    );
  }
}
