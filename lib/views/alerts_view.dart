import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_event.dart';
import '../services/database_service.dart';
import '../services/hybrid_telemetry_service.dart';
import '../utils/solar_timing_helper.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Full-page view of alert history — grouped by date, with timeline styling.
class AlertsView extends StatefulWidget {
  const AlertsView({super.key});

  @override
  State<AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends State<AlertsView>
    with TickerProviderStateMixin {
  List<AlertEvent> _alerts = [];
  bool _loading = true;
  
  AlertSeverity? _selectedSeverity;
  DateTime? _selectedDate;

  late AnimationController _emptyStateController;
  late AnimationController _headerBellController;

  bool _bgServiceEnabled = false;
  bool _notificationsEnabled = true;
  bool _settingsExpanded = false;

  // Track which alert IDs are expanded for detail view
  final Set<int> _expandedAlerts = {};

  @override
  void initState() {
    super.initState();
    _emptyStateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _headerBellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _initPrefs();
    _loadAlerts(forceSeed: true);
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _bgServiceEnabled = prefs.getBool('bg_service_enabled') ?? false;
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      });
    }
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

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    setState(() {
      _notificationsEnabled = value;
    });
  }

  @override
  void dispose() {
    _emptyStateController.dispose();
    _headerBellController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts({bool forceSeed = false}) async {
    setState(() => _loading = true);

    // Seed historical alerts from Firebase (runs once, or on pull-to-refresh)
    await _seedHistoricalAlerts(force: forceSeed);

    final alerts = await DatabaseService.instance.getAlertHistory();
    debugPrint('=== DATABASE ALERTS DUMP (Total: ${alerts.length}) ===');
    for (final a in alerts) {
      debugPrint('ALERT: id=${a.id}, type=${a.type}, sev=${a.severityLabel}, title="${a.title}", val=${a.value}, time=${a.timestamp}');
    }
    debugPrint('=== END DATABASE ALERTS DUMP ===');

    if (mounted) {
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
      // Ring the bell if there are alerts
      if (alerts.isNotEmpty) {
        _headerBellController.forward(from: 0);
      }
    }
  }

  /// Scans Firebase historical telemetry for threshold breaches and
  /// seeds them as alert events in the local DB.
  Future<void> _seedHistoricalAlerts({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastScan = prefs.getInt('alert_history_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Only re-scan if forced or last scan was >1 hour ago
      if (!force && now - lastScan < 3600000) return;

      final allHistory = await HybridTelemetryService.instance.getAllFirebaseHistory();
      if (allHistory.isEmpty) return;

      // Get existing alert timestamps to avoid duplicates
      final existing = await DatabaseService.instance.getAlertHistory();
      final existingTimestamps = existing.map((a) => a.timestamp.millisecondsSinceEpoch).toSet();

      int seeded = 0;

      AlertSeverity? lastLoadSev;
      AlertSeverity? lastBatSev;
      AlertSeverity? lastGridSev;
      AlertSeverity? lastPvSev;
      AlertSeverity? lastSysSev;

      for (final entry in allHistory.entries) {
        final dayData = entry.value;

        DateTime? pvZeroStreakStart;
        DateTime? pvZeroStreakEnd;

        for (final point in dayData) {
          final ts = point['timestamp'] as int? ?? 0;
          if (ts == 0) continue;

          final load = (point['loadPercentage'] as num?)?.toDouble() ?? 0;
          final bv = (point['batteryVoltage'] as num?)?.toDouble() ?? 0;
          final acIn = (point['acInputVoltage'] as num?)?.toDouble() ?? 0;
          final pvPower = (point['pvPower'] as num?)?.toDouble() ?? 0;
          final acOut = (point['acOutputVoltage'] as num?)?.toDouble() ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          final localDt = dt.toLocal();

          // Check for 30+ minute daytime 0W solar outage (solar switch left OFF)
          final isDaylight = SolarTimingHelper.isDaytimeSolarHours(localDt);
          if (isDaylight && pvPower <= 0.5) {
            pvZeroStreakStart ??= localDt;
            pvZeroStreakEnd = localDt;
          } else {
            if (pvZeroStreakStart != null && pvZeroStreakEnd != null) {
              final durMinutes = pvZeroStreakEnd.difference(pvZeroStreakStart).inMinutes;
              if (durMinutes >= 30) {
                final startStr = '${pvZeroStreakStart.hour.toString().padLeft(2, '0')}:${pvZeroStreakStart.minute.toString().padLeft(2, '0')}';
                final endStr = '${pvZeroStreakEnd.hour.toString().padLeft(2, '0')}:${pvZeroStreakEnd.minute.toString().padLeft(2, '0')}';
                final alertTs = pvZeroStreakStart.millisecondsSinceEpoch;
                if (!existingTimestamps.contains(alertTs)) {
                  await DatabaseService.instance.insertAlert(AlertEvent(
                    severity: AlertSeverity.critical,
                    type: AlertType.pv,
                    title: 'Solar Switch Was OFF — 0W',
                    message: 'Solar output was 0W for $durMinutes mins during sunlight ($startStr – $endStr). Solar switch/breaker was left OFF.',
                    value: 0.0,
                    timestamp: pvZeroStreakStart,
                    isActive: false,
                  ));
                  existingTimestamps.add(alertTs);
                  seeded++;
                }
              }
            }
            pvZeroStreakStart = null;
            pvZeroStreakEnd = null;
          }

          // Check load thresholds
          AlertSeverity? currLoadSev;
          if (load >= 105) currLoadSev = AlertSeverity.critical;
          else if (load >= 95) currLoadSev = AlertSeverity.alert;
          else if (load >= 85) currLoadSev = AlertSeverity.warning;

          if (currLoadSev != null && currLoadSev != lastLoadSev) {
            lastLoadSev = currLoadSev;
            if (!existingTimestamps.contains(ts)) {
              await DatabaseService.instance.insertAlert(AlertEvent(
                severity: currLoadSev,
                type: AlertType.load,
                title: currLoadSev == AlertSeverity.critical ? 'Load Overload — ${load.toStringAsFixed(0)}%' 
                     : currLoadSev == AlertSeverity.alert ? 'Load Near Capacity — ${load.toStringAsFixed(0)}%' 
                     : 'Load Warning — ${load.toStringAsFixed(0)}%',
                message: 'Load was at ${load.toStringAsFixed(0)}%.',
                value: load,
                timestamp: dt,
                isActive: false,
              ));
              existingTimestamps.add(ts);
              seeded++;
            }
          }
          if (lastLoadSev != null) {
            if (lastLoadSev == AlertSeverity.warning && load < 80) lastLoadSev = null;
            else if (lastLoadSev == AlertSeverity.alert && load < 90) lastLoadSev = null;
            else if (lastLoadSev == AlertSeverity.critical && load < 100) lastLoadSev = null;
          }

          // Check battery thresholds
          AlertSeverity? currBatSev;
          if (bv > 0 && bv <= 43.0) currBatSev = AlertSeverity.critical;
          else if (bv > 0 && bv <= 44.5) currBatSev = AlertSeverity.alert;
          else if (bv > 0 && bv <= 46.0) currBatSev = AlertSeverity.warning;

          if (currBatSev != null && currBatSev != lastBatSev) {
            lastBatSev = currBatSev;
            if (!existingTimestamps.contains(ts)) {
              await DatabaseService.instance.insertAlert(AlertEvent(
                severity: currBatSev,
                type: AlertType.battery,
                title: 'Battery ${currBatSev == AlertSeverity.critical ? "Critical" : currBatSev == AlertSeverity.alert ? "Very Low" : "Low"} — ${bv.toStringAsFixed(1)}V',
                message: 'Battery was at ${bv.toStringAsFixed(1)}V.',
                value: bv,
                timestamp: dt,
                isActive: false,
              ));
              existingTimestamps.add(ts);
              seeded++;
            }
          }
          if (lastBatSev != null) {
            if (lastBatSev == AlertSeverity.warning && bv >= 47.5) lastBatSev = null;
            else if (lastBatSev == AlertSeverity.alert && bv >= 46.0) lastBatSev = null;
            else if (lastBatSev == AlertSeverity.critical && bv >= 45.0) lastBatSev = null;
          }

          // Check System (Output Sag)
          AlertSeverity? currSysSev;
          if (acOut > 0 && (acOut < 200 || acOut > 250)) currSysSev = AlertSeverity.warning;
          
          if (currSysSev != null && currSysSev != lastSysSev) {
            lastSysSev = currSysSev;
            if (!existingTimestamps.contains(ts)) {
              await DatabaseService.instance.insertAlert(AlertEvent(
                severity: AlertSeverity.warning,
                type: AlertType.system,
                title: 'Output Voltage Unstable',
                message: 'AC output was ${acOut.toStringAsFixed(0)}V, outside safe limits.',
                value: acOut,
                timestamp: dt,
                isActive: false,
              ));
              existingTimestamps.add(ts);
              seeded++;
            }
          }
          if (lastSysSev != null && acOut >= 200 && acOut <= 250) lastSysSev = null;
        }

        // Check if day ended while streak was active
        if (pvZeroStreakStart != null && pvZeroStreakEnd != null) {
          final durMinutes = pvZeroStreakEnd.difference(pvZeroStreakStart).inMinutes;
          if (durMinutes >= 30) {
            final startStr = '${pvZeroStreakStart.hour.toString().padLeft(2, '0')}:${pvZeroStreakStart.minute.toString().padLeft(2, '0')}';
            final endStr = '${pvZeroStreakEnd.hour.toString().padLeft(2, '0')}:${pvZeroStreakEnd.minute.toString().padLeft(2, '0')}';
            final alertTs = pvZeroStreakStart.millisecondsSinceEpoch;
            if (!existingTimestamps.contains(alertTs)) {
              await DatabaseService.instance.insertAlert(AlertEvent(
                severity: AlertSeverity.critical,
                type: AlertType.pv,
                title: 'Solar Switch Was OFF — 0W',
                message: 'Solar output was 0W for $durMinutes mins during sunlight ($startStr – $endStr). Solar switch/breaker was left OFF.',
                value: 0.0,
                timestamp: pvZeroStreakStart,
                isActive: false,
              ));
              existingTimestamps.add(alertTs);
              seeded++;
            }
          }
        }
      }

      await prefs.setInt('alert_history_scan', now);
      if (seeded > 0) {
        debugPrint('AlertsView: Seeded $seeded historical alerts from Firebase');
      }
    } catch (e) {
      debugPrint('AlertsView: Failed to seed historical alerts: $e');
    }
  }

  Future<void> _clearAllAlerts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF4757).withOpacity(0.12),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  color: Color(0xFFFF4757), size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Clear History',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will permanently remove all alert records.\nThis action cannot be undone.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFF4757).withOpacity(0.12),
              foregroundColor: const Color(0xFFFF4757),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Clear All',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.clearAlertHistory();
      // Reset scan timestamp so historical data can be re-seeded
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alert_history_scan');
      _loadAlerts();
    }
  }

  Future<void> _deleteAlert(AlertEvent alert) async {
    if (alert.id == null) return;
    
    setState(() => _alerts.remove(alert));
    
    await DatabaseService.instance.deleteAlert(alert.id!);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1A1F2B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Icon(_severityIcon(alert.severity),
                  color: _severityColor(alert.severity), size: 16),
              const SizedBox(width: 10),
              const Text('Alert dismissed',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: const Color(0xFF55D6BE),
            onPressed: () async {
              await DatabaseService.instance.insertAlert(alert);
              _loadAlerts();
            },
          ),
        ),
      );
    }
  }

  // Group alerts by date
  Map<String, List<AlertEvent>> _groupByDate() {
    final grouped = <String, List<AlertEvent>>{};
    
    // Apply filters
    final filtered = _alerts.where((a) {
      if (_selectedSeverity != null && a.severity != _selectedSeverity) return false;
      if (_selectedDate != null) {
        if (a.timestamp.year != _selectedDate!.year ||
            a.timestamp.month != _selectedDate!.month ||
            a.timestamp.day != _selectedDate!.day) {
          return false;
        }
      }
      return true;
    });

    for (final alert in filtered) {
      final key = _dateKey(alert.timestamp);
      grouped.putIfAbsent(key, () => []).add(alert);
    }
    return grouped;
  }

  String _dateKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final alertDay = DateTime(dt.year, dt.month, dt.day);

    if (alertDay == today) return 'Today';
    if (alertDay == today.subtract(const Duration(days: 1))) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _severityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        return const Color(0xFFFF4757);
      case AlertSeverity.alert:
        return const Color(0xFFFF6B35);
      case AlertSeverity.warning:
        return const Color(0xFFF39C12);
    }
  }

  IconData _severityIcon(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        return Icons.error_rounded;
      case AlertSeverity.alert:
        return Icons.warning_amber_rounded;
      case AlertSeverity.warning:
        return Icons.info_rounded;
    }
  }

  IconData _typeIcon(AlertType type) {
    switch (type) {
      case AlertType.load:
        return Icons.electric_meter_rounded;
      case AlertType.battery:
        return Icons.battery_alert_rounded;
      case AlertType.grid:
        return Icons.power_rounded;
      case AlertType.pv:
        return Icons.solar_power_rounded;
      case AlertType.system:
        return Icons.monitor_heart_rounded;
    }
  }

  String _typeLabel(AlertType type) {
    switch (type) {
      case AlertType.load:
        return 'Load';
      case AlertType.battery:
        return 'Battery';
      case AlertType.grid:
        return 'Grid';
      case AlertType.pv:
        return 'Solar';
      case AlertType.system:
        return 'System';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = _groupByDate().values.fold<int>(0, (sum, list) => sum + list.length);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadAlerts(forceSeed: true),
          color: const Color(0xFF55D6BE),
          backgroundColor: const Color(0xFF12161E),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Header ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _buildHeader(),
                ),
              ),

              // ── Settings Panel ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildSettingsPanel(),
                ),
              ),

              // ── Severity Filter Chips ───────────────────────────
              if (_alerts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _buildSeverityFilters(),
                  ),
                ),

              // ── Date Filter Chips ──────────────────────────────
              if (_alerts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _buildDateFilters(),
                  ),
                ),

              // ── Content ─────────────────────────────────────────
              if (_loading)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: const Color(0xFF55D6BE),
                            strokeWidth: 2.5,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading alerts...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_alerts.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else if (filteredCount == 0)
                SliverFillRemaining(child: _buildNoResults())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(_buildAlertTimeline()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final critCount = _alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final totalCount = _alerts.length;

    return Row(
      children: [
        // Animated bell icon with gradient background
        AnimatedBuilder(
          animation: _headerBellController,
          builder: (context, child) {
            final shake = _headerBellController.value < 0.5
                ? _headerBellController.value * 0.15
                : (1 - _headerBellController.value) * 0.15;
            return Transform.rotate(
              angle: shake * ((_headerBellController.value * 6).toInt().isEven ? 1 : -1),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF55D6BE), Color(0xFF2FA4FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF55D6BE).withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 22, color: Colors.white),
              ),
            );
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Alerts',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDCE2EC),
                          letterSpacing: -0.3)),
                  const SizedBox(width: 8),
                  if (totalCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF55D6BE).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$totalCount',
                        style: const TextStyle(
                          color: Color(0xFF55D6BE),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'History & Notifications',
                style: TextStyle(
                  color: Color(0xFF8E9BAE),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_alerts.isNotEmpty)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _clearAllAlerts,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.white30, size: 20),
              ),
            ),
          ),
      ],
    );
  }

  // ── SETTINGS PANEL ────────────────────────────────────────────────

  Widget _buildSettingsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12161E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row — tappable to expand/collapse
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _settingsExpanded = !_settingsExpanded),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF55D6BE).withOpacity(0.1),
                      ),
                      child: const Icon(Icons.tune_rounded,
                          color: Color(0xFF55D6BE), size: 16),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Monitoring Settings',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    // Status dots
                    Row(
                      children: [
                        _buildStatusDot(_bgServiceEnabled, 'BG'),
                        const SizedBox(width: 6),
                        _buildStatusDot(_notificationsEnabled, 'Notif'),
                      ],
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _settingsExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withOpacity(0.3), size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                _buildToggleRow(
                  icon: Icons.sync_rounded,
                  iconColor: const Color(0xFF2FA4FF),
                  title: 'Background Monitoring',
                  subtitle: 'Poll inverter when app is closed',
                  value: _bgServiceEnabled,
                  onChanged: _toggleBgService,
                ),
                Divider(height: 1, indent: 62, color: Colors.white.withOpacity(0.04)),
                _buildToggleRow(
                  icon: Icons.notifications_active_outlined,
                  iconColor: const Color(0xFFF39C12),
                  title: 'Push Notifications',
                  subtitle: 'Get alerted for critical issues',
                  value: _notificationsEnabled,
                  onChanged: _toggleNotifications,
                ),
                const SizedBox(height: 4),
              ],
            ),
            crossFadeState: _settingsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(bool active, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF55D6BE) : Colors.white24,
            boxShadow: active
                ? [BoxShadow(color: const Color(0xFF55D6BE).withOpacity(0.4), blurRadius: 4)]
                : [],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white54 : Colors.white24,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withOpacity(0.1),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              value: value,
              activeColor: const Color(0xFF55D6BE),
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── SEVERITY FILTERS ──────────────────────────────────────────────

  Widget _buildSeverityFilters() {
    final critCount = _alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final alertCount = _alerts.where((a) => a.severity == AlertSeverity.alert).length;
    final warnCount = _alerts.where((a) => a.severity == AlertSeverity.warning).length;

    return Row(
      children: [
        _buildSeverityPill(
          'Critical',
          critCount,
          const Color(0xFFFF4757),
          AlertSeverity.critical,
          Icons.error_rounded,
        ),
        const SizedBox(width: 8),
        _buildSeverityPill(
          'Alert',
          alertCount,
          const Color(0xFFFF6B35),
          AlertSeverity.alert,
          Icons.warning_amber_rounded,
        ),
        const SizedBox(width: 8),
        _buildSeverityPill(
          'Warning',
          warnCount,
          const Color(0xFFF39C12),
          AlertSeverity.warning,
          Icons.info_rounded,
        ),
      ],
    );
  }

  Widget _buildSeverityPill(String label, int count, Color color,
      AlertSeverity severity, IconData icon) {
    final isSelected = _selectedSeverity == severity;
    final isFaded = _selectedSeverity != null && !isSelected;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedSeverity = _selectedSeverity == severity ? null : severity;
          });
        },
        child: AnimatedOpacity(
          opacity: isFaded ? 0.35 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.15) : const Color(0xFF12161E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color.withOpacity(0.4) : Colors.white.withOpacity(0.05),
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDCE2EC),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── DATE FILTERS ──────────────────────────────────────────────────

  Widget _buildDateFilters() {
    // Get unique dates from all alerts
    final dates = _alerts.map((a) {
      return DateTime(a.timestamp.year, a.timestamp.month, a.timestamp.day);
    }).toSet().toList();
    
    // Sort descending (newest first)
    dates.sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length + 1, // +1 for "All Dates"
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = _selectedDate == null;
            return _buildDateChip('All Dates', isSelected, () {
              setState(() => _selectedDate = null);
            });
          }

          final date = dates[index - 1];
          final isSelected = _selectedDate != null && 
                             _selectedDate!.year == date.year && 
                             _selectedDate!.month == date.month && 
                             _selectedDate!.day == date.day;

          final label = _dateKey(date);
          return _buildDateChip(label, isSelected, () {
            setState(() => _selectedDate = date);
          });
        },
      ),
    );
  }

  Widget _buildDateChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF55D6BE).withOpacity(0.12)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF55D6BE).withOpacity(0.4)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF55D6BE) : Colors.white54,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── EMPTY STATE ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return AnimatedBuilder(
      animation: _emptyStateController,
      builder: (context, child) {
        final scale = 0.95 + _emptyStateController.value * 0.05;
        final glowOpacity = 0.05 + _emptyStateController.value * 0.1;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF55D6BE).withOpacity(glowOpacity),
                        Colors.transparent,
                      ],
                      radius: 1.2,
                    ),
                    border: Border.all(
                      color: const Color(0xFF55D6BE).withOpacity(0.15),
                    ),
                  ),
                  child: Icon(
                    Icons.shield_rounded,
                    size: 42,
                    color: const Color(0xFF55D6BE)
                        .withOpacity(0.4 + _emptyStateController.value * 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'All Clear',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No alerts have been recorded.\nYour system is running smoothly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.3),
                  height: 1.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.03),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Icon(Icons.filter_list_off_rounded,
                size: 32, color: Colors.white.withOpacity(0.2)),
          ),
          const SizedBox(height: 20),
          Text(
            'No matching alerts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try changing your filters',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.25),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedSeverity = null;
                _selectedDate = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF55D6BE).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF55D6BE).withOpacity(0.2)),
              ),
              child: const Text(
                'Clear Filters',
                style: TextStyle(
                  color: Color(0xFF55D6BE),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ALERT TIMELINE ────────────────────────────────────────────────

  List<Widget> _buildAlertTimeline() {
    final grouped = _groupByDate();
    final widgets = <Widget>[];

    for (final entry in grouped.entries) {
      // Date section header
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
                child: Icon(Icons.calendar_today_rounded,
                    size: 10, color: Colors.white.withOpacity(0.35)),
              ),
              const SizedBox(width: 8),
              Text(
                entry.key.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.value.length}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.2),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );

      // Alert items with staggered animation
      for (int i = 0; i < entry.value.length; i++) {
        final alert = entry.value[i];
        widgets.add(
          _AlertTimelineItem(
            alert: alert,
            color: _severityColor(alert.severity),
            severityIcon: _severityIcon(alert.severity),
            typeIcon: _typeIcon(alert.type),
            typeLabel: _typeLabel(alert.type),
            relativeTime: _relativeTime(alert.timestamp),
            isLast: i == entry.value.length - 1,
            index: i,
            isExpanded: _expandedAlerts.contains(alert.id),
            onTap: () {
              setState(() {
                if (_expandedAlerts.contains(alert.id)) {
                  _expandedAlerts.remove(alert.id);
                } else {
                  _expandedAlerts.add(alert.id ?? 0);
                }
              });
            },
            onDismiss: () => _deleteAlert(alert),
          ),
        );
      }

      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }
}

