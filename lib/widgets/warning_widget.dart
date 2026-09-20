import 'package:flutter/material.dart';

class WarningWidget extends StatelessWidget {
  final String message;
  const WarningWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6577).withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFF6577), size: 18),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
      );
}
