import 'package:flutter/material.dart';

class AnimatedSolarBar extends StatefulWidget {
  final double pvPower;
  final double maxPower;
  final Color color;

  const AnimatedSolarBar({
    super.key,
    required this.pvPower,
    required this.maxPower,
    required this.color,
  });

  @override
  State<AnimatedSolarBar> createState() => _AnimatedSolarBarState();
}

class _AnimatedSolarBarState extends State<AnimatedSolarBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillFraction = (widget.pvPower / widget.maxPower).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fillFraction,
            child: AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) {
                return Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [
                        widget.color.withOpacity(0.6),
                        widget.color,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: widget.pvPower > 0
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ShaderMask(
                            shaderCallback: (bounds) {
                              final pos = _shimmerController.value;
                              return LinearGradient(
                                begin: Alignment(-1.0 + 3.0 * pos, 0),
                                end: Alignment(-0.5 + 3.0 * pos, 0),
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withOpacity(0.35),
                                  Colors.transparent,
                                ],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcATop,
                            child: Container(color: widget.color),
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
