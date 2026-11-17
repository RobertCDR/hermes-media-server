import 'package:material_ui/material_ui.dart';

import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_icons.dart';
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
  final void Function(MediaSourceModel source, VideoQualityPreset quality)
      onPlaySource;

  @override
  State<SourceSelectorCard> createState() => _SourceSelectorCardState();
}

class _SourceSelectorCardState extends State<SourceSelectorCard> {
  late VideoQualityPreset _selectedQuality;

  static const _qualityOrder = [
    VideoQualityPreset.p480,
    VideoQualityPreset.p720,
    VideoQualityPreset.p1080,
    VideoQualityPreset.directPlay,
  ];

  @override
  void initState() {
    super.initState();
    _selectedQuality = widget.initialQuality;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stream quality',
            style: TextStyle(
              fontFamily: 'Figtree',
              color: tokens.text2,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          HermesSegmentedControl<VideoQualityPreset>(
            options: _qualityOrder
                .map(
                  (preset) => HermesSegmentOption(
                    value: preset,
                    label: preset.label,
                  ),
                )
                .toList(growable: false),
            selected: _selectedQuality,
            onChanged: (preset) => setState(() => _selectedQuality = preset),
          ),
          const SizedBox(height: 18),
          Text(
            'Available files (${widget.sources.length})',
            style: TextStyle(
              fontFamily: 'Figtree',
              color: tokens.text2,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...widget.sources.map((source) {
            final mbps = (source.bitrateBps / 1000000).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: source.isAvailable
                    ? () => widget.onPlaySource(source, _selectedQuality)
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.lineSoft),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: source.isAvailable
                              ? Colors.white
                              : tokens.surface3,
                        ),
                        child: HermesPlayIcon(
                          size: 16,
                          color: source.isAvailable
                              ? const Color(0xFF0B0B0B)
                              : tokens.text3,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.sourceLabel,
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: tokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${source.videoCodec.toUpperCase()} · ${source.audioCodec.toUpperCase()} · ${source.container.toUpperCase()} · $mbps Mbps',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 12,
                                color: tokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (source.isHdr)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: tokens.accent.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Text(
                            'HDR',
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
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
    );
  }
}
