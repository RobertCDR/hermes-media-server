import 'package:material_ui/material_ui.dart';

import '../theme/hermes_theme_tokens.dart';

/// Exact vector Hermes emblem traced from the canonical brand mark (`assets/brand/hermes_mark.svg`).
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
      ..fillType = PathFillType.evenOdd
      ..moveTo(12.000 * sx, 1.920 * sy)
      ..lineTo(12.089 * sx, 1.920 * sy)
      ..lineTo(12.310 * sx, 2.290 * sy)
      ..quadraticBezierTo(12.532 * sx, 2.659 * sy, 12.783 * sx, 2.955 * sy)
      ..quadraticBezierTo(13.035 * sx, 3.250 * sy, 13.951 * sx, 4.152 * sy)
      ..quadraticBezierTo(14.867 * sx, 5.053 * sy, 15.237 * sx, 5.349 * sy)
      ..quadraticBezierTo(15.606 * sx, 5.645 * sy, 17.173 * sx, 6.620 * sy)
      ..lineTo(17.143 * sx, 6.827 * sy)
      ..lineTo(16.685 * sx, 6.901 * sy)
      ..quadraticBezierTo(16.227 * sx, 6.975 * sy, 14.690 * sx, 7.477 * sy)
      ..lineTo(14.690 * sx, 7.374 * sy)
      ..quadraticBezierTo(14.690 * sx, 7.270 * sy, 14.823 * sx, 7.152 * sy)
      ..quadraticBezierTo(14.956 * sx, 7.034 * sy, 15.015 * sx, 6.812 * sy)
      ..quadraticBezierTo(15.074 * sx, 6.590 * sy, 15.222 * sx, 6.443 * sy)
      ..lineTo(14.986 * sx, 6.472 * sy)
      ..lineTo(14.897 * sx, 6.177 * sy)
      ..lineTo(14.542 * sx, 6.058 * sy)
      ..lineTo(14.542 * sx, 5.851 * sy)
      ..lineTo(14.306 * sx, 5.881 * sy)
      ..lineTo(14.276 * sx, 5.733 * sy)
      ..lineTo(14.173 * sx, 5.733 * sy)
      ..quadraticBezierTo(14.069 * sx, 5.733 * sy, 13.892 * sx, 5.585 * sy)
      ..lineTo(13.818 * sx, 5.748 * sy)
      ..quadraticBezierTo(13.744 * sx, 5.911 * sy, 13.759 * sx, 6.118 * sy)
      ..quadraticBezierTo(13.774 * sx, 6.324 * sy, 13.714 * sx, 6.546 * sy)
      ..quadraticBezierTo(13.655 * sx, 6.768 * sy, 13.508 * sx, 6.990 * sy)
      ..quadraticBezierTo(13.360 * sx, 7.211 * sy, 12.975 * sx, 7.463 * sy)
      ..quadraticBezierTo(12.591 * sx, 7.714 * sy, 12.177 * sx, 7.758 * sy)
      ..quadraticBezierTo(11.764 * sx, 7.802 * sy, 11.453 * sx, 7.669 * sy)
      ..quadraticBezierTo(11.143 * sx, 7.536 * sy, 10.891 * sx, 7.270 * sy)
      ..quadraticBezierTo(10.640 * sx, 7.004 * sy, 10.537 * sx, 6.753 * sy)
      ..quadraticBezierTo(10.433 * sx, 6.502 * sy, 10.419 * sx, 6.058 * sy)
      ..quadraticBezierTo(10.404 * sx, 5.615 * sy, 10.315 * sx, 5.497 * sy)
      ..lineTo(10.256 * sx, 5.556 * sy)
      ..quadraticBezierTo(10.197 * sx, 5.615 * sy, 9.990 * sx, 5.615 * sy)
      ..lineTo(9.960 * sx, 5.792 * sy)
      ..lineTo(9.724 * sx, 5.763 * sy)
      ..lineTo(9.665 * sx, 5.837 * sy)
      ..quadraticBezierTo(9.606 * sx, 5.911 * sy, 9.428 * sx, 5.940 * sy)
      ..lineTo(9.384 * sx, 6.044 * sy)
      ..quadraticBezierTo(9.340 * sx, 6.147 * sy, 9.074 * sx, 6.236 * sy)
      ..lineTo(9.044 * sx, 6.457 * sy)
      ..quadraticBezierTo(9.014 * sx, 6.679 * sy, 9.162 * sx, 6.930 * sy)
      ..quadraticBezierTo(9.310 * sx, 7.182 * sy, 9.798 * sx, 7.477 * sy)
      ..quadraticBezierTo(10.286 * sx, 7.773 * sy, 10.729 * sx, 7.921 * sy)
      ..quadraticBezierTo(11.172 * sx, 8.069 * sy, 12.310 * sx, 8.098 * sy)
      ..quadraticBezierTo(13.448 * sx, 8.128 * sy, 14.187 * sx, 8.009 * sy)
      ..quadraticBezierTo(14.926 * sx, 7.891 * sy, 15.281 * sx, 7.773 * sy)
      ..quadraticBezierTo(15.636 * sx, 7.655 * sy, 15.872 * sx, 7.714 * sy)
      ..lineTo(15.577 * sx, 8.335 * sy)
      ..quadraticBezierTo(15.281 * sx, 8.955 * sy, 15.104 * sx, 9.547 * sy)
      ..quadraticBezierTo(14.926 * sx, 10.138 * sy, 14.779 * sx, 11.645 * sy)
      ..lineTo(14.261 * sx, 11.926 * sy)
      ..quadraticBezierTo(13.744 * sx, 12.207 * sy, 13.552 * sx, 12.414 * sy)
      ..quadraticBezierTo(13.360 * sx, 12.621 * sy, 13.182 * sx, 12.946 * sy)
      ..quadraticBezierTo(13.005 * sx, 13.271 * sy, 12.946 * sx, 13.700 * sy)
      ..quadraticBezierTo(12.887 * sx, 14.128 * sy, 12.916 * sx, 15.089 * sy)
      ..quadraticBezierTo(12.946 * sx, 16.050 * sy, 13.020 * sx, 16.419 * sy)
      ..quadraticBezierTo(13.094 * sx, 16.789 * sy, 13.448 * sx, 17.809 * sy)
      ..quadraticBezierTo(13.803 * sx, 18.828 * sy, 13.892 * sx, 19.301 * sy)
      ..quadraticBezierTo(13.981 * sx, 19.774 * sy, 13.995 * sx, 20.232 * sy)
      ..quadraticBezierTo(14.010 * sx, 20.691 * sy, 13.936 * sx, 20.971 * sy)
      ..quadraticBezierTo(13.862 * sx, 21.252 * sy, 13.744 * sx, 21.444 * sy)
      ..quadraticBezierTo(13.626 * sx, 21.637 * sy, 13.493 * sx, 21.740 * sy)
      ..quadraticBezierTo(13.360 * sx, 21.844 * sy, 13.049 * sx, 21.962 * sy)
      ..quadraticBezierTo(12.739 * sx, 22.080 * sy, 12.325 * sx, 22.080 * sy)
      ..quadraticBezierTo(11.911 * sx, 22.080 * sy, 11.704 * sx, 22.021 * sy)
      ..quadraticBezierTo(11.497 * sx, 21.962 * sy, 11.231 * sx, 21.784 * sy)
      ..quadraticBezierTo(10.965 * sx, 21.607 * sy, 10.788 * sx, 21.311 * sy)
      ..quadraticBezierTo(10.611 * sx, 21.016 * sy, 10.581 * sx, 20.292 * sy)
      ..quadraticBezierTo(10.552 * sx, 19.567 * sy, 11.098 * sx, 17.646 * sy)
      ..quadraticBezierTo(11.645 * sx, 15.725 * sy, 11.645 * sx, 15.015 * sy)
      ..quadraticBezierTo(11.645 * sx, 14.306 * sy, 11.438 * sx, 13.788 * sy)
      ..quadraticBezierTo(11.231 * sx, 13.271 * sy, 9.369 * sx, 11.291 * sy)
      ..lineTo(9.473 * sx, 11.261 * sy)
      ..quadraticBezierTo(9.576 * sx, 11.231 * sy, 9.842 * sx, 11.394 * sy)
      ..quadraticBezierTo(10.108 * sx, 11.557 * sy, 10.478 * sx, 11.675 * sy)
      ..quadraticBezierTo(10.847 * sx, 11.793 * sy, 11.231 * sx, 11.867 * sy)
      ..quadraticBezierTo(11.616 * sx, 11.941 * sy, 11.956 * sx, 11.941 * sy)
      ..quadraticBezierTo(12.296 * sx, 11.941 * sy, 12.503 * sx, 11.837 * sy)
      ..quadraticBezierTo(12.709 * sx, 11.734 * sy, 12.798 * sx, 11.630 * sy)
      ..quadraticBezierTo(12.887 * sx, 11.527 * sy, 12.946 * sx, 11.335 * sy)
      ..quadraticBezierTo(13.005 * sx, 11.143 * sy, 12.975 * sx, 10.921 * sy)
      ..quadraticBezierTo(12.946 * sx, 10.699 * sy, 12.754 * sx, 10.359 * sy)
      ..quadraticBezierTo(12.562 * sx, 10.019 * sy, 12.103 * sx, 9.620 * sy)
      ..quadraticBezierTo(11.645 * sx, 9.221 * sy, 10.478 * sx, 8.541 * sy)
      ..quadraticBezierTo(9.310 * sx, 7.862 * sy, 6.827 * sx, 6.679 * sy)
      ..lineTo(6.857 * sx, 6.531 * sy)
      ..lineTo(7.256 * sx, 6.354 * sy)
      ..quadraticBezierTo(7.655 * sx, 6.177 * sy, 8.128 * sx, 5.881 * sy)
      ..quadraticBezierTo(8.601 * sx, 5.585 * sy, 9.251 * sx, 5.053 * sy)
      ..quadraticBezierTo(9.901 * sx, 4.521 * sy, 10.448 * sx, 3.930 * sy)
      ..quadraticBezierTo(10.995 * sx, 3.339 * sy, 12.000 * sx, 1.920 * sy)
      ..close()
      ..moveTo(13.035 * sx, 6.029 * sy)
      ..lineTo(12.961 * sx, 6.251 * sy)
      ..quadraticBezierTo(12.887 * sx, 6.472 * sy, 12.591 * sx, 6.650 * sy)
      ..quadraticBezierTo(12.296 * sx, 6.827 * sy, 12.074 * sx, 6.827 * sy)
      ..quadraticBezierTo(11.852 * sx, 6.827 * sy, 11.704 * sx, 6.768 * sy)
      ..quadraticBezierTo(11.557 * sx, 6.709 * sy, 11.084 * sx, 6.177 * sy)
      ..lineTo(11.143 * sx, 6.369 * sy)
      ..quadraticBezierTo(11.202 * sx, 6.561 * sy, 11.335 * sx, 6.694 * sy)
      ..quadraticBezierTo(11.468 * sx, 6.827 * sy, 11.690 * sx, 6.916 * sy)
      ..quadraticBezierTo(11.911 * sx, 7.004 * sy, 12.103 * sx, 7.004 * sy)
      ..quadraticBezierTo(12.296 * sx, 7.004 * sy, 12.562 * sx, 6.827 * sy)
      ..quadraticBezierTo(12.828 * sx, 6.650 * sy, 12.961 * sx, 6.443 * sy)
      ..quadraticBezierTo(13.094 * sx, 6.236 * sy, 13.035 * sx, 6.029 * sy)
      ..close();

    final topColor = Color.lerp(color, const Color(0xFF280005), 0.34)!;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..shader = color.computeLuminance() > 0.7
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, color],
            ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..color = color;

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
