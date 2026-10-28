import 'dart:async';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/telemetry.dart';
import '../models/alert_event.dart';
import '../utils/solar_timing_helper.dart';
import '../notification_service.dart';
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
  DateTime? _pvZeroSince; // Tracks when PV first dropped to ~0V during daytime
  double? _lastObservedLoad; // Tracks load growth while user is in the app
  DateTime? _lastSurgeFeedbackTime;

  // Audio player for tick sound
  final AudioPlayer _audioPlayer = AudioPlayer();

  AlertService._() {
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    try {
      _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      _audioPlayer.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ));
    } catch (_) {
      // Ignore if audio context configuration is unsupported
    }
  }

  /// Call this with every new telemetry reading.
  Future<void> evaluate(Telemetry telemetry) async {
    bool changed = false;

    // ── Load thresholds ──────────────────────────────────────────────
    // Eastman Smart Max 5KVA: 110% overload for 60s, 150% for 30s
    final load = telemetry.loadPercentage;
    AlertSeverity? loadSev;

    if (load >= 105) {
      loadSev = AlertSeverity.critical;
    } else if (load >= 90) {
      loadSev = AlertSeverity.alert;
    } else if (load >= 75) {
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
    } else if (_lastObservedLoad != null && load > _lastObservedLoad!) {
      // Detect noticeable load growth / surges while user is in the app
      final double loadDiff = load - _lastObservedLoad!;
      final bool isSurge = (load >= 70.0 && _lastObservedLoad! < 70.0) ||
                           (loadDiff >= 15.0 && load >= 50.0);
      if (isSurge) {
        final now = DateTime.now();
        if (_lastSurgeFeedbackTime == null || now.difference(_lastSurgeFeedbackTime!).inSeconds >= 5) {
          _lastSurgeFeedbackTime = now;
          _triggerFeedback(AlertSeverity.warning);
        }
      }
    }
    _lastObservedLoad = load;

    // Per-level hysteresis for load
    if (_lastLoadSeverity != null) {
      if (_lastLoadSeverity == AlertSeverity.warning && load < 70) {
        _lastLoadSeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.load);
        changed = true;
      } else if (_lastLoadSeverity == AlertSeverity.alert && load < 85) {
        _lastLoadSeverity = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.load);
        changed = true;
      } else if (_lastLoadSeverity == AlertSeverity.critical && load < 98) {
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

    // ── PV / Solar Daytime thresholds ─────────────────────────────────
    // Grid alerts remain disabled for off-grid setup, but PV is monitored during core daylight hours
    // to alert the user if the physical solar switch/breaker was left OFF for 30+ minutes.
    final bool isOnline = telemetry.inverterConnected && telemetry.status.toLowerCase() == 'online';
    final bool isDaytime = SolarTimingHelper.isDaytimeSolarHours();
    final timingRange = SolarTimingHelper.getDaytimeRange();

    AlertSeverity? pvSev;
    String pvTitle = '';
    String pvMsg = '';

    if (isOnline && isDaytime) {
      final bool hasNoSolar = telemetry.pvVoltage < 20.0 || (telemetry.pvPower <= 1.0 && telemetry.pvVoltage < 30.0);
      if (hasNoSolar) {
        _pvZeroSince ??= DateTime.now();
        // Check value for 30 minutes: only trigger if PV stays near 0 continuously for 30+ minutes during sunlight
        final zeroDuration = DateTime.now().difference(_pvZeroSince!);
        if (zeroDuration.inMinutes >= 30) {
          pvSev = AlertSeverity.critical;
          pvTitle = 'Solar Switch May Be OFF';
          pvMsg = 'No solar power detected for over 30 minutes during sunlight (${timingRange.label}). Check if the solar panel switch or breaker is OFF.';
        }
      } else {
        _pvZeroSince = null;
      }
    } else {
      _pvZeroSince = null;
    }

    if (pvSev != null && pvSev != _lastPvSeverity) {
      _lastPvSeverity = pvSev;
      _activeAlerts.removeWhere((a) => a.type == AlertType.pv);

      final event = AlertEvent(
        severity: pvSev,
        type: AlertType.pv,
        title: pvTitle,
        message: pvMsg,
        value: telemetry.pvVoltage,
        timestamp: DateTime.now(),
      );

      _activeAlerts.insert(0, event);
      await DatabaseService.instance.insertAlert(event);
      _triggerFeedback(pvSev);

      // Trigger local push notification if not already sent
      if (await NotificationService.shouldNotify('solar_switch_off')) {
        await NotificationService.instance.show(
          id: 300,
          title: '🚨 Solar Switch May Be OFF!',
          body: pvMsg,
          critical: true,
        );
        await NotificationService.markSent('solar_switch_off');
      }

      changed = true;
    }

    // Recovery condition for PV alerts:
    // When outside core daytime hours, or PV voltage recovers >= 25V with power > 10W
    if (_lastPvSeverity != null) {
      final bool recovered = !isDaytime || (telemetry.pvVoltage >= 25.0 && telemetry.pvPower > 10.0);
      if (recovered) {
        _lastPvSeverity = null;
        _pvZeroSince = null;
        _activeAlerts.removeWhere((a) => a.type == AlertType.pv);
        await NotificationService.clearFlag('solar_switch_off');
        await NotificationService.clearFlag('solar_no_power');
        changed = true;
      }
    }

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
        _playTickSound();
        break;
    }
  }

  Future<void> _playTickSound() async {
    try {
      // Immediate tactile click via system sound
      SystemSound.play(SystemSoundType.click);

      // Play subtle metallic compass tick sound
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource('sounds/metallic_tick.wav'),
        volume: 1.0,
        mode: PlayerMode.lowLatency,
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
