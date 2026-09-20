import 'package:flutter/material.dart';

class CustomTitle extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color? subtitleColor;
  
  const CustomTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(.055),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: TextStyle(
                      color: subtitleColor ?? Colors.white38, fontSize: 11,
                      fontWeight: subtitleColor != null
                          ? FontWeight.w700
                          : FontWeight.normal)),
            ],
          ),
        ],
      );
}
