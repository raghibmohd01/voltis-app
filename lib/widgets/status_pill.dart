import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final bool online;
  const StatusPill({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    final color =
        online ? const Color(0xFF54D6A2) : const Color(0xFFFF6577);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(online ? 'LIVE' : 'OFFLINE',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
