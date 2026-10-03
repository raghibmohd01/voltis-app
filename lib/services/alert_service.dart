import 'dart:async';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/telemetry.dart';
import '../models/alert_event.dart';
import 'database_service.dart';

/// Evaluates real-time telemetry against thresholds and emits [AlertEvent]s.
///
/// Thresholds (based on Eastman Smart Max 5KVA specs):
///   Load    ≥ 85 → warning,  ≥ 95 → alert,  ≥ 105 → critical
///   Battery ≤ 46.0V → warning,  ≤ 44.5V → alert,  ≤ 43.0V → critical
///
/// Deduplication: only fires a new alert when the severity *level* changes or
/// after the condition has fully cleared (with per-level hysteresis).
class AlertService {
  AlertService._();
  static final instance = AlertService._();

  final StreamController<List<AlertEvent>> _activeController =
      StreamController<List<AlertEvent>>.broadcast();

  Stream<List<AlertEvent>> get activeAlertStream => _activeController.stream;

  final List<AlertEvent> _activeAlerts = [];
  List<AlertEvent> get activeAlerts => List.unmodifiable(_activeAlerts);

  // Track last fired severity per type to avoid duplicate alerts
  AlertSeverity? _lastLoadSeverity;
  AlertSeverity? _lastBatterySeverity;
  AlertSeverity? _lastGridSeverity;
  AlertSeverity? _lastPvSeverity;
  AlertSeverity? _lastSystemSeverity;

  double? _lastAcInputVoltage;
  DateTime? _offlineSince;

