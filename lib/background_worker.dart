import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'notification_service.dart';
import 'models/telemetry.dart';
import 'config.dart';

const _endpoint = telemetryEndpoint;

// ── Notification IDs ───
const _idBattery47 = 100;
const _idBattery46 = 101;
const _idBattery45 = 102;
const _idLoad50 = 200;
const _idLoad60 = 201;
const _idLoad80 = 202;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'Voltis Foreground Service', // title
    description: 'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Voltis Service',
      initialNotificationContent: 'Initializing...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('bg_service_enabled') ?? false;
  if (enabled) {
    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Bring in notification service
  await NotificationService.instance.init(requestPermissions: false);

  // Polling loop (every 15 seconds)
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    await _checkAndNotify(service);
  });
}

Future<void> _checkAndNotify(ServiceInstance service) async {
  try {
    final response = await http
        .get(Uri.parse(_endpoint))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final telemetry = Telemetry.fromJson(json);

    final batteryVoltage = telemetry.batteryVoltage;
    final loadPercentage = telemetry.loadPercentage;

    // Update foreground notification safely
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "Voltis is Monitoring",
          content: "Battery: ${batteryVoltage.toStringAsFixed(1)}V | Load: ${loadPercentage.toStringAsFixed(0)}%",
        );
      }
    }

    final svc = NotificationService.instance;

    // ── Battery thresholds ───────────────────────────────────────────
    if (batteryVoltage > 0 && batteryVoltage <= 45.0) {
      if (await NotificationService.shouldNotify('bat45')) {
        await svc.show(
          id: _idBattery45,
          title: '🚨 CRITICAL: Battery at ${batteryVoltage.toStringAsFixed(1)}V',
          body: 'Battery voltage has dropped to a critical level. Reduce load immediately!',
          critical: true,
        );
        await NotificationService.markSent('bat45');
      }
    } else if (batteryVoltage > 45.0 && batteryVoltage <= 46.0) {
      if (await NotificationService.shouldNotify('bat46')) {
        await svc.show(
          id: _idBattery46,
          title: '🚨 Battery Very Low — ${batteryVoltage.toStringAsFixed(1)}V',
          body: 'Battery voltage is very low. Consider reducing load.',
          critical: true,
        );
        await NotificationService.markSent('bat46');
      }
    } else if (batteryVoltage > 46.0 && batteryVoltage <= 47.0) {
      if (await NotificationService.shouldNotify('bat47')) {
        await svc.show(
          id: _idBattery47,
          title: '⚠️ Battery Low — ${batteryVoltage.toStringAsFixed(1)}V',
          body: 'Battery voltage is getting low.',
        );
        await NotificationService.markSent('bat47');
      }
    }

    // Hysteresis for Battery: Clear flags when voltage safely Recovers
    if (batteryVoltage >= 46.0) {
      await NotificationService.clearFlag('bat45');
    }
    if (batteryVoltage >= 47.0) {
      await NotificationService.clearFlag('bat46');
    }
    if (batteryVoltage >= 48.0) { // Safely recovered
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
      if (await NotificationService.shouldNotify('load60')) {
        await svc.show(
          id: _idLoad60,
          title: '⚠️ Load High — ${loadPercentage.toStringAsFixed(0)}%',
          body: 'Inverter load is high. Monitor usage.',
        );
        await NotificationService.markSent('load60');
      }
    } else if (loadPercentage >= 50) {
      if (await NotificationService.shouldNotify('load50')) {
        await svc.show(
          id: _idLoad50,
          title: '⚠️ Load at ${loadPercentage.toStringAsFixed(0)}%',
          body: 'Inverter load has crossed 50%.',
        );
        await NotificationService.markSent('load50');
      }
    }

    // Hysteresis for Load
    if (loadPercentage < 75) {
      await NotificationService.clearFlag('load80');
    }
    if (loadPercentage < 55) {
      await NotificationService.clearFlag('load60');
    }
    if (loadPercentage < 45) {
      await NotificationService.clearFlag('load50');
    }
  } catch (_) {
    // Network unavailable — silently skip this cycle.
  }
}
