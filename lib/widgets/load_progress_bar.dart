import 'package:flutter/material.dart';
import '../utils/color_helpers.dart';
import 'status_chip.dart';

class LoadProgressBar extends StatelessWidget {
  final double loadPercent;
  final Color color;
  
  const LoadProgressBar({
    super.key, 
    required this.loadPercent, 
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF11161E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.electric_meter_rounded,
                    size: 20, color: color),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text('SYSTEM LOAD',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
              StatusChip(
                label: getLoadLabel(loadPercent),
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${loadPercent.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 2),
                child: Text('%',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color.withOpacity(0.7))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (loadPercent / 100).clamp(0, 1),
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.7),
                          color,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withOpacity(0.3))),
              Text('50%',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withOpacity(0.3))),
              Text('100%',
                  style: TextStyle(
                      fontSize: 10, color: Colors.white.withOpacity(0.3))),
            ],
          ),
        ],
      ),
    );
  }
}
