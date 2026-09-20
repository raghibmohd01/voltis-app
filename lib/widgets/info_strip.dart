import 'package:flutter/material.dart';

class InfoStrip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;
  const InfoStrip({super.key, required this.icon, required this.text, this.iconColor});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 17, color: iconColor ?? const Color(0xFF55D6BE)),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