/// Individual alert item in the timeline with slide-in animation
class _AlertTimelineItem extends StatefulWidget {
  final AlertEvent alert;
  final Color color;
  final IconData severityIcon;
  final IconData typeIcon;
  final String typeLabel;
  final String relativeTime;
  final bool isLast;
  final int index;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _AlertTimelineItem({
    required this.alert,
    required this.color,
    required this.severityIcon,
    required this.typeIcon,
    required this.typeLabel,
    required this.relativeTime,
    required this.isLast,
    required this.index,
    required this.isExpanded,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_AlertTimelineItem> createState() => _AlertTimelineItemState();
}

class _AlertTimelineItemState extends State<_AlertTimelineItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slideAnimation = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Stagger the animation (cap to avoid long waits for large lists)
    final delay = (50 * widget.index).clamp(0, 500);
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${widget.alert.timestamp.hour.toString().padLeft(2, '0')}:${widget.alert.timestamp.minute.toString().padLeft(2, '0')}';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_slideAnimation.value, 0),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Dismissible(
                key: ValueKey(widget.alert.id ?? widget.alert.timestamp.millisecondsSinceEpoch),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => widget.onDismiss(),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFFFF4757).withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: const Color(0xFFFF4757).withOpacity(0.7), size: 22),
                      const SizedBox(height: 2),
                      Text('Dismiss',
                          style: TextStyle(
                            color: const Color(0xFFFF4757).withOpacity(0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: const Color(0xFF131722),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: widget.isExpanded
                            ? widget.color.withOpacity(0.20)
                            : Colors.white.withOpacity(0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Column(
                        children: [
                          // Main card content — soft, eye-friendly layout
                          Padding(
                            padding: const EdgeInsets.all(15),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Type icon — calm squircle container
                                Container(
                                  width: 38,
                                  height: 38,
                                  margin: const EdgeInsets.only(top: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: const Color(0xFF1A2130),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.04),
                                    ),
                                  ),
                                  child: Icon(
                                    widget.typeIcon,
                                    color: const Color(0xFF8E9BAE),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Title & message
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Severity badge + time header
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: widget.color.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              widget.alert.severityLabel,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                                color: widget.color,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          // Time — soft readable slate timestamp
                                          Text(
                                            timeStr,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // Title — soft off-white, no sharp glare/halation
                                      Text(
                                        widget.alert.title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFDCE2EC),
                                          letterSpacing: -0.1,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Message — soothing neutral slate, easy on the eyes
                                      Text(
                                        widget.alert.message,
                                        maxLines: widget.isExpanded ? 10 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: Color(0xFF8E9BAE),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Expanded detail section ──
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F131A),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.04),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Value row
                                    Row(
                                      children: [
                                        _detailItem(
                                          'Value',
                                          _formatValue(widget.alert),
                                          widget.color,
                                        ),
                                        const SizedBox(width: 24),
                                        _detailItem(
                                          'Time',
                                          '${widget.alert.timestamp.hour.toString().padLeft(2, '0')}:${widget.alert.timestamp.minute.toString().padLeft(2, '0')}:${widget.alert.timestamp.second.toString().padLeft(2, '0')}',
                                          const Color(0xFFCBD5E1),
                                        ),
                                        const SizedBox(width: 24),
                                        _detailItem(
                                          'Source',
                                          widget.typeLabel,
                                          const Color(0xFFCBD5E1),
                                        ),
                                      ],
                                    ),
                                    if (widget.alert.message.length > 60) ...[
                                      const SizedBox(height: 10),
                                      Divider(height: 1, color: Colors.white.withOpacity(0.04)),
                                      const SizedBox(height: 9),
                                      Text(
                                        widget.alert.message,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8E9BAE),
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            crossFadeState: widget.isExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 300),
                            sizeCurve: Curves.easeOutCubic,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _formatValue(AlertEvent alert) {
    switch (alert.type) {
      case AlertType.load:
        return '${alert.value.toStringAsFixed(0)}%';
      case AlertType.battery:
        return '${alert.value.toStringAsFixed(1)}V';
      case AlertType.grid:
        return '${alert.value.toStringAsFixed(0)}V';
      case AlertType.pv:
        return '${alert.value.toStringAsFixed(1)}V';
      case AlertType.system:
        return '${alert.value.toStringAsFixed(0)}V';
    }
  }
}
