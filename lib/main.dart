
import 'dart:async';
import 'config.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'notification_service.dart';
import 'background_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await registerBackgroundWorker();
  runApp(const InverterDashboardApp());
}

class InverterDashboardApp extends StatelessWidget {
  const InverterDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inverter Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080B10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D6BE),
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATUS COLOR HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Load % → color
Color getLoadColor(double load) {
  if (load >= 80) return const Color(0xFFE74C3C); // red
  if (load >= 51) return const Color(0xFFF39C12); // amber
  if (load >= 31) return const Color(0xFF5B9DFF); // blue
  return const Color(0xFF2ECC71); // green
}

String getLoadLabel(double load) {
  if (load >= 80) return 'Overloaded';
  if (load >= 51) return 'High';
  if (load >= 31) return 'Normal';
  return 'Low';
}

/// Battery voltage → color
Color getBatteryColor(double voltage) {
  if (voltage >= 49) return const Color(0xFF2ECC71); // green – good
  if (voltage >= 48) return const Color(0xFF5B9DFF); // blue – ok
  if (voltage >= 47) return const Color(0xFFF39C12); // amber – low
  if (voltage >= 46) return const Color(0xFFE74C3C); // red – very low
  return const Color(0xFFC0392B); // dark red – critical
}

String getBatteryLabel(double voltage) {
  if (voltage >= 49) return 'Good';
  if (voltage >= 48) return 'OK';
  if (voltage >= 47) return 'Low';
  if (voltage >= 46) return 'Very Low';
  return 'Critical';
}

/// Solar PV power → color
Color getSolarColor(double watts) {
  if (watts >= 3000) return const Color(0xFF1B8A2A); // dark green – excellent
  if (watts >= 1500) return const Color(0xFF2ECC71); // green – good
  if (watts >= 500) return const Color(0xFFF39C12); // amber – moderate
  if (watts >= 1) return const Color(0xFFE74C3C); // red – poor
  return const Color(0xFF888888); // grey – none
}

String getSolarLabel(double watts) {
  if (watts >= 3000) return 'Excellent';
  if (watts >= 1500) return 'Good';
  if (watts >= 500) return 'Moderate';
  if (watts >= 1) return 'Poor';
  return 'None';
}

// ═══════════════════════════════════════════════════════════════════════════
// TELEMETRY MODEL
// ═══════════════════════════════════════════════════════════════════════════

class Telemetry {
  final String status;
  final bool inverterConnected;
  final double batteryVoltage, batteryCurrent;
  final double pvVoltage, pvCurrent, pvPower;
  final double acInputVoltage, acInputFrequency;
  final double acOutputVoltage, acOutputFrequency;
  final double loadPercentage, pvEnergy;
  final int lastUpdateMs;

  const Telemetry({
    required this.status,
    required this.inverterConnected,
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.pvVoltage,
    required this.pvCurrent,
    required this.pvPower,
    required this.acInputVoltage,
    required this.acInputFrequency,
    required this.acOutputVoltage,
    required this.acOutputFrequency,
    required this.loadPercentage,
    required this.pvEnergy,
    required this.lastUpdateMs,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? {});

    double d(String key) {
      final v = data[key];
      return v is num ? v.toDouble() : 0;
    }

    int i(String key) {
      final v = data[key];
      return v is num ? v.toInt() : 0;
    }

    return Telemetry(
      status: '${json['status'] ?? 'offline'}',
      inverterConnected: json['inverter_connected'] == true,
      batteryVoltage: d('batteryVoltage'),
      batteryCurrent: d('batteryCurrent'),
      pvVoltage: d('pvVoltage'),
      pvCurrent: d('pvCurrent'),
      pvPower: d('pvPower'),
      acInputVoltage: d('acInputVoltage'),
      acInputFrequency: d('acInputFrequency'),
      acOutputVoltage: d('acOutputVoltage'),
      acOutputFrequency: d('acOutputFrequency'),
      loadPercentage: d('loadPercentage').clamp(0, 100),
      pvEnergy: d('pvEnergy'),
      lastUpdateMs: i('lastUpdateMs'),
    );
  }

