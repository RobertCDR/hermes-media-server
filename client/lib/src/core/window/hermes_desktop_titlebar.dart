import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../theme/hermes_theme_tokens.dart';
import '../widgets/hermes_icons.dart';
import 'hermes_window_bridge.dart';

class HermesDesktopTitleBar extends StatelessWidget {
  const HermesDesktopTitleBar({
    super.key,
    required this.bridge,
    this.onOpenShortcuts,
  });

  final HermesWindowBridge bridge;
  final VoidCallback? onOpenShortcuts;

  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return Material(
      color: tokens.bgRail,
      child: Container(
        key: const Key('hermes-desktop-titlebar'),
        height: height,
        decoration: BoxDecoration(
          color: tokens.bgRail,
          border: Border(
            bottom: BorderSide(
              color: tokens.lineSoft,
            ),
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                const SizedBox(width: 14),
                HermesMarkIcon(size: 14, color: tokens.accent),
                const SizedBox(width: 8),
                Text(
                  'Hermes',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: tokens.text,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('win-drag-area'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(bridge.startDragging()),
                    onDoubleTap: () => unawaited(bridge.toggleMaximize()),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ValueListenableBuilder<String?>(
                        valueListenable: bridge.activeTrackSummary,
                        builder: (context, track, _) {
                          if (track == null || track.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(left: 14, right: 12),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 340),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surface.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: tokens.line,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.music_note_rounded,
                                    size: 12,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      track,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: tokens.text2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _CaptionActionButton(
                  key: const Key('desktop-shortcuts-btn'),
                  semanticLabel: 'Keyboard shortcuts',
                  width: 36,
                  icon: Icons.keyboard_alt_outlined,
                  iconSize: 15,
                  normalFg: tokens.text3,
                  hoverFg: tokens.text,
                  hoverBg: tokens.surface3.withValues(alpha: 0.8),
                  onTap: onOpenShortcuts ??
                      () => unawaited(showHermesKeyboardShortcutsDialog(context)),
                ),
                _CaptionActionButton(
                  key: const Key('win-btn-minimize'),
                  semanticLabel: 'Minimize',
                  width: 44,
                  icon: Icons.remove_rounded,
                  iconSize: 16,
                  normalFg: tokens.text2,
                  hoverFg: tokens.text,
                  hoverBg: tokens.surface3.withValues(alpha: 0.85),
                  onTap: () => unawaited(bridge.minimize()),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: bridge.isMaximized,
                  builder: (context, maximized, _) => _CaptionActionButton(
                    key: const Key('win-btn-maximize'),
                    semanticLabel: maximized ? 'Restore' : 'Maximize',
                    width: 44,
                    icon: maximized
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    iconSize: maximized ? 12 : 13,
                    normalFg: tokens.text2,
                    hoverFg: tokens.text,
                    hoverBg: tokens.surface3.withValues(alpha: 0.85),
                    onTap: () => unawaited(bridge.toggleMaximize()),
                  ),
                ),
                _CaptionActionButton(
                  key: const Key('win-btn-close'),
                  semanticLabel: 'Close',
                  width: 46,
                  icon: Icons.close_rounded,
                  iconSize: 16,
                  normalFg: tokens.text2,
                  hoverFg: Colors.white,
                  hoverBg: const Color(0xFFC42B1C),
                  onTap: () => unawaited(bridge.closeWindow()),
                ),
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: bridge.isMaximized,
              builder: (context, maximized, _) {
                if (maximized) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  key: const Key('win-top-resize-strip'),
                  top: 0,
                  left: 0,
                  right: 170,
                  height: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) => unawaited(bridge.startTopResize()),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionActionButton extends StatefulWidget {
  const _CaptionActionButton({
    super.key,
    required this.semanticLabel,
    required this.width,
    required this.icon,
    required this.iconSize,
    required this.normalFg,
    required this.hoverFg,
    required this.hoverBg,
    required this.onTap,
  });

  final String semanticLabel;
  final double width;
  final IconData icon;
  final double iconSize;
  final Color normalFg;
  final Color hoverFg;
  final Color hoverBg;
  final VoidCallback onTap;

  @override
  State<_CaptionActionButton> createState() => _CaptionActionButtonState();
}

class _CaptionActionButtonState extends State<_CaptionActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: widget.width,
            height: HermesDesktopTitleBar.height,
            color: _hovered ? widget.hoverBg : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered ? widget.hoverFg : widget.normalFg,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showHermesKeyboardShortcutsDialog(BuildContext context) {
  final tokens = HermesThemeTokens.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      key: const Key('desktop-shortcuts-dialog'),
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.line),
      ),
      title: Row(
        children: [
          Icon(Icons.keyboard_alt_outlined, size: 20, color: tokens.accent),
          const SizedBox(width: 10),
          Text(
            'Keyboard & Mouse Shortcuts',
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShortcutGroup(
                title: 'Global & Music',
                tokens: tokens,
                entries: const [
                  ('Ctrl + K / /', 'Quick search catalog'),
                  ('Space', 'Play / Pause music'),
                  ('M', 'Mute / Unmute audio'),
                  ('Ctrl / Alt + ← / →', 'Previous / Next track'),
                  ('Media Keys', 'Control playback + live flyout'),
                  ('Wheel on Volume', 'Adjust volume ±5%'),
                ],
              ),
              const SizedBox(height: 16),
              _ShortcutGroup(
                title: 'Navigation & Window',
                tokens: tokens,
                entries: const [
                  ('Mouse 4 / Mouse 5', 'Navigate Back / Forward'),
                  ('F11', 'Toggle borderless fullscreen'),
                  ('?', 'Open this shortcuts sheet'),
                  ('Esc', 'Close overlay / Exit fullscreen'),
                ],
              ),
              const SizedBox(height: 16),
              _ShortcutGroup(
                title: 'Video Player',
                tokens: tokens,
                entries: const [
                  ('Space / K', 'Play / Pause video'),
                  ('← / J  and  → / L', 'Seek ±10 seconds'),
                  ('Double-click / F', 'Toggle fullscreen'),
                  ('Scroll / ↑ / ↓', 'Adjust video volume ±5%'),
                  ('A', 'Cycle Fit / Cover / Stretch'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ShortcutGroup extends StatelessWidget {
  const _ShortcutGroup({
    required this.title,
    required this.tokens,
    required this.entries,
  });

  final String title;
  final HermesThemeTokens tokens;
  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.accent,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surface3,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: tokens.line),
                  ),
                  child: Text(
                    entry.$1,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.$2,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      color: tokens.text2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
