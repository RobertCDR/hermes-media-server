part of 'hermes_video_player.dart';

class _PlayerSubtitleCaption extends StatelessWidget {
  const _PlayerSubtitleCaption({
    required this.text,
    required this.color,
    required this.sizePreset,
    required this.backgroundStyle,
  });

  final String text;
  final Color color;
  final SubtitleSizePreset sizePreset;
  final SubtitleBackgroundStyle backgroundStyle;

  static final RegExp _wrappedItalicRe = RegExp(
    r'^<\s*i\b[^>]*>.*<\s*/\s*i\s*>$',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _brTagRe = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _htmlTagRe = RegExp(r'<[^>]+>');

  @override
  Widget build(BuildContext context) {
    final shadows = switch (backgroundStyle) {
      SubtitleBackgroundStyle.shadow => const [
          Shadow(
            color: Color(0xE6000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
          Shadow(
            color: Color(0xE6000000),
            offset: Offset(0, 0),
            blurRadius: 2,
          ),
        ],
      _ => null,
    };

    return Container(
      padding: backgroundStyle == SubtitleBackgroundStyle.box
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
          : EdgeInsets.zero,
      decoration: backgroundStyle == SubtitleBackgroundStyle.box
          ? BoxDecoration(
              color: const Color(0xBF000000),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Builder(
        builder: (context) {
          final trimmed = text.trim();
          final isWrappedItalic = _wrappedItalicRe.hasMatch(trimmed);
          final cleanedText = text
              .replaceAll(_brTagRe, '\n')
              .replaceAll(_htmlTagRe, '')
              .trim();
          return Text(
            cleanedText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Figtree',
              color: color,
              fontSize: sizePreset.playerFontSize,
              fontWeight: FontWeight.w600,
              fontStyle: isWrappedItalic ? FontStyle.italic : FontStyle.normal,
              height: 1.3,
              shadows: shadows,
            ),
          );
        },
      ),
    );
  }
}

enum _TrackPanelTab { subtitles, style, audio, quality }

class _TracksAndQualityPanel extends StatefulWidget {
  const _TracksAndQualityPanel({
    required this.tokens,
    required this.source,
    required this.compact,
    required this.maxWidth,
    required this.maxHeight,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.selectedQuality,
    required this.selectedAspectMode,
    required this.qualityOrder,
    required this.subtitleDelaySeconds,
    required this.subtitleVerticalOffset,
    required this.subtitleSize,
    required this.subtitleBackground,
    required this.subtitleColor,
    required this.onClose,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onSelectQuality,
    required this.onSelectAspectMode,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleOffsetChanged,
    required this.onSubtitleSizeChanged,
    required this.onSubtitleBackgroundChanged,
    required this.onSubtitleColorChanged,
    this.onInteraction,
  });

  final HermesThemeTokens tokens;
  final MediaSourceModel source;
  final bool compact;
  final double maxWidth;
  final double maxHeight;
  final int selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final VideoQualityPreset selectedQuality;
  final VideoAspectMode selectedAspectMode;
  final List<VideoQualityPreset> qualityOrder;
  final double subtitleDelaySeconds;
  final double subtitleVerticalOffset;
  final SubtitleSizePreset subtitleSize;
  final SubtitleBackgroundStyle subtitleBackground;
  final Color subtitleColor;
  final VoidCallback onClose;
  final ValueChanged<int> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final ValueChanged<VideoQualityPreset> onSelectQuality;
  final ValueChanged<VideoAspectMode> onSelectAspectMode;
  final ValueChanged<double> onSubtitleDelayChanged;
  final ValueChanged<double> onSubtitleOffsetChanged;
  final ValueChanged<SubtitleSizePreset> onSubtitleSizeChanged;
  final ValueChanged<SubtitleBackgroundStyle> onSubtitleBackgroundChanged;
  final ValueChanged<Color> onSubtitleColorChanged;
  final VoidCallback? onInteraction;

  @override
  State<_TracksAndQualityPanel> createState() => _TracksAndQualityPanelState();
}

class _TracksAndQualityPanelState extends State<_TracksAndQualityPanel> {
  _TrackPanelTab _activeTab = _TrackPanelTab.subtitles;
  bool _desktopShowStyle = false;

  List<_PanelOption> _audioItems() {
    if (widget.source.audioStreams.isEmpty) {
      return [
        _PanelOption(
          label: widget.source.audioCodec.isEmpty
              ? 'Default audio'
              : widget.source.audioCodec.toUpperCase(),
          active: true,
          onTap: () {},
        ),
      ];
    }
    return widget.source.audioStreams
        .map(
          (s) => _PanelOption(
            label: '${s.language.toUpperCase()} (${s.codec})',
            active: widget.selectedAudioIndex == s.streamIndex,
            onTap: () => widget.onSelectAudio(s.streamIndex),
          ),
        )
        .toList(growable: false);
  }

  List<_PanelOption> _subtitleItems() {
    return [
      _PanelOption(
        label: 'Off',
        active: widget.selectedSubtitleIndex == null,
        onTap: () => widget.onSelectSubtitle(null),
      ),
      ...widget.source.subtitleStreams.map(
        (s) => _PanelOption(
          label: '${s.language.toUpperCase()} (${s.title})',
          active: widget.selectedSubtitleIndex == s.streamIndex,
          onTap: () => widget.onSelectSubtitle(s.streamIndex),
        ),
      ),
    ];
  }

  List<_PanelOption> _qualityItems() {
    return widget.qualityOrder
        .map(
          (q) => _PanelOption(
            label: q == VideoQualityPreset.directPlay
                ? 'Original · ${widget.source.shortTag}'
                : q.label,
            active: widget.selectedQuality == q,
            onTap: () => widget.onSelectQuality(q),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildAspectRow(HermesThemeTokens tokens) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Display',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(width: 4),
        for (final mode in VideoAspectMode.values)
          _HeaderPillChip(
            key: Key('vp-aspect-${mode.name}'),
            label: mode.label,
            selected: widget.selectedAspectMode == mode,
            tokens: tokens,
            onTap: () => widget.onSelectAspectMode(mode),
          ),
      ],
    );
  }

  Widget _buildStyleEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: _SubtitleStyleEditor(
        tokens: widget.tokens,
        delaySeconds: widget.subtitleDelaySeconds,
        verticalOffset: widget.subtitleVerticalOffset,
        sizePreset: widget.subtitleSize,
        backgroundStyle: widget.subtitleBackground,
        color: widget.subtitleColor,
        onDelayChanged: widget.onSubtitleDelayChanged,
        onOffsetChanged: widget.onSubtitleOffsetChanged,
        onSizeChanged: widget.onSubtitleSizeChanged,
        onBackgroundChanged: widget.onSubtitleBackgroundChanged,
        onColorChanged: widget.onSubtitleColorChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final decoration = BoxDecoration(
      color: const Color(0xF2121215),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tokens.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 36,
          offset: Offset(0, 16),
        ),
      ],
    );

    if (widget.compact) {
      return Material(
        color: Colors.transparent,
        child: Container(
          key: const Key('vp-panel'),
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          ),
          padding: const EdgeInsets.all(12),
          decoration: decoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Player settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _CompactTabChip(
                    label: 'Subtitles',
                    selected: _activeTab == _TrackPanelTab.subtitles,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.subtitles);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Style',
                    selected: _activeTab == _TrackPanelTab.style,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.style);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Audio',
                    selected: _activeTab == _TrackPanelTab.audio,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.audio);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Quality',
                    selected: _activeTab == _TrackPanelTab.quality,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.quality);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _activeTab == _TrackPanelTab.style
                    ? _buildStyleEditor()
                    : _activeTab == _TrackPanelTab.quality
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PanelColumn(
                                  title: 'Quality',
                                  tokens: tokens,
                                  items: _qualityItems(),
                                  fillWidth: true,
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: tokens.lineSoft),
                                const SizedBox(height: 10),
                                _buildAspectRow(tokens),
                              ],
                            ),
                          )
                        : _PanelColumn(
                            title: _activeTab == _TrackPanelTab.subtitles
                                ? 'Subtitles'
                                : 'Audio',
                            tokens: tokens,
                            items: _activeTab == _TrackPanelTab.subtitles
                                ? _subtitleItems()
                                : _audioItems(),
                            fillWidth: true,
                          ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('vp-panel'),
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        ),
        padding: const EdgeInsets.all(14),
        decoration: decoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Tracks & subtitles',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 12),
                _HeaderPillChip(
                  label: 'Tracks',
                  selected: !_desktopShowStyle,
                  tokens: tokens,
                  onTap: () {
                    widget.onInteraction?.call();
                    setState(() => _desktopShowStyle = false);
                  },
                ),
                const SizedBox(width: 6),
                _HeaderPillChip(
                  label: 'Subtitle Style',
                  selected: _desktopShowStyle,
                  tokens: tokens,
                  onTap: () {
                    widget.onInteraction?.call();
                    setState(() => _desktopShowStyle = true);
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close panel',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _desktopShowStyle
                  ? _buildStyleEditor()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PanelColumn(
                            title: 'Audio',
                            tokens: tokens,
                            items: _audioItems(),
                          ),
                          const SizedBox(width: 12),
                          _PanelColumn(
                            title: 'Subtitles',
                            tokens: tokens,
                            items: _subtitleItems(),
                          ),
                          const SizedBox(width: 12),
                          _PanelColumn(
                            title: 'Quality',
                            tokens: tokens,
                            items: _qualityItems(),
                          ),
                        ],
                      ),
                    ),
            ),
            if (!_desktopShowStyle) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: tokens.lineSoft),
              const SizedBox(height: 10),
              _buildAspectRow(tokens),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderPillChip extends StatelessWidget {
  const _HeaderPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? tokens.accent : tokens.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ),
    );
  }
}