  static const empty = Telemetry(
    status: 'offline',
    inverterConnected: false,
    batteryVoltage: 0,
    batteryCurrent: 0,
    pvVoltage: 0,
    pvCurrent: 0,
    pvPower: 0,
    acInputVoltage: 0,
    acInputFrequency: 0,
    acOutputVoltage: 0,
    acOutputFrequency: 0,
    loadPercentage: 0,
    pvEnergy: 0,
    lastUpdateMs: 0,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// DASHBOARD PAGE
// ═══════════════════════════════════════════════════════════════════════════

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const endpoint = telemetryEndpoint;

  Telemetry telemetry = Telemetry.empty;
  Timer? timer;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    fetchTelemetry();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => fetchTelemetry());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> fetchTelemetry() async {
    try {
      final response = await http
          .get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final next =
          Telemetry.fromJson(jsonDecode(response.body) as Map<String, dynamic>);

      if (!mounted) return;
      setState(() {
        telemetry = next;
        loading = false;
        error = null;
      });

      // Fire in-app notifications for thresholds
      _evaluateNotifications(next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'ESP32 unavailable';
      });
    }
  }

  /// Evaluate thresholds and fire notifications while app is in foreground.
  Future<void> _evaluateNotifications(Telemetry t) async {
    final svc = NotificationService.instance;
    final v = t.batteryVoltage;
    final load = t.loadPercentage;

    // ── Battery ──
    if (v > 0 && v <= 45) {
      if (await NotificationService.shouldNotify('bat45')) {
        await svc.show(
          id: 102,
          title: '🚨 CRITICAL: Battery ${v.toStringAsFixed(1)}V',
          body: 'Battery at critical level! Reduce load immediately.',
          critical: true,
        );
        await NotificationService.markSent('bat45');
      }
    } else if (v > 45 && v <= 46) {
      await NotificationService.clearFlag('bat45');
      if (await NotificationService.shouldNotify('bat46')) {
        await svc.show(
          id: 101,
          title: '🚨 Battery Very Low — ${v.toStringAsFixed(1)}V',
          body: 'Battery voltage is very low. Consider reducing load.',
          critical: true,
        );
        await NotificationService.markSent('bat46');
      }
    } else if (v > 46 && v <= 47) {
      await NotificationService.clearFlag('bat45');
      await NotificationService.clearFlag('bat46');
      if (await NotificationService.shouldNotify('bat47')) {
        await svc.show(
          id: 100,
          title: '⚠️ Battery Low — ${v.toStringAsFixed(1)}V',
          body: 'Battery voltage is getting low.',
        );
        await NotificationService.markSent('bat47');
      }
    } else {
      await NotificationService.clearFlag('bat45');
      await NotificationService.clearFlag('bat46');
      await NotificationService.clearFlag('bat47');
    }

    // ── Load ──
    if (load >= 80) {
      if (await NotificationService.shouldNotify('load80')) {
        await svc.show(
          id: 202,
          title: '🚨 Load Overloaded — ${load.toStringAsFixed(0)}%',
          body: 'Inverter load is critically high!',
          critical: true,
        );
        await NotificationService.markSent('load80');
      }
    } else if (load >= 60) {
      await NotificationService.clearFlag('load80');
      if (await NotificationService.shouldNotify('load60')) {
        await svc.show(
          id: 201,
          title: '⚠️ Load High — ${load.toStringAsFixed(0)}%',
          body: 'Inverter load is high.',
        );
        await NotificationService.markSent('load60');
      }
    } else if (load >= 50) {
      await NotificationService.clearFlag('load80');
      await NotificationService.clearFlag('load60');
      if (await NotificationService.shouldNotify('load50')) {
        await svc.show(
          id: 200,
          title: '⚠️ Load at ${load.toStringAsFixed(0)}%',
          body: 'Inverter load has crossed 50%.',
        );
        await NotificationService.markSent('load50');
      }
    } else {
      await NotificationService.clearFlag('load50');
      await NotificationService.clearFlag('load60');
      await NotificationService.clearFlag('load80');
    }
  }

  double batteryPercent(double voltage) {
    // Approximation for a 48 V tubular/lead-acid bank.
    // Replace later with coulomb counting + calibration for real SOC.
     var points = <double, double>{
      46: 0, 47: 10, 48: 25, 49: 45, 50: 65, 51: 80, 52: 95, 53: 100,
    };
    final keys = points.keys.toList()..sort();
    if (voltage <= keys.first) return 0;
    if (voltage >= keys.last) return 100;
    for (var n = 0; n < keys.length - 1; n++) {
      final a = keys[n], b = keys[n + 1];
      if (voltage >= a && voltage <= b) {
        final f = (voltage - a) / (b - a);
        return points[a]! + (points[b]! - points[a]!) * f;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final online = telemetry.inverterConnected &&
        telemetry.status.toLowerCase() == 'online';
    final soc = batteryPercent(telemetry.batteryVoltage);
    final loadColor = getLoadColor(telemetry.loadPercentage);
    final batteryColor = getBatteryColor(telemetry.batteryVoltage);
    final solarColor = getSolarColor(telemetry.pvPower);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchTelemetry,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF55D6BE), Color(0xFF2FA4FF)],
                      ),
                    ),
                    child: const Icon(Icons.bolt_rounded),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Inverter',
                            style: TextStyle(
                                fontSize: 27, fontWeight: FontWeight.w800)),
                        Text('Live energy dashboard',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: loading ? null : fetchTelemetry,
                    icon: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                  ),
                  _StatusPill(online: online),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                _Warning(message: error!),
              ],

              // ════════════════════════════════════════════════════════════
              // 1. LOAD PROGRESS BAR — TOP WIDGET
              // ════════════════════════════════════════════════════════════
              const SizedBox(height: 16),
              _LoadProgressBar(
                loadPercent: telemetry.loadPercentage,
                color: loadColor,
              ),

              // ════════════════════════════════════════════════════════════
              // BATTERY CARD — with dynamic colors
              // ════════════════════════════════════════════════════════════
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.battery_charging_full_rounded,
                      title: 'Battery',
                      subtitle: telemetry.batteryVoltage > 0
                          ? '48 V • ${getBatteryLabel(telemetry.batteryVoltage)}'
                          : '48 V tubular / lead-acid',
                      subtitleColor: telemetry.batteryVoltage > 0
                          ? batteryColor
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: CircularProgressIndicator(
                                  value: soc / 100,
                                  strokeWidth: 9,
                                  backgroundColor: Colors.white10,
                                  valueColor:
                                      AlwaysStoppedAnimation(batteryColor),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${soc.round()}%',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: batteryColor)),
                                  const Text('estimated',
                                      style: TextStyle(
                                          fontSize: 9, color: Colors.white38)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MiniPanel(
                                title: 'VOLTAGE',
                                icon: Icons.electrical_services_rounded,
                                text: telemetry.batteryVoltage > 0
                                    ? '${telemetry.batteryVoltage.toStringAsFixed(2)} V'
                                    : '—',
                              ),
                              const SizedBox(height: 10),
                              _MiniPanel(
                                title: 'CHRG CURRENT',
                                icon: Icons.electric_meter_rounded,
                                text: '${telemetry.batteryCurrent.abs().toStringAsFixed(1)} A',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoStrip(
                      icon: Icons.bolt_rounded,
                      iconColor: batteryColor,
                      text: telemetry.batteryVoltage > 0
                          ? '${formatPower(telemetry.batteryVoltage * telemetry.batteryCurrent.abs())} battery power'
                          : 'No battery telemetry',
                    ),
                  ],
                ),
              ),

              // ════════════════════════════════════════════════════════════
              // SOLAR CARD — with dynamic colors
              // ════════════════════════════════════════════════════════════
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.wb_sunny_rounded,
                      title: 'Solar',
                      subtitle: telemetry.pvPower > 0
                          ? 'PV input • ${getSolarLabel(telemetry.pvPower)}'
                          : 'PV input',
                      subtitleColor: telemetry.pvPower > 0
                          ? solarColor
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                            child: _Metric('PV VOLTAGE',
                                telemetry.pvVoltage.toStringAsFixed(0), 'V')),
                        Expanded(
                            child: _Metric('PV CURRENT',
                                telemetry.pvCurrent.toStringAsFixed(1), 'A')),
                        Expanded(
                            child: _Metric(
                          'POWER',
                          formatPower(telemetry.pvPower),
                          '',
                          valueColor: solarColor,
                        )),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: (telemetry.pvPower / 6100).clamp(0, 1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(10),
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(solarColor),
                    ),
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('6.1 kW inverter',
                          style: TextStyle(
                              color: solarColor, fontSize: 11)),
                    ),
                  ],
                ),
              ),

              // ════════════════════════════════════════════════════════════
              // GRID & LOAD CARD — with dynamic colors
              // ════════════════════════════════════════════════════════════
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Title(
                      icon: Icons.power_rounded,
                      title: 'Grid & Load',
                      subtitle: 'AC input / inverter output',
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniPanel(
                            title: 'OUTPUT',
                            icon: Icons.outlet_rounded,
                            text:
                                '${telemetry.acOutputVoltage.toStringAsFixed(0)} V\n${telemetry.acOutputFrequency.toStringAsFixed(1)} Hz',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniPanel(
                            title: 'GRID INPUT',
                            icon: Icons.electrical_services_rounded,
                            text: telemetry.acInputVoltage > 0
                                ? '${telemetry.acInputVoltage.toStringAsFixed(0)} V  •  ${telemetry.acInputFrequency.toStringAsFixed(1)} Hz'
                                : 'No grid',
                          ),
                        ),
                      ],
                    ),

                  ],
                ),
              ),

              // ════════════════════════════════════════════════════════════
              // PV ENERGY CARD
              // ════════════════════════════════════════════════════════════
              const SizedBox(height: 14),
              _Card(
                child: Row(
                  children: [
                    const Icon(Icons.insights_rounded,
                        color: Color(0xFF5B9DFF), size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PV ENERGY',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                          Text(telemetry.pvEnergy.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w800)),
                          const Text('as reported by inverter',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white38)),
                        ],
                      ),
                    ),
                    Text('${telemetry.lastUpdateMs} ms',
                        style: const TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text('Eastman Smart Max • ESP32 monitor',
                    style: TextStyle(color: Colors.white30, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOAD PROGRESS BAR — SEPARATE TOP WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _LoadProgressBar extends StatelessWidget {
  final double loadPercent;
  final Color color;
  const _LoadProgressBar({required this.loadPercent, required this.color});

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
              _StatusChip(
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

// ═══════════════════════════════════════════════════════════════════════════
// STATUS CHIP (tiny colored label)
// ═══════════════════════════════════════════════════════════════════════════

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF11161E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(.055)),
        ),
        child: child,
      );
}

class _Title extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color? subtitleColor;
  const _Title(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.subtitleColor});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(.055),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: TextStyle(
                      color: subtitleColor ?? Colors.white38, fontSize: 11,
                      fontWeight: subtitleColor != null
                          ? FontWeight.w700
                          : FontWeight.normal)),
            ],
          ),
        ],
      );
}

class _Metric extends StatelessWidget {
  final String label, value, unit;
  final Color? valueColor;
  const _Metric(this.label, this.value, this.unit, {this.valueColor});

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
                  letterSpacing: 1)),
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

class _MiniPanel extends StatelessWidget {
  final String title, text;
  final IconData icon;
  const _MiniPanel(
      {required this.title, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white54),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;
  const _InfoStrip({required this.icon, required this.text, this.iconColor});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(.035),
            borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 17, color: iconColor ?? const Color(0xFF55D6BE)),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  final bool online;
  const _StatusPill({required this.online});

  @override
  Widget build(BuildContext context) {
    final color =
        online ? const Color(0xFF54D6A2) : const Color(0xFFFF6577);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(online ? 'LIVE' : 'OFFLINE',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String message;
  const _Warning({required this.message});

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

String formatPower(double watts) =>
    watts >= 1000 ? '${(watts / 1000).toStringAsFixed(2)} kW' : '${watts.toStringAsFixed(0)} W';
