import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/formatters.dart';

class ChargingPowerTile extends StatefulWidget {
  final double chargingPower;
  final Color batteryColor;

  const ChargingPowerTile({
    super.key,
    required this.chargingPower,
    required this.batteryColor,
  });

  @override
  State<ChargingPowerTile> createState() => _ChargingPowerTileState();
}

class _ChargingPowerTileState extends State<ChargingPowerTile>
    with TickerProviderStateMixin {
  late AnimationController _flowController;
  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    // Particles flowing left to right
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    // Bolt icon breathing glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    // Background energy wave
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flowController, _pulseController, _waveController]),
      builder: (context, child) {
        final pulse = _pulseController.value;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: double.infinity,
            height: 82,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.black,
            ),
            child: Stack(
              children: [
                // Background energy waves
                CustomPaint(
                  size: const Size(double.infinity, 82),
                  painter: _EnergyWavePainter(
                    progress: _waveController.value,
                    color: widget.batteryColor,
                  ),
                ),

                // Flowing energy particles
                CustomPaint(
                  size: const Size(double.infinity, 82),
                  painter: _FlowParticlesPainter(
                    progress: _flowController.value,
                    color: widget.batteryColor,
                  ),
                ),

                // Content overlay
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      // Glowing bolt icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.batteryColor.withOpacity(0.1 + pulse * 0.08),
                          boxShadow: [
                            BoxShadow(
                              color: widget.batteryColor.withOpacity(0.15 + pulse * 0.2),
                              blurRadius: 16 + pulse * 10,
                              spreadRadius: pulse * 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 26,
                          color: widget.batteryColor.withOpacity(0.8 + pulse * 0.2),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CHARGING',
                              style: TextStyle(
                                color: widget.batteryColor.withOpacity(0.5 + pulse * 0.2),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              formatPower(widget.chargingPower),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
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
class _EnergyWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _EnergyWavePainter({required this.progress, required this.color});

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
  bool shouldRepaint(covariant _EnergyWavePainter oldDelegate) => true;
}

/// Draws glowing particles flowing from bottom to top (energy rising)
class _FlowParticlesPainter extends CustomPainter {
  final double progress;
  final Color color;

  _FlowParticlesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // Fixed seed for consistent particle positions

    // Generate 8 particles on 3 vertical lanes
    for (int i = 0; i < 8; i++) {
      final lane = i % 3;
      final laneX = size.width * (0.25 + lane * 0.25);

      // Each particle has a different phase offset
      final phaseOffset = random.nextDouble();
      final speed = 0.6 + random.nextDouble() * 0.4;
      final particleProgress = ((progress * speed + phaseOffset) % 1.0);

      // Y position: flows from bottom to top
      final y = size.height * (1.0 - particleProgress) + 10 - 10 * particleProgress;

      // Slight horizontal wobble
      final wobble = math.sin(particleProgress * math.pi * 4 + i) * 4;
      final x = laneX + wobble;

      // Fade in at bottom, full in middle, fade out at top
      final fadeIn = (particleProgress * 3).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - particleProgress) * 3).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut;

      if (opacity <= 0) continue;

      // Draw small bolt instead of dot
      final boltScale = 3.0 + random.nextDouble() * 2.0;
      final cx = x;
      final cy = y;
      
      final boltPath = Path()
        ..moveTo(cx + boltScale * 0.2, cy - boltScale) // Top point
        ..lineTo(cx - boltScale * 0.5, cy + boltScale * 0.1) // Middle left
        ..lineTo(cx + boltScale * 0.1, cy + boltScale * 0.1) // Middle inner
        ..lineTo(cx - boltScale * 0.2, cy + boltScale * 1.2) // Bottom point
        ..lineTo(cx + boltScale * 0.5, cy) // Middle right
        ..lineTo(cx - boltScale * 0.1, cy) // Middle inner 2
        ..close();

      // Particle glow
      final glowPaint = Paint()
        ..color = color.withOpacity(opacity * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(boltPath, glowPaint);

      // Particle core
      final corePaint = Paint()
        ..color = color.withOpacity(opacity * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawPath(boltPath, corePaint);

      // Trailing tail (downward, since particles move up)
      final double tailLength = 6.0; // Shortened tail
      final tailPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(opacity * 0.3),
            color.withOpacity(0),
          ],
        ).createShader(Rect.fromLTWH(cx - 0.5, cy + boltScale, 1, tailLength));
      canvas.drawRect(Rect.fromLTWH(cx - 0.5, cy + boltScale, 1, tailLength), tailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowParticlesPainter oldDelegate) => true;
}
