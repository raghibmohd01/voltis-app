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
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
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
                          fontWeight: FontWeight.w800,
                          color: valueColor)),
                ),
              ),
              if (unit.isNotEmpty)
                Text(' $unit',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      );
}
