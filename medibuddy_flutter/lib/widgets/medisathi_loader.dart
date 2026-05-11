import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/medisathi_colors.dart';

/// Branded loading indicator (replaces bare [CircularProgressIndicator] on main waits).
class MediSathiLoader extends StatefulWidget {
  const MediSathiLoader({
    super.key,
    this.message,
    this.size = 56,
    this.secondaryMessage,
  });

  final String? message;
  final String? secondaryMessage;
  final double size;

  @override
  State<MediSathiLoader> createState() => _MediSathiLoaderState();
}

class _MediSathiLoaderState extends State<MediSathiLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _OrbitPainter(_c.value * 2 * math.pi),
              child: SizedBox.square(
                dimension: widget.size,
                child: Center(
                  child: Icon(Icons.favorite_outline_rounded, size: widget.size * 0.42, color: MediSathiColors.brandBlue),
                ),
              ),
            );
          },
        ),
        if (widget.message != null || widget.secondaryMessage != null) ...[
          const SizedBox(height: 26),
          if (widget.message != null)
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          if (widget.secondaryMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.secondaryMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final ctr = Offset(size.width / 2, size.height / 2);
    final rOuter = size.width / 2;
    final sweep = SweepGradient(
      colors: [
        MediSathiColors.neonAccent.withValues(alpha: 0.08),
        MediSathiColors.neonAccent,
        MediSathiColors.brandBlue,
        MediSathiColors.neonAccent.withValues(alpha: 0.08),
      ],
      stops: const [0.0, 0.35, 0.72, 1.0],
      transform: GradientRotation(phase),
    );
    final pb = Paint()
      ..shader = sweep.createShader(Rect.fromCircle(center: ctr, radius: rOuter))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: ctr, radius: rOuter - 2), 0, math.pi * 2, false, pb);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = MediSathiColors.brandBlue.withValues(alpha: 0.18);
    canvas.drawArc(Rect.fromCircle(center: ctr, radius: rOuter - 8), math.pi / 8 + phase, math.pi * 1.05, false, inner);
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => oldDelegate.phase != phase;
}
