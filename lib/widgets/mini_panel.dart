import 'package:flutter/material.dart';

class MiniPanel extends StatelessWidget {
  final String title, text;
  final IconData icon;
  final Color? color;

  const MiniPanel(
      {super.key, required this.title, required this.text, required this.icon, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: color != null ? color!.withOpacity(.1) : Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? Colors.white54),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      );
}
