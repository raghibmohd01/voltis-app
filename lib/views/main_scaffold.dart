import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dashboard_view.dart';
import 'statistics_view.dart';
import 'alerts_view.dart';
import '../services/alert_service.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _alertBadgeCount = 0;
  StreamSubscription? _alertSub;
  late AnimationController _badgePulse;

  final List<Widget> _pages = [
    const DashboardView(),
    const StatisticsView(),
    const AlertsView(),
  ];

  @override
  void initState() {
    super.initState();
    _badgePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _alertSub = AlertService.instance.activeAlertStream.listen((alerts) {
      final newCount = alerts.length;
      if (newCount > 0 && newCount != _alertBadgeCount) {
        _badgePulse.forward(from: 0).then((_) => _badgePulse.reverse());
      }
      setState(() => _alertBadgeCount = newCount);
    });

    // Also check current state
    _alertBadgeCount = AlertService.instance.activeAlerts.length;
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _badgePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Allow body to scroll behind the floating nav bar
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B22).withOpacity(0.85),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.dashboard_rounded, 'Dashboard'),
                      _buildNavItem(1, Icons.bar_chart_rounded, 'Statistics'),
                      _buildNavItem(
                          2, Icons.notifications_rounded, 'Alerts',
                          badgeCount: _alertBadgeCount),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      {int badgeCount = 0}) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xFF55D6BE) : Colors.white38;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCirc,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 24 : 16, 
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 26),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: AnimatedBuilder(
                      animation: _badgePulse,
                      builder: (context, child) {
                        final scale = 1.0 + _badgePulse.value * 0.25;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4757),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF4757)
                                      .withOpacity(0.5),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '$badgeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
            // Use AnimatedSize to smoothly animate the text appearance
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCirc,
              child: Row(
                children: [
                  if (isSelected) const SizedBox(width: 8),
                  if (isSelected)
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

