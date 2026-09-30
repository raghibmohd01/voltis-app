import 'package:flutter/material.dart';
import 'dart:math' as math;

class BatteryDurationTile extends StatefulWidget {
  final double batteryVoltage;
  final double batteryCurrent;
  final double loadPercentage;
  final double pvPower;
  final double acInputVoltage;
  final double soc; // State of charge 0-100

  const BatteryDurationTile({
    super.key,
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.loadPercentage,
    required this.pvPower,
    required this.acInputVoltage,
    required this.soc,
  });

  @override
  State<BatteryDurationTile> createState() => _BatteryDurationTileState();
}

class _BatteryDurationTileState extends State<BatteryDurationTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 48V lead-acid bank capacity in Wh
  // Typical 200Ah tubular battery bank
  static const double _batteryCapacityWh = 9600.0;

  // Minimum useful voltage (cut-off)
  static const double _cutoffVoltage = 44.0;

  ({String duration, String subtitle, Color color, IconData icon, bool isDraining}) _calculateDuration() {
    final double loadWatts = (widget.loadPercentage / 100.0) * 5000.0;
    final bool isOnGrid = widget.acInputVoltage > 50;

    // If grid is available, battery is not draining
    if (isOnGrid) {
      return (
        duration: '∞',
        subtitle: 'Grid power active',
        color: const Color(0xFF55D6BE),
        icon: Icons.power,
        isDraining: false,
      );
    }

    // Calculate net drain (load minus solar contribution)
    double netDrainWatts = loadWatts - widget.pvPower;
    
    // Increased threshold to 80W to prevent toggling due to float charging and sensor noise
    if (netDrainWatts <= 80) {
      // Solar is covering or exceeding the load
      return (
        duration: '∞',
        subtitle: 'Solar sustaining load',
        color: const Color(0xFF2ECC71),
        icon: Icons.wb_sunny_rounded,
        isDraining: false,
      );
    }

    // Use SOC-based estimation
    // Available energy = SOC% * total capacity
    // But we can only use down to ~10% SOC safely
    final double usableSocPercent = (widget.soc - 10).clamp(0, 100);
    final double availableWh = (usableSocPercent / 100.0) * _batteryCapacityWh;

    if (availableWh <= 0 || netDrainWatts <= 0) {
      return (
        duration: '0m',
        subtitle: 'Battery depleted',
        color: Colors.redAccent,
        icon: Icons.battery_alert_rounded,
        isDraining: true,
      );
    }

    final double hoursRemaining = availableWh / netDrainWatts;
    final int totalMinutes = (hoursRemaining * 60).round();

    String durationStr;
    if (totalMinutes >= 1440) {
      // 24 hours or more -> show days
      final int days = totalMinutes ~/ 1440;
      final int remainingHours = (totalMinutes % 1440) ~/ 60;
      durationStr = remainingHours > 0 ? '${days}d ${remainingHours}h' : '${days}d';
    } else if (totalMinutes >= 60) {
      final int hours = totalMinutes ~/ 60;
      final int mins = totalMinutes % 60;
      durationStr = '${hours}h ${mins}m';
    } else {
      durationStr = '${totalMinutes}m';
    }

    // Color based on remaining time
    Color timeColor;
    if (totalMinutes <= 30) {
      timeColor = Colors.redAccent;
    } else if (totalMinutes <= 90) {
      timeColor = Colors.orangeAccent;
    } else if (totalMinutes <= 180) {
      timeColor = const Color(0xFFF1C40F);
    } else {
      timeColor = const Color(0xFF55D6BE);
    }

    final drainKw = netDrainWatts >= 1000
        ? '${(netDrainWatts / 1000).toStringAsFixed(1)} kW drain'
        : '${netDrainWatts.toStringAsFixed(0)} W drain';

    return (
      duration: durationStr,
      subtitle: drainKw,
      color: timeColor,
      icon: Icons.timer_outlined,
      isDraining: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _calculateDuration();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 72, // Match the exact height of the BatteryDrainTile
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: result.isDraining 
                ? result.color.withOpacity(0.1) 
                : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Animated icon section matches Drain Tile
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  result.icon,
                  size: 28,
                  color: result.color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EST. BATTERY LIFE',
                      style: TextStyle(
                        color: result.color.withOpacity(0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.duration,
                      style: TextStyle(
                        color: result.color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        shadows: result.isDraining
                            ? [
                                Shadow(
                                  color: result.color.withOpacity(0.5),
                                  blurRadius: 8,
                                )
                              ]
                            : [],
                      ),
                    ),
                  ],
                ),
              ),
              // Subtitle on the right side
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    result.subtitle,
                    style: TextStyle(
                      color: result.color.withOpacity(0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (result.isDraining) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${widget.soc.round()}% SOC',
                      style: TextStyle(
                        color: result.color.withOpacity(0.4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
