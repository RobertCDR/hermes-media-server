import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Single-line text that smoothly loops horizontally when wider than its slot.
class HermesMarqueeText extends StatefulWidget {
  const HermesMarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.velocityPxPerSecond = 32.0,
    this.blankSpace = 44.0,
    this.pauseDuration = const Duration(milliseconds: 1600),
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final double velocityPxPerSecond;
  final double blankSpace;
  final Duration pauseDuration;
  final TextAlign textAlign;

  @override
  State<HermesMarqueeText> createState() => _HermesMarqueeTextState();
}

class _HermesMarqueeTextState extends State<HermesMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _pauseTimer;
  double _textWidth = 0;
  double _maxWidth = 0;
  double _lineHeight = 0;
  bool _overflowing = false;
  bool _startedForCurrentSize = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant HermesMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocityPxPerSecond != widget.velocityPxPerSecond ||
        oldWidget.blankSpace != widget.blankSpace) {
      _stopLoop();
      _startedForCurrentSize = false;
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _stopLoop() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    if (_controller.isAnimating) {
      _controller.stop();
    }
    _controller.value = 0;
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (!mounted || !_overflowing) return;
    if (status == AnimationStatus.completed) {
      _controller.value = 0;
      _scheduleNextCycle();
    }
  }

  void _scheduleNextCycle() {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(widget.pauseDuration, () {
      if (!mounted || !_overflowing) return;
      final distance = _textWidth + widget.blankSpace;
      final durationMs =
          ((distance / widget.velocityPxPerSecond) * 1000).round().clamp(
                600,
                30000,
              );
      _controller.duration = Duration(milliseconds: durationMs);
      unawaited(_controller.forward(from: 0));
    });
  }

  void _syncOverflowState(
    double availableWidth,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    if (availableWidth <= 0 || !availableWidth.isFinite) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: direction,
      textScaler: textScaler,
    )..layout();

    final measured = painter.width;
    final lineHeight = painter.height;
    painter.dispose();
    final nextOverflow = measured > availableWidth + 1.0;

    if (!nextOverflow) {
      if (_overflowing) {
        _stopLoop();
      }
      _overflowing = false;
      _textWidth = measured;
      _maxWidth = availableWidth;
      _lineHeight = lineHeight;
      _startedForCurrentSize = false;
      return;
    }

    if (!_startedForCurrentSize ||
        (_textWidth - measured).abs() > 1.0 ||
        (_maxWidth - availableWidth).abs() > 1.0) {
      _textWidth = measured;
      _maxWidth = availableWidth;
      _lineHeight = lineHeight;
      _overflowing = true;
      _startedForCurrentSize = true;
      _stopLoop();
      _scheduleNextCycle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _stopLoop();
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      );
    }

    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _syncOverflowState(constraints.maxWidth, direction, textScaler);
        if (!_overflowing) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
            style: widget.style,
          );
        }

        final travel = _textWidth + widget.blankSpace;
        final boxHeight = _lineHeight > 0 ? _lineHeight : 20.0;
        return SizedBox(
          width: constraints.maxWidth,
          height: boxHeight,
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0.0, 0.9, 1.0],
              ).createShader(bounds),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final dx = -_controller.value * travel;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  minHeight: boxHeight,
                  maxHeight: boxHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        style: widget.style,
                      ),
                      SizedBox(width: widget.blankSpace),
                      ExcludeSemantics(
                        child: RichText(
                          maxLines: 1,
                          softWrap: false,
                          textScaler: textScaler,
                          text: TextSpan(
                            text: widget.text,
                            style: DefaultTextStyle.of(context)
                                .style
                                .merge(widget.style),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
