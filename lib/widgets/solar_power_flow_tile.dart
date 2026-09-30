import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/formatters.dart';

class SolarPowerFlowTile extends StatefulWidget {
  final double pvPower;
  final double toBatteryPower;
  final double toLoadPower;
  final Color color;

  const SolarPowerFlowTile({
    super.key,
    required this.pvPower,
    required this.toBatteryPower,
    required this.toLoadPower,
    required this.color,
  });

  @override
  State<SolarPowerFlowTile> createState() => _SolarPowerFlowTileState();
}

class _SolarPowerFlowTileState extends State<SolarPowerFlowTile>
    with TickerProviderStateMixin {
  late AnimationController _flowController;
  late AnimationController _sunRotationController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    // Flowing particles along the paths and ripples
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Slow, continuous rotation for the sun
    _sunRotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 45000), // Extremely slow 45s rotation
    )..repeat();

    // Slow, majestic breathing glow for the sun
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flowController.dispose();
    _sunRotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getDynamicSolarColor(double power) {
    if (power <= 0) return Colors.white24;

    final double normalized = (power / 5000.0).clamp(0.0, 1.0);
    
    if (normalized < 0.15) {
      // 0% - 15%: Deep Orange (Morning/Evening/Heavy Clouds)
      return Color.lerp(const Color(0xFFE65100), const Color(0xFFFF8F00), normalized / 0.15)!;
    } else if (normalized < 0.5) {
      // 15% - 50%: Amber to Golden Yellow (Mid-day or Partly Cloudy)
      return Color.lerp(const Color(0xFFFF8F00), const Color(0xFFFFCA28), (normalized - 0.15) / 0.35)!;
    } else {
      // 50% - 100%: Golden Yellow to Bright Sun Yellow (Peak Noon)
      return Color.lerp(const Color(0xFFFFCA28), const Color(0xFFFFF59D), (normalized - 0.5) / 0.5)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isGenerating = widget.pvPower > 0;
    final Color sunColor = _getDynamicSolarColor(widget.pvPower);

    return AnimatedBuilder(
      animation: Listenable.merge([_flowController, _sunRotationController, _pulseController]),
      builder: (context, child) {
        final pulse = isGenerating ? _pulseController.value : 0.0;
        final rotation = isGenerating ? _sunRotationController.value * 2 * math.pi : 0.0;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: double.infinity,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                // Animated Flow Lines
                if (isGenerating)
                  CustomPaint(
                    size: const Size(double.infinity, 140),
                    painter: _SolarFlowPainter(
                      progress: _flowController.value,
                      color: sunColor,
                      toBatteryPower: widget.toBatteryPower,
                      toLoadPower: widget.toLoadPower,
                    ),
                  ),

                // Main Content Overlay
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      // SUN SECTION (Left)
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // Sun Icon Container
                            Padding(
                              padding: const EdgeInsets.only(left: 2, top: 4),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Transform.rotate(
                                  angle: rotation,
                                  child: CustomPaint(
                                    painter: _WeatherSunPainter(
                                      color: isGenerating ? sunColor : Colors.white24,
                                      pulse: pulse,
                                      intensity: (widget.pvPower / 5000.0).clamp(0.0, 1.0),
                                      isGenerating: isGenerating,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              formatPower(widget.pvPower),
                              style: TextStyle(
                                color: isGenerating ? Colors.white : Colors.white38,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'TOTAL PV',
                              style: TextStyle(
                                color: isGenerating ? widget.color : Colors.white24,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // DESTINATION SECTION (Right)
                      SizedBox(
                        width: 120,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Battery Destination
                            _buildDestination(
                              icon: Icons.battery_charging_full_rounded,
                              label: 'TO BATTERY',
                              power: widget.toBatteryPower,
                              color: const Color(0xFF55D6BE),
                              isActive: widget.toBatteryPower > 0,
                            ),
                            const SizedBox(height: 12),
                            // Load Destination
                            _buildDestination(
                              icon: Icons.home_rounded,
                              label: 'TO LOAD',
                              power: widget.toLoadPower,
                              color: const Color(0xFFF1C40F),
                              isActive: widget.toLoadPower > 0,
                            ),
                          ],
                        ),
                      )
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

  Widget _buildDestination({
    required IconData icon,
    required String label,
    required double power,
    required Color color,
    required bool isActive,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isActive ? formatPower(power) : '0 W',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white38,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: isActive ? color.withOpacity(0.8) : Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.15) : Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? color.withOpacity(0.3) : Colors.transparent,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? color : Colors.white38,
          ),
        ),
      ],
    );
  }
}

/// Custom painter that draws flowing energy paths from the sun to the destinations
class _SolarFlowPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double toBatteryPower;
  final double toLoadPower;

  _SolarFlowPainter({
    required this.progress,
    required this.color,
    required this.toBatteryPower,
    required this.toLoadPower,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Starting point (center of the sun icon in the top left)
    // Padding left 20 + 2 + 22 (half of 44 width) = 44
    // Padding top 16 + 4 + 22 = 42
    final double startX = 44.0;
    final double startY = 42.0;

    // End points (center of the destination icons)
    final double endX = size.width - 36.0;
    final double batteryY = 36.0;
    final double loadY = size.height - 36.0;

    // Draw Battery Path
    if (toBatteryPower > 0) {
      _drawAnimatedPath(
        canvas,
        startX: startX,
        startY: startY,
        endX: endX,
        endY: batteryY,
        particleColor: const Color(0xFF55D6BE),
      );
    }

    // Draw Load Path
    if (toLoadPower > 0) {
      _drawAnimatedPath(
        canvas,
        startX: startX,
        startY: startY,
        endX: endX,
        endY: loadY,
        particleColor: const Color(0xFFF1C40F),
      );
    }
  }

  void _drawAnimatedPath(Canvas canvas,
      {required double startX,
      required double startY,
      required double endX,
      required double endY,
      required Color particleColor}) {
    final Path path = Path();
    path.moveTo(startX, startY);

    // Create a smooth cubic bezier curve
    final controlPointX = startX + (endX - startX) * 0.5;
    path.cubicTo(controlPointX, startY, controlPointX, endY, endX, endY);

    // Draw the faint background track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = particleColor.withOpacity(0.1);
    canvas.drawPath(path, trackPaint);

    // Get path metrics to calculate particle positions
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;

    // Draw 3 particles flowing along the path
    for (int i = 0; i < 3; i++) {
      final particleProgress = (progress + (i * 0.33)) % 1.0;
      final position = metric.getTangentForOffset(metric.length * particleProgress)?.position;

      if (position != null) {
        // Fade in and out at the ends
        final fadeIn = (particleProgress * 4).clamp(0.0, 1.0);
        final fadeOut = ((1.0 - particleProgress) * 4).clamp(0.0, 1.0);
        final opacity = fadeIn * fadeOut;

        if (opacity > 0) {
          // Glow
          final glowPaint = Paint()
            ..color = particleColor.withOpacity(opacity * 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(position, 5, glowPaint);

          // Core
          final corePaint = Paint()
            ..color = particleColor.withOpacity(opacity)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(position, 2, corePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SolarFlowPainter oldDelegate) => true;
}

/// Draws a beautiful, modern weather-app style sun with dynamic light emission
class _WeatherSunPainter extends CustomPainter {
  final Color color;
  final double pulse;
  final double intensity; // 0.0 to 1.0 based on power
  final bool isGenerating;

  _WeatherSunPainter({
    required this.color,
    required this.pulse,
    required this.intensity,
    required this.isGenerating,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final coreRadius = 11.5 + (pulse * 1.0);
    
    // 1. Draw Ambient Light Emission (Smooth falloff)
    if (isGenerating) {
      final maxGlowRadius = 25.0 + (intensity * 30.0) + (pulse * 5.0); 
      
      final emitPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(0.15 + (intensity * 0.15) + (pulse * 0.05)),
            color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxGlowRadius));
        
      canvas.drawCircle(center, maxGlowRadius, emitPaint);
    }

    // 2. Draw Sun Core (Gradient)
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(isGenerating ? 1.0 : 0.8),
          color.withOpacity(isGenerating ? 0.85 : 0.5),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    // 3. Draw 8 rounded sun rays
    final rayPaint = Paint()
      ..color = color.withOpacity(isGenerating ? (0.7 + intensity * 0.3) : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final int numRays = 8;
    final double rayStartRadius = coreRadius + 2.5; // Detached from core
    final double rayEndRadius = rayStartRadius + 2.5 + (pulse * 0.5) + (intensity * 1.0);

    for (int i = 0; i < numRays; i++) {
      final angle = (i * 2 * math.pi) / numRays;
      final start = Offset(
        center.dx + rayStartRadius * math.cos(angle),
        center.dy + rayStartRadius * math.sin(angle),
      );
      final end = Offset(
        center.dx + rayEndRadius * math.cos(angle),
        center.dy + rayEndRadius * math.sin(angle),
      );
      
      canvas.drawLine(start, end, rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherSunPainter oldDelegate) => true;
}


