import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/formatters.dart';
import '../utils/color_helpers.dart';

class TelemetryChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String title;
  final String metricKey;
  final Color color;
  final LinearGradient? gradient;
  final bool isArea;
  final bool isDaily;
  final String? unit;

  const TelemetryChart({
    super.key,
    required this.data,
    required this.title,
    required this.metricKey,
    required this.color,
    this.gradient,
    this.isArea = false,
    this.isDaily = false,
    this.unit,
  });

  String _formatValue(double val) {
    if (metricKey == 'pvPower') {
      return formatPower(val);
    } else if (metricKey == 'batteryVoltage') {
      return '${val.toStringAsFixed(1)} V';
    } else if (metricKey == 'loadPercentage') {
      return '${val.toStringAsFixed(1)}%';
    }
    return '${val.toStringAsFixed(1)}${unit != null ? ' $unit' : ''}';
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    final values = spots.map((s) => s.y).toList();
    final nonZeroValues = values.where((v) => v > 0).toList();
    final statValues = (metricKey == 'batteryVoltage' && nonZeroValues.isNotEmpty)
        ? nonZeroValues
        : values;

    final double actualMin = statValues.reduce((a, b) => a < b ? a : b);
    final double actualMax = statValues.reduce((a, b) => a > b ? a : b);
    final double avgVal = statValues.reduce((a, b) => a + b) / statValues.length;

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

    Color maxColor = const Color(0xFF2ECC71);
    Color avgColor = const Color(0xFF5B9DFF);
    Color minColor = const Color(0xFFF39C12);

    if (metricKey == 'loadPercentage') {
      maxColor = getLoadColor(actualMax);
      avgColor = const Color(0xFF5B9DFF);
      minColor = getLoadColor(actualMin);
    } else if (metricKey == 'batteryVoltage') {
      maxColor = getBatteryColor(actualMax);
      avgColor = const Color(0xFF5B9DFF);
      minColor = getBatteryColor(actualMin);
    } else if (metricKey == 'pvPower') {
      maxColor = actualMax >= 1500 ? const Color(0xFF2ECC71) : const Color(0xFF55D6BE);
      avgColor = const Color(0xFF55D6BE);
      minColor = const Color(0xFFF39C12);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFFDCE2EC), fontWeight: FontWeight.w600, fontSize: 13.5)),
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
                    color: gradient == null ? color.withValues(alpha: 0.2) : null,
                    gradient: gradient != null 
                        ? LinearGradient(
                            colors: gradient!.colors.map((c) => c.withValues(alpha: 0.2)).toList(),
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
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatTile(
              label: 'MAX',
              value: _formatValue(actualMax),
              icon: Icons.arrow_upward_rounded,
              color: maxColor,
            ),
            const SizedBox(width: 8),
            _buildStatTile(
              label: 'AVG',
              value: _formatValue(avgVal),
              icon: Icons.show_chart_rounded,
              color: avgColor,
            ),
            const SizedBox(width: 8),
            _buildStatTile(
              label: 'LOW',
              value: _formatValue(actualMin),
              icon: Icons.arrow_downward_rounded,
              color: minColor,
            ),
          ],
        ),
      ],
    );
  }
}
