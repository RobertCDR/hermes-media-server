import 'package:material_ui/material_ui.dart';

import '../theme/hermes_theme_tokens.dart';

/// Exact Hermes wing silhouette from Figma v4 (24x24 grid).
class HermesMarkIcon extends StatelessWidget {
  const HermesMarkIcon({
    super.key,
    this.size = 28,
    this.color,
    this.strokeWidth = 2.0,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? HermesThemeTokens.of(context).accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HermesMarkPainter(
          color: resolvedColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _HermesMarkPainter extends CustomPainter {
  const _HermesMarkPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    final path = Path()
      ..moveTo(4 * sx, 17 * sy)
      ..cubicTo(8 * sx, 14 * sy, 11 * sx, 10 * sy, 13 * sx, 4 * sy)
      ..cubicTo(15 * sx, 9 * sy, 18 * sx, 12 * sy, 20 * sx, 13 * sy)
      ..cubicTo(16 * sx, 14 * sy, 13 * sx, 17 * sy, 11 * sx, 20 * sy)
      ..cubicTo(10 * sx, 18 * sy, 8 * sx, 17 * sy, 4 * sx, 17 * sy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * ((sx + sy) * 0.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HermesMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Optically centered Play triangle (`8.5,5.2 -> 19,12 -> 8.5,18.8` on a 24x24 grid).
class HermesPlayIcon extends StatelessWidget {
  const HermesPlayIcon({
    super.key,
    this.size = 18,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? HermesThemeTokens.of(context).text;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HermesPlayPainter(color: resolvedColor),
      ),
    );
  }
}

class _HermesPlayPainter extends CustomPainter {
  const _HermesPlayPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    final path = Path()
      ..moveTo(8.5 * sx, 5.2 * sy)
      ..lineTo(19.0 * sx, 12.0 * sy)
      ..lineTo(8.5 * sx, 18.8 * sy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HermesPlayPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Crisp dual-bar Pause icon aligned with [HermesPlayIcon] inside circular buttons.
class HermesPauseIcon extends StatelessWidget {
  const HermesPauseIcon({
    super.key,
    this.size = 18,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? HermesThemeTokens.of(context).text;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HermesPausePainter(color: resolvedColor),
      ),
    );
  }
}

class _HermesPausePainter extends CustomPainter {
  const _HermesPausePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(6.5 * sx, 5 * sy, 10 * sx, 19 * sy),
        Radius.circular(1 * sx),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(14 * sx, 5 * sy, 17.5 * sx, 19 * sy),
        Radius.circular(1 * sx),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HermesPausePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Bookmark ribbon icon matching Figma v4 Nuvio detail & watchlist actions.
class HermesBookmarkIcon extends StatelessWidget {
  const HermesBookmarkIcon({
    super.key,
    this.size = 18,
    this.filled = false,
    this.color,
  });

  final double size;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final resolvedColor = color ?? (filled ? tokens.accent : tokens.text);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HermesBookmarkPainter(color: resolvedColor, filled: filled),
      ),
    );
  }
}

class _HermesBookmarkPainter extends CustomPainter {
  const _HermesBookmarkPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    final path = Path()
      ..moveTo(6.5 * sx, 4.5 * sy)
      ..lineTo(17.5 * sx, 4.5 * sy)
      ..lineTo(17.5 * sx, 20.5 * sy)
      ..lineTo(12 * sx, 16 * sy)
      ..lineTo(6.5 * sx, 20.5 * sy)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 2.0 * ((sx + sy) * 0.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HermesBookmarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.filled != filled;
  }
}

class HermesSegmentOption<T> {
  const HermesSegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Flat Figma v4 segmented control (`--surface-2` tray, `--surface-3` active thumb).
class HermesSegmentedControl<T> extends StatelessWidget {
  const HermesSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<HermesSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: options.map((option) {
          final isSelected = option.value == selected;
          return Semantics(
            container: true,
            button: true,
            selected: isSelected,
            excludeSemantics: true,
            label: option.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => onChanged(option.value),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isSelected ? tokens.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  widthFactor: 1.0,
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? tokens.text : tokens.text2,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class HermesDropdownOption<T> {
  const HermesDropdownOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Flat borderless select matching Figma v4 `.select` (`--surface-2`, 4px radius).
class HermesFlatDropdown<T> extends StatelessWidget {
  const HermesFlatDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.minWidth = 210,
  });

  final T value;
  final List<HermesDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            menuMaxHeight: 340,
            dropdownColor: tokens.surface,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: tokens.text2,
            ),
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: tokens.text,
            ),
            items: options
                .map(
                  (opt) => DropdownMenuItem<T>(
                    value: opt.value,
                    child: Text(opt.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}
