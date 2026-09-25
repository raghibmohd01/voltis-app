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
  bool _bgServiceEnabled = false;
  int _selectedDay = DateTime.now().day;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _loadStats();
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgServiceEnabled = prefs.getBool('bg_service_enabled') ?? false;
    });
  }

  Future<void> _toggleBgService(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_service_enabled', value);
    setState(() {
      _bgServiceEnabled = value;
    });

    final service = FlutterBackgroundService();
    if (value) {
      await service.startService();
    } else {
      service.invoke("stopService");
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    
    // Fetch chart history from Firebase backend for the selected day
    final history = await HybridTelemetryService.instance.getFirebaseHistoryForDay(_selectedDay);
    
    // Calculate stats dynamically from Firebase data
    double maxLoad = 0.0;
    double maxSolar = 0.0;
    double minBattery = 999.0;
    double minEnergy = 999999.0;
    double maxEnergy = 0.0;
    
    for (var point in history) {
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
    final totalEnergy = (maxEnergy >= minEnergy && minEnergy != 999999.0) ? (maxEnergy - minEnergy) : 0.0;
    
    final today = {
      'maxLoad': maxLoad,
      'maxSolar': maxSolar,
      'minBattery': minBattery,
      'totalEnergy': totalEnergy,
    };
    
    // Fetch all history for 30-day aggregation
    final allHistory = await HybridTelemetryService.instance.getAllFirebaseHistory();
    List<Map<String, dynamic>> thirtyDays = [];
    final now = DateTime.now();
    for (int i = 29; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));
      final dayKey = targetDate.day;
      
      final dayData = allHistory[dayKey];
      if (dayData != null && dayData.isNotEmpty) {
        double dMaxLoad = 0;
        double dMaxSolar = 0;
        double dMinBattery = 999;
        
        for (var pt in dayData) {
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
    setState(() {
      _selectedDay += delta;
      if (_selectedDay < 1) _selectedDay = 31;
      if (_selectedDay > 31) _selectedDay = 1;
    });
    _loadStats();
  }

  String _getFormattedDate(int day) {
    final now = DateTime.now();
    
    if (day == now.day) {
      return 'Today';
    }
    
    final yesterday = now.subtract(const Duration(days: 1));
    if (day == yesterday.day) {
      return 'Yesterday';
    }

    int targetMonth = now.month;
    int targetYear = now.year;

    if (day > now.day) {
      targetMonth--;
      if (targetMonth < 1) {
        targetMonth = 12;
        targetYear--;
      }
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[targetMonth - 1];
    return '$monthName $day';
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
                                fontSize: 27, fontWeight: FontWeight.w800)),
                        Text("Rolling 30-day history",
                            style: TextStyle(color: Colors.white54)),
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
                  child: Text('TODAY', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                  child: Text('LAST 30 DAYS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                  child: Text('GRAPHS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                
                // Today Expanded View
                CustomCard(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: const Text('Daily Trends', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                    subtitle: const Text('Detailed 5-minute interval data', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    iconColor: const Color(0xFF55D6BE),
                    collapsedIconColor: Colors.white70,
                    childrenPadding: const EdgeInsets.only(bottom: 16),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, color: Colors.white70),
                            onPressed: () => _changeDay(-1),
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 8),
                          Text(_getFormattedDate(_selectedDay), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF55D6BE))),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, color: Colors.white70),
                            onPressed: () => _changeDay(1),
                            constraints: const BoxConstraints(),
                          ),
                        ],
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
                      const SizedBox(height: 32),
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
                      const SizedBox(height: 32),
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
                    title: const Text('Last 7 Days', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                    subtitle: const Text('Weekly summary trends', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    iconColor: const Color(0xFF55D6BE),
                    collapsedIconColor: Colors.white70,
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      if (_last7DaysData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Not enough data yet.', style: TextStyle(color: Colors.white54)),
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
                        const SizedBox(height: 32),
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
                    title: const Text('Last 30 Days', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                    subtitle: const Text('Monthly summary trends', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                        const SizedBox(height: 32),
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

                const SizedBox(height: 24),


                const SizedBox(height: 24),
                
                // Section: SETTINGS
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                  child: Text('SETTINGS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
                CustomCard(
                  child: SwitchListTile(
                    title: const Text('Background Alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Poll inverter in background to provide instant overload notifications. Only works on local Wi-Fi, not via Firebase.', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    value: _bgServiceEnabled,
                    activeColor: const Color(0xFF55D6BE),
                    onChanged: (val) => _toggleBgService(val),
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
