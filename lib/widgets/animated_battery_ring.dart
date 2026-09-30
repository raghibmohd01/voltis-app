import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedBatteryRing extends StatefulWidget {
  final double soc; // 0-100
  final Color color;

  const AnimatedBatteryRing({
    super.key,
    required this.soc,
    required this.color,
  });

  @override
  State<AnimatedBatteryRing> createState() => _AnimatedBatteryRingState();
}

class _AnimatedBatteryRingState extends State<AnimatedBatteryRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glow = _glowController.value;

          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.08 + glow * 0.12),
                      blurRadius: 12 + glow * 8,
                      spreadRadius: glow * 3,
                    ),
                  ],
                ),
              ),
              // Background track
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 9,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.06)),
                ),
              ),
              // Animated SOC arc
              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _GlowArcPainter(
                    progress: widget.soc / 100,
                    color: widget.color,
                    glowIntensity: glow,
                  ),
                ),
              ),
              // Center text
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${widget.soc.round()}%',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: widget.color)),
                  const Text('estimated',
                      style: TextStyle(
                          fontSize: 9, color: Colors.white38)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Custom arc painter with a glowing tip
class _GlowArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double glowIntensity;

  _GlowArcPainter({
    required this.progress,
    required this.color,
    required this.glowIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4.5;
    final sweepAngle = progress * 2 * math.pi;
    const startAngle = -math.pi / 2;

    if (progress <= 0) return;

    // Main arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: [
          color.withOpacity(0.3),
          color.withOpacity(0.7 + glowIntensity * 0.3),
          color,
        ],
        stops: const [0.0, 0.6, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    // Glowing tip at the end of the arc
    final tipAngle = startAngle + sweepAngle;
    final tipX = center.dx + radius * math.cos(tipAngle);
    final tipY = center.dy + radius * math.sin(tipAngle);

    // Glow behind tip
    final glowPaint = Paint()
      ..color = color.withOpacity(0.2 + glowIntensity * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(tipX, tipY), 7, glowPaint);

    // Bright tip dot
    final tipPaint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(tipX, tipY), 3.5, tipPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowArcPainter oldDelegate) => true;
}