class _SubtitleStyleEditor extends StatelessWidget {
  const _SubtitleStyleEditor({
    required this.tokens,
    required this.delaySeconds,
    required this.verticalOffset,
    required this.sizePreset,
    required this.backgroundStyle,
    required this.color,
    required this.onDelayChanged,
    required this.onOffsetChanged,
    required this.onSizeChanged,
    required this.onBackgroundChanged,
    required this.onColorChanged,
  });

  final HermesThemeTokens tokens;
  final double delaySeconds;
  final double verticalOffset;
  final SubtitleSizePreset sizePreset;
  final SubtitleBackgroundStyle backgroundStyle;
  final Color color;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onOffsetChanged;
  final ValueChanged<SubtitleSizePreset> onSizeChanged;
  final ValueChanged<SubtitleBackgroundStyle> onBackgroundChanged;
  final ValueChanged<Color> onColorChanged;

  static const List<({String label, Color color})> _colorPresets = [
    (label: 'HDR', color: Color(0xFFD8D8D8)),
    (label: 'White', color: Color(0xFFFFFFFF)),
    (label: 'Yellow', color: Color(0xFFF5D76E)),
    (label: 'Cyan', color: Color(0xFF8CE8FF)),
  ];

  String _formatDelay(double s) {
    if (s.abs() < 0.01) return '0.00s';
    final prefix = s > 0 ? '+' : '';
    return '$prefix${s.toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle('Timing delay'),
        const SizedBox(height: 6),
        Row(
          children: [
            _stepButton(
              key: const Key('vp-sub-delay-minus'),
              label: '-0.25s',
              onTap: () => onDelayChanged(delaySeconds - 0.25),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDelay(delaySeconds),
                  key: const Key('vp-sub-delay-value'),
                  style: const TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _stepButton(
              key: const Key('vp-sub-delay-plus'),
              label: '+0.25s',
              onTap: () => onDelayChanged(delaySeconds + 0.25),
            ),
            if (delaySeconds.abs() >= 0.01) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('vp-sub-delay-reset'),
                onPressed: () => onDelayChanged(0.0),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _sectionTitle('Vertical position')),
            Text(
              '${verticalOffset >= 0 ? '+' : ''}${verticalOffset.round()} px',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: tokens.accent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: tokens.accent,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            key: const Key('vp-sub-offset-slider'),
            value: verticalOffset.clamp(-24.0, 120.0),
            min: -24.0,
            max: 120.0,
            divisions: 24,
            onChanged: onOffsetChanged,
          ),
        ),
        const SizedBox(height: 4),
        _sectionTitle('Text size'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in SubtitleSizePreset.values)
              _styleChoiceChip(
                label: preset.label,
                selected: sizePreset == preset,
                onTap: () => onSizeChanged(preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Background'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final bg in SubtitleBackgroundStyle.values)
              _styleChoiceChip(
                label: bg.label,
                selected: backgroundStyle == bg,
                onTap: () => onBackgroundChanged(bg),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Color'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in _colorPresets)
              _styleChoiceChip(
                label: preset.label,
                swatchColor: preset.color,
                selected: color.toARGB32() == preset.color.toARGB32(),
                onTap: () => onColorChanged(preset.color),
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.65),
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.line),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _styleChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? swatchColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? tokens.accent : tokens.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatchColor != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: swatchColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black54, width: 0.8),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTabChip extends StatelessWidget {
  const _CompactTabChip({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? tokens.accent : tokens.line,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelColumn extends StatelessWidget {
  const _PanelColumn({
    required this.title,
    required this.tokens,
    required this.items,
    this.fillWidth = false,
  });

  final String title;
  final HermesThemeTokens tokens;
  final List<_PanelOption> items;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final column = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!fillWidth)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ...items.map(
            (item) => InkWell(
              borderRadius: BorderRadius.circular(6),
              hoverColor: Colors.white.withValues(alpha: 0.1),
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      child: item.active
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: tokens.accent,
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    if (fillWidth)
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 14,
                            fontWeight: item.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      )
                    else
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 14,
                          fontWeight:
                              item.active ? FontWeight.w700 : FontWeight.w500,
                          color: item.active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (fillWidth) {
      return column;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: column,
    );
  }
}

class _PanelOption {
  const _PanelOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
}

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.tokens,
    required this.autoplay,
    required this.remainingSeconds,
    required this.episodeCode,
    required this.episodeTitle,
    required this.stillUri,
    required this.onPlayNow,
    required this.onDismiss,
  });

  final HermesThemeTokens tokens;
  final bool autoplay;
  final int remainingSeconds;
  final String episodeCode;
  final String episodeTitle;
  final Uri? stillUri;
  final VoidCallback onPlayNow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final countdownProgress =
        ((20 - remainingSeconds.clamp(0, 20)) / 20.0).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        key: const Key('vp-upnext-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xE0101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 112,
                      height: 63,
                      child: HermesArtworkImage(
                        uri: stillUri,
                        fallbackTitle: episodeTitle,
                        showFallbackLabel: false,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          autoplay
                              ? 'Next episode in ${remainingSeconds.clamp(1, 20)}s'
                              : 'Next episode',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          episodeCode.isEmpty
                              ? episodeTitle
                              : '$episodeCode · $episodeTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: onPlayNow,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HermesPlayIcon(
                                      size: 14,
                                      color: Color(0xFF0B0B0B),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Play now',
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0B0B0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: onDismiss,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Center(
                                  widthFactor: 1.0,
                                  child: Text(
                                    'Watch credits',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (autoplay)
              LinearProgressIndicator(
                value: countdownProgress,
                minHeight: 3,
                color: tokens.accent,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}
