import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/color_helpers.dart';
import 'card_widget.dart';
import 'title_widget.dart';

class LoadProgressBar extends StatefulWidget {
  final double loadPercent;
  final double acOutputVoltage;
  final Color color;
  
  const LoadProgressBar({
    super.key, 
    required this.loadPercent, 
    required this.acOutputVoltage,
    required this.color,
  });

  @override
  State<LoadProgressBar> createState() => _LoadProgressBarState();
}

class _LoadProgressBarState extends State<LoadProgressBar>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // Speed of the sweep and flow
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double estimatedWatts = (widget.loadPercent / 100.0) * 5000.0;
    final double estimatedAmps = widget.acOutputVoltage > 0 ? (estimatedWatts / widget.acOutputVoltage) : 0.0;

    return CustomCard(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _flowController]),
        builder: (context, child) {
          final pulse = _pulseController.value;
          final flow = _flowController.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTitle(
                icon: Icons.electric_meter_rounded,
                title: 'System Load',
                subtitle: getLoadLabel(widget.loadPercent),
                subtitleColor: widget.color,
              ),
              const SizedBox(height: 16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${widget.loadPercent.round()}',
                    style: TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: widget.color.withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Text(
                      '%',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Compact metrics on the right
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${estimatedWatts.toStringAsFixed(0)} W',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${estimatedAmps.toStringAsFixed(1)} A',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.color.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Sleek Modern Progress Bar
              SizedBox(
                height: 16, // Thick pill shape
                width: double.infinity,
                child: CustomPaint(
                  painter: _ModernProgressBarPainter(
                    progress: (widget.loadPercent / 100).clamp(0.0, 1.0),
                    color: widget.color,
                    pulseValue: pulse,
                    flowValue: flow,
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0%',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.3))),
                  Text('50%',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.3))),
                  Text('100%',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.3))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sleek, premium gradient progress bar with modern animations
class _ModernProgressBarPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double pulseValue;
  final double flowValue;

  _ModernProgressBarPainter({
    required this.progress,
    required this.color,
    required this.pulseValue,
    required this.flowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.height / 2;

    // 1. Draw Background Track (Glassmorphic dark inset)
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(trackRect, trackPaint);

    if (progress <= 0.0) return;

    final double activeWidth = size.width * progress;
    final activeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, activeWidth, size.height),
      Radius.circular(radius),
    );

    // 2. Draw Glow behind the active bar
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3 + pulseValue * 0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + pulseValue * 4);
    canvas.drawRRect(activeRect, glowPaint);

    // 3. Draw Active Gradient Fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.4), // Darker at the start
          color, // Bright at the leading edge
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, activeWidth, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(activeRect, fillPaint);

    // 4. Draw Animated Details (Inside the active track)
    if (activeWidth > 0) {
      canvas.save();
      canvas.clipRRect(activeRect);

      // 4A. Sweeping Glass Shimmer
      final double shimmerCenter = (activeWidth + 60) * flowValue - 30; 
      final Paint shimmerPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.4),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(shimmerCenter - 25, 0, 50, size.height))
        ..blendMode = BlendMode.screen;
      
      canvas.drawRect(Rect.fromLTWH(shimmerCenter - 25, 0, 50, size.height), shimmerPaint);

      // 4B. Flowing Energy Particles
      final int particleCount = (activeWidth / 24).ceil();
      for (int i = 0; i < particleCount; i++) {
        // Continuous left-to-right flow
        final double normalizedPhase = (flowValue + (i / particleCount)) % 1.0;
        final double x = activeWidth * normalizedPhase;
        
        // Fades in near start, fades out near the thumb
        final double fade = math.sin(normalizedPhase * math.pi); 
        
        final Paint particlePaint = Paint()
          ..color = Colors.white.withOpacity(0.3 * fade)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        
        canvas.drawLine(Offset(x - 3, size.height / 2), Offset(x + 3, size.height / 2), particlePaint);
      }

      canvas.restore();
    }

    // 5. Draw Leading Edge Energy Node (Thumb)
    if (activeWidth >= size.height) {
      final double thumbX = activeWidth - radius;
      final double thumbY = size.height / 2;

      // Pulsing outer halo
      final haloPaint = Paint()
        ..color = Colors.white.withOpacity(0.3 + pulseValue * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(thumbX, thumbY), radius - 1, haloPaint);
      
      // Core glowing node
      final corePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(thumbX, thumbY), radius - 3, corePaint);

      // Tiny inner energy dot
      final innerDot = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(thumbX, thumbY), 1.5, innerDot);
    }
  }

  @override
  bool shouldRepaint(covariant _ModernProgressBarPainter oldDelegate) => true;
}
