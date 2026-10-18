import 'package:flutter/material.dart';

class Metric extends StatelessWidget {
  final String label, value, unit;
  final Color? valueColor;
  const Metric(this.label, this.value, this.unit, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: valueColor ?? const Color(0xFFDCE2EC))),
                ),
              ),
              if (unit.isNotEmpty)
                Text(' $unit',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
            ],
          ),
        ],
      );
}