  // Audio player for tick sound
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Call this with every new telemetry reading.
  Future<void> evaluate(Telemetry telemetry) async {
    bool changed = false;

    // ── Load thresholds ──────────────────────────────────────────────
    // Eastman Smart Max 5KVA: 110% overload for 60s, 150% for 30s
    final load = telemetry.loadPercentage;
    AlertSeverity? loadSev;

    if (load >= 105) {
      loadSev = AlertSeverity.critical;
    } else if (load >= 95) {
      loadSev = AlertSeverity.alert;
    } else if (load >= 85) {
      loadSev = AlertSeverity.warning;
    }

    if (loadSev != null && loadSev != _lastLoadSeverity) {
      _lastLoadSeverity = loadSev;
      _activeAlerts.removeWhere((a) => a.type == AlertType.load);

      final event = AlertEvent(
        severity: loadSev,
        type: AlertType.load,
        title: _loadTitle(loadSev, load),
        message: _loadMessage(loadSev, load),
        value: load,
        timestamp: DateTime.now(),
      );

      _activeAlerts.insert(0, event);
      await DatabaseService.instance.insertAlert(event);
      _triggerFeedback(loadSev);
      changed = true;
    }

    // Per-level hysteresis for load
    if (_lastLoadSeverity != null) {
      if (_lastLoadSeverity == AlertSeverity.warning && load < 80) {
        _lastLoadSeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.load);
        changed = true;
      } else if (_lastLoadSeverity == AlertSeverity.alert && load < 90) {
        _lastLoadSeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.load);
        changed = true;
      } else if (_lastLoadSeverity == AlertSeverity.critical && load < 100) {
        _lastLoadSeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.load);
        changed = true;
      }
    }

    // ── Battery thresholds ───────────────────────────────────────────
    // 48V Lead-Acid Tubular: 42V = dead, 44.5V = 10% SoC, 46V = ~25% SoC
    final bv = telemetry.batteryVoltage;
    AlertSeverity? batSev;

    if (bv > 0 && bv <= 43.0) {
      batSev = AlertSeverity.critical;   // ~3% SoC — imminent shutdown
    } else if (bv > 0 && bv <= 44.5) {
      batSev = AlertSeverity.alert;      // ~10% SoC — deep discharge zone
    } else if (bv > 0 && bv <= 46.0) {
      batSev = AlertSeverity.warning;    // ~25% SoC — getting low
    }

    if (batSev != null && batSev != _lastBatterySeverity) {
      _lastBatterySeverity = batSev;
      _activeAlerts.removeWhere((a) => a.type == AlertType.battery);

      final event = AlertEvent(
        severity: batSev,
        type: AlertType.battery,
        title: _batteryTitle(batSev, bv),
        message: _batteryMessage(batSev, bv),
        value: bv,
        timestamp: DateTime.now(),
      );

      _activeAlerts.insert(0, event);
      await DatabaseService.instance.insertAlert(event);
      _triggerFeedback(batSev);
      changed = true;
    }

    // Per-level hysteresis for battery (voltage must recover past threshold)
    if (_lastBatterySeverity != null) {
      if (_lastBatterySeverity == AlertSeverity.warning && bv >= 47.5) {
        _lastBatterySeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.battery);
        changed = true;
      } else if (_lastBatterySeverity == AlertSeverity.alert && bv >= 46.0) {
        _lastBatterySeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.battery);
        changed = true;
      } else if (_lastBatterySeverity == AlertSeverity.critical && bv >= 45.0) {
        _lastBatterySeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.battery);
        changed = true;
      }
    }

    // Grid and PV alert generation disabled due to off-grid setup (acIn always 0, pv drops are normal)

    // ── System thresholds (Output Sag / Offline) ──────────────────────
    final acOut = telemetry.acOutputVoltage;
    AlertSeverity? sysSev;
    String sysTitle = '';
    String sysMsg = '';
    
    if (telemetry.status != 'online') {
      if (_offlineSince == null) _offlineSince = DateTime.now();
      if (DateTime.now().difference(_offlineSince!).inSeconds > 60) {
        sysSev = AlertSeverity.critical;
        sysTitle = 'Inverter Offline';
        sysMsg = 'Inverter has been offline for over 60 seconds.';
      }
    } else {
      _offlineSince = null;
      // Check voltage sag/surge if inverter is running
      if (acOut > 0 && (acOut < 200 || acOut > 250)) {
        sysSev = AlertSeverity.warning;
        sysTitle = 'Output Voltage Unstable';
        sysMsg = 'AC output is ${acOut.toStringAsFixed(0)}V, which is outside safe limits.';
      }
    }

    if (sysSev != null && sysSev != _lastSystemSeverity) {
      _lastSystemSeverity = sysSev;
      _activeAlerts.removeWhere((a) => a.type == AlertType.system);
      final event = AlertEvent(
        severity: sysSev,
        type: AlertType.system,
        title: sysTitle,
        message: sysMsg,
        value: acOut,
        timestamp: DateTime.now(),
      );
      _activeAlerts.insert(0, event);
      await DatabaseService.instance.insertAlert(event);
      _triggerFeedback(sysSev);
      changed = true;
    }

    if (sysSev == null && _lastSystemSeverity != null) {
      _lastSystemSeverity = null;
      _activeAlerts.removeWhere((a) => a.type == AlertType.system);
      changed = true;
    }

    if (changed) {
      _activeController.add(List.unmodifiable(_activeAlerts));
    }
  }

  // ── Haptic + Sound ───────────────────────────────────────────────
  void _triggerFeedback(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        HapticFeedback.heavyImpact();
        _playTickSound();
        // Double tap for critical
        Future.delayed(const Duration(milliseconds: 150), () {
          HapticFeedback.heavyImpact();
          _playTickSound();
        });
        break;
      case AlertSeverity.alert:
        HapticFeedback.mediumImpact();
        _playTickSound();
        break;
      case AlertSeverity.warning:
        HapticFeedback.lightImpact();
        break;
    }
  }

  Future<void> _playTickSound() async {
    try {
      await _audioPlayer.play(
        AssetSource('sounds/alert_tick.wav'),
        volume: 0.7,
      );
    } catch (_) {
      // Sound not available — ignore gracefully
    }
  }

  // ── Message builders ─────────────────────────────────────────────
  String _loadTitle(AlertSeverity sev, double load) {
    switch (sev) {
      case AlertSeverity.critical:
        return 'Load Overload — ${load.toStringAsFixed(0)}%';
      case AlertSeverity.alert:
        return 'Load High — ${load.toStringAsFixed(0)}%';
      case AlertSeverity.warning:
        return 'Load Warning — ${load.toStringAsFixed(0)}%';
    }
  }

  String _loadMessage(AlertSeverity sev, double load) {
    switch (sev) {
      case AlertSeverity.critical:
        return 'Inverter is overloaded! The 60-second shutdown timer has started. Reduce load immediately!';
      case AlertSeverity.alert:
        return 'Load is dangerously close to capacity. Turn off non-essential appliances now.';
      case AlertSeverity.warning:
        return 'Load is at ${load.toStringAsFixed(0)}% of 5KVA capacity. Monitor usage closely.';
    }
  }

  String _batteryTitle(AlertSeverity sev, double voltage) {
    switch (sev) {
      case AlertSeverity.critical:
        return 'Battery Critical — ${voltage.toStringAsFixed(1)}V (~3%)';
      case AlertSeverity.alert:
        return 'Battery Very Low — ${voltage.toStringAsFixed(1)}V (~10%)';
      case AlertSeverity.warning:
        return 'Battery Low — ${voltage.toStringAsFixed(1)}V (~25%)';
    }
  }

  String _batteryMessage(AlertSeverity sev, double voltage) {
    switch (sev) {
      case AlertSeverity.critical:
        return 'Battery at ~3% SoC. Inverter will shut down at 42V. Connect grid power immediately!';
      case AlertSeverity.alert:
        return 'Battery at ~10% SoC. Deep discharge risks permanent damage. Reduce load or connect grid.';
      case AlertSeverity.warning:
        return 'Battery dropping below 25% SoC. Consider reducing load.';
    }
  }

  void dispose() {
    _activeController.close();
    _audioPlayer.dispose();
  }
}
