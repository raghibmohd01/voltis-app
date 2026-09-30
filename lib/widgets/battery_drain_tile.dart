import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/color_helpers.dart';
import '../utils/formatters.dart';

class BatteryDrainTile extends StatefulWidget {
  final double drainWatts;

  const BatteryDrainTile({
    super.key,
    required this.drainWatts,
  });

  @override
  State<BatteryDrainTile> createState() => _BatteryDrainTileState();
}

class _BatteryDrainTileState extends State<BatteryDrainTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine color based on severity of drain
    final Color color = widget.drainWatts >= 3500 
        ? Colors.redAccent 
        : widget.drainWatts >= 1500 
            ? Colors.orangeAccent 
            : widget.drainWatts >= 500 
                ? Colors.green 
                : Colors.white54;
                
    final IconData icon = widget.drainWatts >= 3500 ? Icons.warning_amber_rounded : Icons.bolt_rounded;

    return AnimatedBuilder(
      animation: _flowController,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            height: 72,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
            ),
            child: Stack(
              children: [
                // Animated background waves
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DrainWavePainter(
                      progress: _flowController.value,
                      color: color,
                    ),
                  ),
                ),
                // Animated particles flowing downwards
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DrainParticlesPainter(
                      progress: _flowController.value,
                      color: color,
                    ),
                  ),
                ),
                // Foreground Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 28,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EST. BATTERY DRAIN',
                              style: TextStyle(
                                color: color.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatPower(widget.drainWatts),
                              style: TextStyle(
                                color: color,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(
                                    color: color.withOpacity(0.5),
                                    blurRadius: 8,
                                  )
                                ]
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draws soft horizontal energy waves in the background
class _DrainWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _DrainWavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw 2 sine waves flowing right
    for (int i = 0; i < 2; i++) {
      final paint = Paint()
        ..color = color.withOpacity(0.04 + i * 0.02)
        ..style = PaintingStyle.fill;

      final path = Path();
      final amplitude = 8.0 + i * 6.0;
      final yOffset = size.height * (0.4 + i * 0.2);
      final phaseShift = progress * math.pi * 2 + i * math.pi * 0.7;

      path.moveTo(0, size.height);
      path.lineTo(0, yOffset);

      for (double x = 0; x <= size.width; x += 2) {
        final y = yOffset + math.sin((x / size.width * 3 * math.pi) + phaseShift) * amplitude;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrainWavePainter oldDelegate) => true;
}

/// Draws glowing particles flowing from top to bottom (energy draining)
class _DrainParticlesPainter extends CustomPainter {
  final double progress;
  final Color color;

  _DrainParticlesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);

    for (int i = 0; i < 8; i++) {
      final lane = i % 3;
      final laneX = size.width * (0.25 + lane * 0.25);

      final phaseOffset = random.nextDouble();
      final speed = 0.6 + random.nextDouble() * 0.4;
      final particleProgress = ((progress * speed + phaseOffset) % 1.0);

      // Y position: flows from top to bottom (draining)
      final y = size.height * particleProgress - 10;

      final wobble = math.sin(particleProgress * math.pi * 4 + i) * 4;
      final x = laneX + wobble;

      final fadeIn = (particleProgress * 3).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - particleProgress) * 3).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut;

      if (opacity <= 0) continue;

      final boltScale = 3.0 + random.nextDouble() * 2.0;
      final cx = x;
      final cy = y;
      
      final boltPath = Path()
        ..moveTo(cx + boltScale * 0.2, cy - boltScale) 
        ..lineTo(cx - boltScale * 0.5, cy + boltScale * 0.1) 
        ..lineTo(cx + boltScale * 0.1, cy + boltScale * 0.1) 
        ..lineTo(cx - boltScale * 0.2, cy + boltScale * 1.2) 
        ..lineTo(cx + boltScale * 0.5, cy) 
        ..lineTo(cx - boltScale * 0.1, cy) 
        ..close();

      final glowPaint = Paint()
        ..color = color.withOpacity(opacity * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(boltPath, glowPaint);

      final corePaint = Paint()
        ..color = color.withOpacity(opacity * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawPath(boltPath, corePaint);

      // Trailing tail (upward, since particles move down)
      final double tailLength = 6.0;
      final tailPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withOpacity(opacity * 0.3),
            color.withOpacity(0),
          ],
        ).createShader(Rect.fromLTWH(cx - 0.5, cy - tailLength, 1, tailLength));
      canvas.drawRect(Rect.fromLTWH(cx - 0.5, cy - tailLength, 1, tailLength), tailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrainParticlesPainter oldDelegate) => true;
}
