import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/alert_event.dart';

/// A premium animated alert card that appears above the System Load widget
/// when a critical/alert/warning condition is active.
///
/// Features:
/// - Pulsing glow border (color matches severity)
/// - Slide-in entrance animation
/// - Shake micro-animation on first appear
/// - Animated severity icon with rotation
/// - Glassmorphic dark card with colored left accent stripe
class CriticalAlertCard extends StatefulWidget {
  final List<AlertEvent> alerts;

  const CriticalAlertCard({super.key, required this.alerts});

  @override
  State<CriticalAlertCard> createState() => _CriticalAlertCardState();
}

class _CriticalAlertCardState extends State<CriticalAlertCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _entranceController;
  late AnimationController _shakeController;
  late AnimationController _iconController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    // Pulsing glow — continuous
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Slide-in entrance
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<double>(begin: -60, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );

    // Shake on entrance
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Rotating / pulsing icon
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    // Start entrance sequence
    _entranceController.forward().then((_) {
      _shakeController.forward();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    _shakeController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Color _severityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        return const Color(0xFFFF4757);
      case AlertSeverity.alert:
        return const Color(0xFFFF6B35);
      case AlertSeverity.warning:
        return const Color(0xFFF39C12);
    }
  }

  IconData _severityIcon(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        return Icons.error_rounded;
      case AlertSeverity.alert:
        return Icons.warning_amber_rounded;
      case AlertSeverity.warning:
        return Icons.info_rounded;
    }
  }

  IconData _typeIcon(AlertType type) {
    switch (type) {
      case AlertType.load:
        return Icons.electric_meter_rounded;
      case AlertType.battery:
        return Icons.battery_alert_rounded;
      case AlertType.grid:
        return Icons.power_rounded;
      case AlertType.pv:
        return Icons.solar_power_rounded;
      case AlertType.system:
        return Icons.monitor_heart_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alerts.isEmpty) return const SizedBox.shrink();

    // Highest severity first
    final sorted = List<AlertEvent>.from(widget.alerts)
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    final topAlert = sorted.first;
    final color = _severityColor(topAlert.severity);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _entranceController,
        _shakeController,
        _iconController,
      ]),
      builder: (context, child) {
        final shake = _shakeController.status == AnimationStatus.forward
            ? math.sin(_shakeAnimation.value * math.pi * 6) * 4
            : 0.0;

        return Transform.translate(
          offset: Offset(shake, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: color.withOpacity(0.3 + _pulseController.value * 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.15 + _pulseController.value * 0.2),
                    blurRadius: 20 + _pulseController.value * 12,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withOpacity(0.12),
                        const Color(0xFF12161E),
                        const Color(0xFF12161E),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        // Colored left accent stripe
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                color,
                                color.withOpacity(0.4 + _pulseController.value * 0.6),
                              ],
                            ),
                          ),
                        ),

                        // Content
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
                                Row(
                                  children: [
                                    // Animated icon
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: color.withOpacity(0.15),
                                        boxShadow: [
                                          BoxShadow(
                                            color: color.withOpacity(
                                                0.2 + _pulseController.value * 0.3),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: Transform.scale(
                                        scale: 0.9 + _iconController.value * 0.15,
                                        child: Icon(
                                          _severityIcon(topAlert.severity),
                                          color: color,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Severity badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: color.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        topAlert.severityLabel,
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    // Type icon
                                    Icon(
                                      _typeIcon(topAlert.type),
                                      color: Colors.white38,
                                      size: 18,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Title
                                Text(
                                  topAlert.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Message
                                Text(
                                  topAlert.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.55),
                                    height: 1.4,
                                  ),
                                ),
                                // Show additional alerts count
                                if (sorted.length > 1) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.notifications_active_rounded,
                                          color: Colors.white38,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '+${sorted.length - 1} more active alert${sorted.length > 2 ? 's' : ''}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white38,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
