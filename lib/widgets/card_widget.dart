import 'package:flutter/material.dart';

class CustomCard extends StatelessWidget {
  final Widget child;
  const CustomCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF12161E), // Elevated card background
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.04), // Subtle border
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 2,
            )
          ]
        ),
        child: child,
      );
}
