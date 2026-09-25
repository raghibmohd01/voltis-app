import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class TelemetryChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String title;
  final String metricKey;
  final Color color;
  final LinearGradient? gradient;
  final bool isArea;
  final bool isDaily;

  const TelemetryChart({
    super.key,
    required this.data,
    required this.title,
    required this.metricKey,
    required this.color,
    this.gradient,
    this.isArea = false,
    this.isDaily = false,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text('No data available yet', style: TextStyle(color: Colors.white54)),
      );
    }

    final spots = data.map((entry) {
      final timestamp = entry['timestamp'] as int;
      final value = (entry[metricKey] as num).toDouble();
      return FlSpot(timestamp.toDouble(), value);
    }).toList();

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final xRange = maxX - minX;

    double actualMin = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double actualMax = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    double finalMinY = 0;
    double finalMaxY = 100;

    if (metricKey == 'batteryVoltage') {
      finalMinY = actualMin < 45.0 ? actualMin : 45.0;
      finalMaxY = actualMax > 55.0 ? actualMax : 55.0;
    } else if (metricKey == 'loadPercentage') {
      finalMinY = actualMin < 5.0 ? actualMin : 5.0;
      finalMaxY = actualMax > 70.0 ? actualMax : 70.0;
    } else if (metricKey == 'pvPower') {
      finalMinY = 0;
      finalMaxY = actualMax > 3900.0 ? actualMax : 3900.0;
    }

    final yRange = finalMaxY - finalMinY;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => Colors.black87,
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((LineBarSpot touchedSpot) {
                      final date = DateTime.fromMillisecondsSinceEpoch(touchedSpot.x.toInt());
                      final formattedDate = isDaily 
                          ? '${date.month}/${date.day}'
                          : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      return LineTooltipItem(
                        '$formattedDate\n${touchedSpot.y.toStringAsFixed(1)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
                handleBuiltInTouches: true,
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yRange > 0 ? yRange / 4 : 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.white12,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xRange > 0 ? xRange / 4 : 1,
                    getTitlesWidget: (value, meta) {
                      if (value == minX || value == maxX) return const SizedBox();
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      final formattedDate = isDaily 
                          ? '${date.month}/${date.day}'
                          : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(formattedDate, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: yRange > 0 ? yRange / 4 : 1,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max) {
                        return Text(value.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 10));
                      }
                      if (yRange > 0 && (meta.max - value).abs() < (yRange / 4) * 0.5) {
                        return const SizedBox.shrink();
                      }
                      return Text(value.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 10));
                    },
                    reservedSize: 40,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: minX,
              maxX: maxX,
              minY: finalMinY,
              maxY: finalMaxY, // Strict upper bound
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: gradient == null ? color : null,
                  gradient: gradient,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: isArea,
                    color: gradient == null ? color.withOpacity(0.2) : null,
                    gradient: gradient != null 
                        ? LinearGradient(
                            colors: gradient!.colors.map((c) => c.withOpacity(0.2)).toList(),
                            stops: gradient!.stops,
                            begin: gradient!.begin,
                            end: gradient!.end,
                          ) 
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
