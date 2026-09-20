import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'models/telemetry.dart';
import 'config.dart';

/// Unique task name registered with WorkManager.
const kBackgroundTaskName = 'inverterTelemetryCheck';

/// The endpoint to poll (must match DashboardPage).
const _endpoint = telemetryEndpoint;

// ── Notification IDs (stable per-threshold so they replace each other) ───

const _idBattery47 = 100;
const _idBattery46 = 101;
const _idBattery45 = 102;
const _idLoad50 = 200;
const _idLoad60 = 201;
const _idLoad80 = 202;

/// Top-level callback required by WorkManager — must be a static or
/// top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kBackgroundTaskName ||
        taskName == Workmanager.iOSBackgroundTask) {
      await _checkAndNotify();
    }
    return true;
  });
}

/// Register the periodic background task. Call once at app start.
Future<void> registerBackgroundWorker() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  await Workmanager().registerPeriodicTask(
    'inverter-bg-check',
    kBackgroundTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

// ── Core check logic (runs in isolate / background) ─────────────────────

Future<void> _checkAndNotify() async {
  try {
    final response = await http
        .get(Uri.parse(_endpoint))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final telemetry = Telemetry.fromJson(json);

    final batteryVoltage = telemetry.batteryVoltage;
    final loadPercentage = telemetry.loadPercentage;

    final svc = NotificationService.instance;
    await svc.init();

    // ── Battery thresholds ───────────────────────────────────────────

    if (batteryVoltage > 0 && batteryVoltage <= 45) {
      if (await NotificationService.shouldNotify('bat45')) {
        await svc.show(
          id: _idBattery45,
          title: '🚨 CRITICAL: Battery at ${batteryVoltage.toStringAsFixed(1)}V',
          body:
              'Battery voltage has dropped to a critical level. Reduce load immediately!',
          critical: true,
        );
        await NotificationService.markSent('bat45');
      }
    } else if (batteryVoltage > 45 && batteryVoltage <= 46) {
      await NotificationService.clearFlag('bat45');
      if (await NotificationService.shouldNotify('bat46')) {
        await svc.show(
          id: _idBattery46,
          title: '🚨 Battery Very Low — ${batteryVoltage.toStringAsFixed(1)}V',
          body: 'Battery voltage is very low. Consider reducing load.',
          critical: true,
        );
        await NotificationService.markSent('bat46');
      }
    } else if (batteryVoltage > 46 && batteryVoltage <= 47) {
      await NotificationService.clearFlag('bat45');
      await NotificationService.clearFlag('bat46');
      if (await NotificationService.shouldNotify('bat47')) {
        await svc.show(
          id: _idBattery47,
          title: '⚠️ Battery Low — ${batteryVoltage.toStringAsFixed(1)}V',
          body: 'Battery voltage is getting low.',
        );
        await NotificationService.markSent('bat47');
      }
    } else {
      // Recovered — clear all battery flags
      await NotificationService.clearFlag('bat45');
      await NotificationService.clearFlag('bat46');
      await NotificationService.clearFlag('bat47');
    }

    // ── Load thresholds ──────────────────────────────────────────────

    if (loadPercentage >= 80) {
      if (await NotificationService.shouldNotify('load80')) {
        await svc.show(
          id: _idLoad80,
          title: '🚨 Load Overloaded — ${loadPercentage.toStringAsFixed(0)}%',
          body: 'Inverter load is critically high!',
          critical: true,
        );
        await NotificationService.markSent('load80');
      }
    } else if (loadPercentage >= 60) {
      await NotificationService.clearFlag('load80');
      if (await NotificationService.shouldNotify('load60')) {
        await svc.show(
          id: _idLoad60,
          title: '⚠️ Load High — ${loadPercentage.toStringAsFixed(0)}%',
          body: 'Inverter load is high. Monitor usage.',
        );
        await NotificationService.markSent('load60');
      }
    } else if (loadPercentage >= 50) {
      await NotificationService.clearFlag('load80');
      await NotificationService.clearFlag('load60');
      if (await NotificationService.shouldNotify('load50')) {
        await svc.show(
          id: _idLoad50,
          title: '⚠️ Load at ${loadPercentage.toStringAsFixed(0)}%',
          body: 'Inverter load has crossed 50%.',
        );
        await NotificationService.markSent('load50');
      }
    } else {
      // Recovered — clear all load flags
      await NotificationService.clearFlag('load50');
      await NotificationService.clearFlag('load60');
      await NotificationService.clearFlag('load80');
    }
  } catch (_) {
    // Network unavailable — silently skip this cycle.
  }
}
