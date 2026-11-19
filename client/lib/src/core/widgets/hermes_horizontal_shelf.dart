import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Desktop-friendly horizontal shelf with hover `<` `>` navigation arrows and
/// `Shift + Wheel` horizontal scrolling.
class HermesHorizontalShelf extends StatefulWidget {
  const HermesHorizontalShelf({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.horizontalPadding = 0,
    this.spacing = 14,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double horizontalPadding;
  final double spacing;

  @override
  State<HermesHorizontalShelf> createState() => _HermesHorizontalShelfState();
}

class _HermesHorizontalShelfState extends State<HermesHorizontalShelf> {
  final ScrollController _controller = ScrollController();
  bool _hovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncExtent());
  }

  @override
  void didUpdateWidget(covariant HermesHorizontalShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncExtent());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncExtent)
      ..dispose();
    super.dispose();
  }

  void _syncExtent() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > pos.minScrollExtent + 2;
    final right = pos.pixels < pos.maxScrollExtent - 2;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  void _scrollPage(int direction) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final step = (pos.viewportDimension * 0.78).clamp(240.0, 960.0);
    final target = (_controller.offset + direction * step).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    unawaited(
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : (shift ? event.scrollDelta.dy : 0.0);
    if (delta == 0) return;
    final pos = _controller.position;
    final target = (_controller.offset + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) {
          _syncExtent();
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: Listener(
          onPointerSignal: _handlePointerSignal,
          child: Stack(
            children: [
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  _syncExtent();
                  return false;
                },
                child: ListView.separated(
                  controller: _controller,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.horizontalPadding,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
                  itemBuilder: widget.itemBuilder,
                ),
              ),
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ShelfArrowButton(
                    key: const Key('shelf-scroll-left'),
                    visible: _hovered && _canScrollLeft,
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollPage(-1),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ShelfArrowButton(
                    key: const Key('shelf-scroll-right'),
                    visible: _hovered && _canScrollRight,
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _scrollPage(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfArrowButton extends StatelessWidget {
  const _ShelfArrowButton({
    super.key,
    required this.visible,
    required this.icon,
    required this.onTap,
  });

  final bool visible;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 140),
        child: Material(
          color: const Color(0xC8101015),
          shape: CircleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
