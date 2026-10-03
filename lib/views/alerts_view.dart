import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert_event.dart';
import '../services/database_service.dart';
import '../services/hybrid_telemetry_service.dart';

/// Full-page view of alert history — grouped by date, with timeline styling.
class AlertsView extends StatefulWidget {
  const AlertsView({super.key});

  @override
  State<AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends State<AlertsView>
    with SingleTickerProviderStateMixin {
  List<AlertEvent> _alerts = [];
  bool _loading = true;
  
  AlertSeverity? _selectedSeverity;
  DateTime? _selectedDate;

  late AnimationController _emptyStateController;

  @override
  void initState() {
    super.initState();
    _emptyStateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _loadAlerts();
  }

  @override
  void dispose() {
    _emptyStateController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => _loading = true);

    // Seed historical alerts from Firebase (runs once, or on pull-to-refresh)
    await _seedHistoricalAlerts();

    final alerts = await DatabaseService.instance.getAlertHistory();
    if (mounted) {
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    }
  }

  /// Scans Firebase historical telemetry for threshold breaches and
  /// seeds them as alert events in the local DB.
  Future<void> _seedHistoricalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastScan = prefs.getInt('alert_history_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Only re-scan if last scan was >1 hour ago (avoid duplicating on every visit)
      if (now - lastScan < 3600000) return;

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

        for (final point in dayData) {
          final ts = point['timestamp'] as int? ?? 0;
          if (ts == 0) continue;

          final load = (point['loadPercentage'] as num?)?.toDouble() ?? 0;
          final bv = (point['batteryVoltage'] as num?)?.toDouble() ?? 0;
          final acIn = (point['acInputVoltage'] as num?)?.toDouble() ?? 0;
          final pvVolt = (point['pvVoltage'] as num?)?.toDouble() ?? 0;
          final acOut = (point['acOutputVoltage'] as num?)?.toDouble() ?? 0;
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);

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

          // Grid and PV alerts disabled for off-grid setup

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
        title: const Text('Clear Alert History',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'This will permanently remove all alert records. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All',
                style: TextStyle(
                    color: Color(0xFFFF4757), fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAlerts,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFFF4757)],
                      ),
                    ),
                    child: const Icon(Icons.notifications_active_rounded,
                        size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alerts',
                            style: TextStyle(
                                fontSize: 27, fontWeight: FontWeight.w800)),
                        Text('History & Events',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                  if (_alerts.isNotEmpty)
                    IconButton(
                      onPressed: _clearAllAlerts,
                      icon: const Icon(Icons.delete_sweep_rounded,
                          color: Colors.white38),
                      tooltip: 'Clear history',
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Stats strip
              if (_alerts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _buildStatsStrip(),
                ),

              const SizedBox(height: 8),
              
              if (_alerts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildDateFilters(),
                ),

              const SizedBox(height: 4),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: CircularProgressIndicator(
                      color: Color(0xFF55D6BE),
                      strokeWidth: 2,
                    ),
                  ),
                )
              else if (_alerts.isEmpty)
                _buildEmptyState()
              else
                ..._buildAlertTimeline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsStrip() {
    final critCount =
        _alerts.where((a) => a.severity == AlertSeverity.critical).length;
    final alertCount =
        _alerts.where((a) => a.severity == AlertSeverity.alert).length;
    final warnCount =
        _alerts.where((a) => a.severity == AlertSeverity.warning).length;

    return Row(
      children: [
        _buildStatChip('CRITICAL', critCount, const Color(0xFFFF4757), AlertSeverity.critical),
        const SizedBox(width: 8),
        _buildStatChip('ALERT', alertCount, const Color(0xFFFF6B35), AlertSeverity.alert),
        const SizedBox(width: 8),
        _buildStatChip('WARNING', warnCount, const Color(0xFFF39C12), AlertSeverity.warning),
      ],
    );
  }

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
          return _buildDateChip(_dateKey(date).toUpperCase(), isSelected, () {
            setState(() => _selectedDate = date);
          });
        },
      ),
    );
  }

  Widget _buildDateChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF55D6BE).withOpacity(0.15) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF55D6BE).withOpacity(0.5) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF55D6BE) : Colors.white60,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color, AlertSeverity severity) {
    final isSelected = _selectedSeverity == severity;
    final isFaded = _selectedSeverity != null && !isSelected;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_selectedSeverity == severity) {
              _selectedSeverity = null; // Toggle off
            } else {
              _selectedSeverity = severity;
            }
          });
        },
        child: Opacity(
          opacity: isFaded ? 0.3 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.2) : color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? color : color.withOpacity(0.15),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: color.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return AnimatedBuilder(
      animation: _emptyStateController,
      builder: (context, child) {
        final scale = 0.95 + _emptyStateController.value * 0.05;
        return Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Column(
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF55D6BE).withOpacity(0.1),
                        const Color(0xFF2FA4FF).withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFF55D6BE).withOpacity(0.2),
                    ),
                  ),
                  child: Icon(
                    Icons.verified_user_rounded,
                    size: 44,
                    color: const Color(0xFF55D6BE)
                        .withOpacity(0.5 + _emptyStateController.value * 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
                  color: Colors.white.withOpacity(0.35),
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildAlertTimeline() {
    final grouped = _groupByDate();
    final widgets = <Widget>[];

    for (final entry in grouped.entries) {
      // Date header
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8, bottom: 10),
          child: Text(
            entry.key.toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );

      // Alert items with staggered animation
      for (int i = 0; i < entry.value.length; i++) {
        widgets.add(
          _AlertTimelineItem(
            alert: entry.value[i],
            color: _severityColor(entry.value[i].severity),
            severityIcon: _severityIcon(entry.value[i].severity),
            typeIcon: _typeIcon(entry.value[i].type),
            isLast: i == entry.value.length - 1,
            index: i,
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
  final bool isLast;
  final int index;

  const _AlertTimelineItem({
    required this.alert,
    required this.color,
    required this.severityIcon,
    required this.typeIcon,
    required this.isLast,
    required this.index,
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
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Stagger the animation
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
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
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF12161E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.color.withOpacity(0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // Colored left stripe
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: widget.color,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                          ),
                        ),
                      ),

                      // Content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // Icon
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.color.withOpacity(0.12),
                                ),
                                child: Icon(
                                  widget.severityIcon,
                                  color: widget.color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title & message
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Severity badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color:
                                                widget.color.withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            widget.alert.severityLabel,
                                            style: TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.8,
                                              color: widget.color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(widget.typeIcon,
                                            size: 12,
                                            color: Colors.white24),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.alert.title,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.alert.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.4),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Timestamp
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white30,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
