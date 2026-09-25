import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages local notifications with deduplication so each threshold only
/// fires once until the value recovers past it.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  // ── Notification channels ──────────────────────────────────────────────

  static const _defaultChannel = AndroidNotificationDetails(
    'inverter_default',
    'Inverter Alerts',
    channelDescription: 'Standard inverter monitoring alerts',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _criticalChannel = AndroidNotificationDetails(
    'inverter_critical',
    'Critical Alerts',
    channelDescription: 'Critical inverter alerts with alarm sound',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm'),
    enableVibration: true,
    fullScreenIntent: true,
  );

  // ── Initialisation ─────────────────────────────────────────────────────

  Future<void> init({bool requestPermissions = true}) async {
    if (_initialised) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Request permission on Android 13+ only if requested (don't do this in background isolate!)
    if (requestPermissions && Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {
        // Ignore if called from background without an activity
      }
    }

    _initialised = true;
  }

  // ── Show helpers ───────────────────────────────────────────────────────

  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool critical = false,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: critical ? _criticalChannel : _defaultChannel,
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ── Threshold deduplication ────────────────────────────────────────────

  /// Returns `true` if the notification for [key] hasn't been sent yet.
  /// Call [markSent] after showing it.
  static Future<bool> shouldNotify(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('notif_$key') ?? false);
  }

  static Future<void> markSent(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_$key', true);
  }

  /// Call when the value recovers past the threshold so future
  /// crossings can re-trigger.
  static Future<void> clearFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notif_$key');
  }
}
