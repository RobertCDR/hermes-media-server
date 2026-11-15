import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import 'cinema_models.dart';

class SourceSelectorCard extends StatefulWidget {
  const SourceSelectorCard({
    super.key,
    required this.sources,
    required this.initialQuality,
    required this.onPlaySource,
  });

  final List<MediaSourceModel> sources;
  final VideoQualityPreset initialQuality;
  final void Function(MediaSourceModel source, VideoQualityPreset quality) onPlaySource;

  @override
  State<SourceSelectorCard> createState() => _SourceSelectorCardState();
}

class _SourceSelectorCardState extends State<SourceSelectorCard> {
  late VideoQualityPreset _selectedQuality;

  @override
  void initState() {
    super.initState();
    _selectedQuality = widget.initialQuality;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quality Preset',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VideoQualityPreset.values.map((preset) {
                final selected = _selectedQuality == preset;
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: selected,
                  selectedColor: tokens.accentPrimary.withValues(alpha: 0.28),
                  onSelected: (_) => setState(() => _selectedQuality = preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Available Files (${widget.sources.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ...widget.sources.map((source) {
              final mbps = (source.bitrateBps / 1000000).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: source.isAvailable
                      ? () => widget.onPlaySource(source, _selectedQuality)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgPrimary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          color: source.isAvailable ? tokens.accentPrimary : tokens.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                source.sourceLabel,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${source.videoCodec.toUpperCase()} • ${source.audioCodec.toUpperCase()} • ${source.container.toUpperCase()} • $mbps Mbps',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (source.isHdr)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: tokens.accentPrimary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: tokens.accentPrimary),
                            ),
                            child: Text(
                              'HDR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: tokens.accentHover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
