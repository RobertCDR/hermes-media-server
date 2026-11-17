import 'package:material_ui/material_ui.dart';

import '../theme/hermes_theme_tokens.dart';

/// Borderless, pill-shaped search field that overrides global [InputDecorationTheme]
/// borders so focusing never draws an inner sharp rectangle.
class HermesSearchPill extends StatefulWidget {
  const HermesSearchPill({
    super.key,
    this.inputKey,
    this.clearKey,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.onSubmitted,
    this.darkGlass = false,
    this.height = 42,
    this.iconSize = 18,
    this.hasQuery = false,
    this.autofocus = false,
    this.fontSize = 14,
  });

  final Key? inputKey;
  final Key? clearKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final ValueChanged<String>? onSubmitted;
  final bool darkGlass;
  final double height;
  final double iconSize;
  final bool hasQuery;
  final bool autofocus;
  final double fontSize;

  @override
  State<HermesSearchPill> createState() => _HermesSearchPillState();
}

class _HermesSearchPillState extends State<HermesSearchPill> {
  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_handleFocusChange);
    _focused = _effectiveFocusNode.hasFocus;
  }

  @override
  void didUpdateWidget(covariant HermesSearchPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_handleFocusChange);
      if (widget.focusNode != null && _ownedFocusNode != null) {
        _ownedFocusNode!.dispose();
        _ownedFocusNode = null;
      }
      _effectiveFocusNode.addListener(_handleFocusChange);
      _focused = _effectiveFocusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final nextFocused = _effectiveFocusNode.hasFocus;
    if (nextFocused != _focused) {
      setState(() => _focused = nextFocused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final activeBorder = _focused || widget.hasQuery;

    final fillColor = widget.darkGlass
        ? Colors.black.withValues(alpha: 0.42)
        : tokens.surface2;
    final borderColor = widget.darkGlass
        ? (activeBorder
            ? Colors.white
            : Colors.white.withValues(alpha: 0.16))
        : (activeBorder
            ? tokens.text.withValues(alpha: 0.85)
            : Colors.transparent);
    final foregroundColor = widget.darkGlass ? Colors.white : tokens.text;
    final mutedColor = widget.darkGlass
        ? Colors.white.withValues(alpha: 0.55)
        : tokens.text2;
    final hintColor = widget.darkGlass
        ? Colors.white.withValues(alpha: 0.5)
        : tokens.text3;

    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: widget.iconSize,
              color: mutedColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: widget.inputKey,
                controller: widget.controller,
                focusNode: _effectiveFocusNode,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: widget.fontSize,
                  color: foregroundColor,
                ),
                cursorColor: foregroundColor,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: widget.fontSize,
                    color: hintColor,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
              ),
            ),
            if (widget.hasQuery && widget.onClear != null)
              Tooltip(
                message: 'Clear search',
                child: InkWell(
                  key: widget.clearKey,
                  borderRadius: BorderRadius.circular(99),
                  onTap: () {
                    widget.onClear!();
                    _effectiveFocusNode.requestFocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: widget.iconSize - 1,
                      color: mutedColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
