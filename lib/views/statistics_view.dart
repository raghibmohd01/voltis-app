import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/database_service.dart';
import '../widgets/card_widget.dart';
import '../widgets/title_widget.dart';
import '../widgets/metric.dart';
import '../widgets/telemetry_chart.dart';
import '../utils/formatters.dart';
import '../utils/color_helpers.dart';
import '../services/hybrid_telemetry_service.dart';

class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key});

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  Map<String, dynamic>? _todayStats;
  Map<String, dynamic>? _monthStats;
  List<Map<String, dynamic>> _historyData = [];
  List<Map<String, dynamic>> _last7DaysData = [];
  List<Map<String, dynamic>> _last30DaysData = [];
  bool _loading = true;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final isSelectedToday = _selectedDate.year == todayDate.year &&
        _selectedDate.month == todayDate.month &&
        _selectedDate.day == todayDate.day;

    // Fetch chart history for selected date and today (if different)
    final history = await HybridTelemetryService.instance.getFirebaseHistoryForDay(
      _selectedDate.day,
      targetDate: _selectedDate,
    );
    final todayHistory = isSelectedToday 
        ? history 
        : await HybridTelemetryService.instance.getFirebaseHistoryForDay(
            todayDate.day,
            targetDate: todayDate,
          );
    
    // Calculate stats dynamically from today's Firebase data
    double maxLoad = 0.0;
    double maxSolar = 0.0;
    double minBattery = 999.0;
    double minEnergy = 999999.0;
    double maxEnergy = 0.0;
    
    for (var point in todayHistory) {
      final load = (point['loadPercentage'] as num?)?.toDouble() ?? 0.0;
      final solar = (point['pvPower'] as num?)?.toDouble() ?? 0.0;
      final battery = (point['batteryVoltage'] as num?)?.toDouble() ?? 0.0;
      final energy = (point['pvEnergy'] as num?)?.toDouble() ?? 0.0;
      
      if (load > maxLoad) maxLoad = load;
      if (solar > maxSolar) maxSolar = solar;
      if (battery > 0 && battery < minBattery) minBattery = battery;
      
      if (energy > 0 && energy < minEnergy) minEnergy = energy;
      if (energy > maxEnergy) maxEnergy = energy;
    }
    
    if (minBattery == 999.0) minBattery = 0.0;
    // pvEnergy is reported in Watt-hours (Wh); divide by 1000.0 to display kWh
    final totalEnergy = (maxEnergy >= minEnergy && minEnergy != 999999.0) 
        ? ((maxEnergy - minEnergy) / 1000.0) 
        : 0.0;
    
    final today = {
      'maxLoad': maxLoad,
      'maxSolar': maxSolar,
      'minBattery': minBattery,
      'totalEnergy': totalEnergy,
    };
    
    // Fetch all history for 30-day aggregation
    final allHistory = await HybridTelemetryService.instance.getAllFirebaseHistory();
    List<Map<String, dynamic>> thirtyDays = [];
    for (int i = 29; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));
      final dayKey = targetDate.day;
      
      final dayData = allHistory[dayKey];
      if (dayData != null && dayData.isNotEmpty) {
        final startMs = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0).millisecondsSinceEpoch;
        final endMs = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59, 999).millisecondsSinceEpoch;

        final matchingPoints = dayData.where((pt) {
          final ts = pt['timestamp'] as int?;
          return ts != null && ts >= startMs && ts <= endMs;
        }).toList();

        if (matchingPoints.isNotEmpty) {
          double dMaxLoad = 0;
          double dMaxSolar = 0;
          double dMinBattery = 999;
          
          for (var pt in matchingPoints) {
            final l = (pt['loadPercentage'] as num?)?.toDouble() ?? 0;
            final s = (pt['pvPower'] as num?)?.toDouble() ?? 0;
            final b = (pt['batteryVoltage'] as num?)?.toDouble() ?? 0;
            if (l > dMaxLoad) dMaxLoad = l;
            if (s > dMaxSolar) dMaxSolar = s;
            if (b > 0 && b < dMinBattery) dMinBattery = b;
          }
          if (dMinBattery == 999) dMinBattery = 0;
          
          // Midnight timestamp for the daily graph x-axis
          final midnight = DateTime(targetDate.year, targetDate.month, targetDate.day);
          thirtyDays.add({
            'timestamp': midnight.millisecondsSinceEpoch,
            'loadPercentage': dMaxLoad,
            'pvPower': dMaxSolar,
            'batteryVoltage': dMinBattery,
          });
        }
      }
    }
    
    final sevenDays = thirtyDays.length > 7 
        ? thirtyDays.sublist(thirtyDays.length - 7) 
        : thirtyDays;

    // Fallback to SQLite for all-time month stats until we implement Firebase month aggregation
    final month = await DatabaseService.instance.getMonthStats();
    
    if (mounted) {
      setState(() {
        _todayStats = today;
        _monthStats = month;
        _historyData = history;
        _last7DaysData = sevenDays;
        _last30DaysData = thirtyDays;
        _loading = false;
      });
    }
  }

  void _changeDay(int delta) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(const Duration(days: 29));

    final newDate = _selectedDate.add(Duration(days: delta));
    final newDayDate = DateTime(newDate.year, newDate.month, newDate.day);

    if (newDayDate.isAfter(today)) return;
    if (newDayDate.isBefore(earliest)) return;

    setState(() {
      _selectedDate = newDayDate;
    });
    _loadStats();
  }

  String _getFormattedDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    
    if (target.isAtSameMomentAs(today)) {
      return 'Today';
    }
    
    final yesterday = today.subtract(const Duration(days: 1));
    if (target.isAtSameMomentAs(yesterday)) {
      return 'Yesterday';
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[target.month - 1];
    return '$monthName ${target.day}';
  }

  @override
  Widget build(BuildContext context) {
    final maxLoad = _todayStats?['maxLoad'] ?? 0.0;
    final maxSolar = _todayStats?['maxSolar'] ?? 0.0;
    final minBattery = _todayStats?['minBattery'] ?? 0.0;
    final totalEnergy = _todayStats?['totalEnergy'] ?? 0.0;
    
    final monthMaxLoad = _monthStats?['monthMaxLoad'] ?? 0.0;
    final monthMaxSolar = _monthStats?['monthMaxSolar'] ?? 0.0;
    final bestDailyEnergy = _monthStats?['bestDailyEnergy'] ?? 0.0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              const Row(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 38, color: Color(0xFF55D6BE)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Statistics',
                            style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDCE2EC),
                                letterSpacing: -0.3)),
                        Text("Rolling 30-day history",
                            style: TextStyle(color: Color(0xFF8E9BAE))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              AnimatedOpacity(
                opacity: _loading ? 0.4 : 1.0,
                duration: const Duration(milliseconds: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // Section: TODAY
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('TODAY', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, letterSpacing: 1.0, fontSize: 11)),
                ),
                CustomCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Metric('PEAK LOAD', '${(maxLoad as num).toStringAsFixed(1)}', '%', valueColor: getLoadColor((maxLoad as num).toDouble()))),
                          Expanded(child: Metric('PEAK SOLAR', formatPower((maxSolar as num).toDouble()), '', valueColor: getSolarColor((maxSolar as num).toDouble()))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Metric('MIN BATTERY', '${(minBattery as num).toStringAsFixed(1)}', 'V', valueColor: getBatteryColor((minBattery as num).toDouble()))),
                          Expanded(child: Metric('TOTAL ENERGY', '${(totalEnergy as num).toStringAsFixed(1)}', 'kWh', valueColor: Colors.blueAccent)),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Section: LAST 30 DAYS
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('LAST 30 DAYS', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, letterSpacing: 1.0, fontSize: 11)),
                ),
                CustomCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Metric('ALL-TIME LOAD', '${(monthMaxLoad as num).toStringAsFixed(1)}', '%', valueColor: getLoadColor((monthMaxLoad as num).toDouble()))),
                          Expanded(child: Metric('ALL-TIME SOLAR', formatPower((monthMaxSolar as num).toDouble()), '', valueColor: getSolarColor((monthMaxSolar as num).toDouble()))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Metric('BEST DAILY ENERGY', '${(bestDailyEnergy as num).toStringAsFixed(1)}', 'kWh', valueColor: Colors.blueAccent)),
                          Expanded(child: Container()), // Empty placeholder
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                
                // Section: CHARTS
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('GRAPHS', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, letterSpacing: 1.0, fontSize: 11)),
                ),
                
                // Today Expanded View
                CustomCard(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Daily Trends', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDCE2EC))),
                    subtitle: const Text('Detailed 5-minute interval data', style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 12)),
                    iconColor: const Color(0xFF55D6BE),
                    collapsedIconColor: Colors.white70,
                    childrenPadding: const EdgeInsets.only(bottom: 16),
                    children: [
                      Builder(
                        builder: (context) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final earliest = today.subtract(const Duration(days: 29));
                          final isToday = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).isAtSameMomentAs(today);
                          final isEarliest = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).isAtSameMomentAs(earliest);

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left, color: isEarliest ? Colors.white24 : Colors.white70),
                                onPressed: isEarliest ? null : () => _changeDay(-1),
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              Text(_getFormattedDate(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF55D6BE))),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.chevron_right, color: isToday ? Colors.white24 : Colors.white70),
                                onPressed: isToday ? null : () => _changeDay(1),
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TelemetryChart(
                        data: _historyData,
                        title: 'Solar Power (W)',
                        metricKey: 'pvPower',
                        color: const Color(0xFF2ECC71), // fallback
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFF2ECC71)],
                        ),
                        isArea: true,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Divider(color: Colors.white12, height: 1, thickness: 1),
                      ),
                      TelemetryChart(
                        data: _historyData,
                        title: 'Load (%)',
                        metricKey: 'loadPercentage',
                        color: const Color(0xFF2ECC71), // fallback
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFF2ECC71), Color(0xFFF39C12), Color(0xFFE74C3C)],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Divider(color: Colors.white12, height: 1, thickness: 1),
                      ),
                      TelemetryChart(
                        data: _historyData,
                        title: 'Battery Voltage (V)',
                        metricKey: 'batteryVoltage',
                        color: const Color(0xFF2ECC71), // fallback
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFF2ECC71)],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Last 7 Days Collapsed View
                CustomCard(
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: const Text('Last 7 Days', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDCE2EC))),
                    subtitle: const Text('Weekly summary trends', style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 12)),
                    iconColor: const Color(0xFF55D6BE),
                    collapsedIconColor: Colors.white70,
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      if (_last7DaysData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Not enough data yet.', style: TextStyle(color: Color(0xFF8E9BAE))),
                        )
                      else ...[
                        TelemetryChart(
                          data: _last7DaysData,
                          title: 'Peak Solar Power (W)',
                          metricKey: 'pvPower',
                          color: const Color(0xFF2ECC71),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFF2ECC71)],
                          ),
                          isArea: true,
                          isDaily: true,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Divider(color: Colors.white12, height: 1, thickness: 1),
                        ),
                        TelemetryChart(
                          data: _last7DaysData,
                          title: 'Peak Load (%)',
                          metricKey: 'loadPercentage',
                          color: const Color(0xFF2ECC71),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFF2ECC71), Color(0xFFF39C12), Color(0xFFE74C3C)],
                          ),
                          isDaily: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Last 30 Days Collapsed View
                CustomCard(
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: const Text('Last 30 Days', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDCE2EC))),
                    subtitle: const Text('Monthly summary trends', style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 12)),
                    iconColor: const Color(0xFF55D6BE),
                    collapsedIconColor: Colors.white70,
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      if (_last30DaysData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Not enough data yet.', style: TextStyle(color: Colors.white54)),
                        )
                      else ...[
                        TelemetryChart(
                          data: _last30DaysData,
                          title: 'Peak Solar Power (W)',
                          metricKey: 'pvPower',
                          color: const Color(0xFF2ECC71),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFFE74C3C), Color(0xFFF39C12), Color(0xFF2ECC71)],
                          ),
                          isArea: true,
                          isDaily: true,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Divider(color: Colors.white12, height: 1, thickness: 1),
                        ),
                        TelemetryChart(
                          data: _last30DaysData,
                          title: 'Peak Load (%)',
                          metricKey: 'loadPercentage',
                          color: const Color(0xFF2ECC71),
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFF2ECC71), Color(0xFFF39C12), Color(0xFFE74C3C)],
                          ),
                          isDaily: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),

                  ],
                ),
              ),
            ], // End of children: [
          ),
        ),
      ),
    );
  }
}
