import 'package:flutter/material.dart';
import 'dart:ui';
import 'dashboard_view.dart';
import 'statistics_view.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DashboardView(),
    const StatisticsView(),
  ];

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

  Widget _buildNavItem(int index, IconData icon, String label) {
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
            Icon(icon, color: color, size: 26),
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
