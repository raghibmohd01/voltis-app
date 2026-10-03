import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../models/telemetry.dart';
import '../models/alert_event.dart';
import '../services/hybrid_telemetry_service.dart';
import '../services/database_service.dart';
import '../services/alert_service.dart';

class DashboardViewModel extends ChangeNotifier {
  StreamSubscription? _subscription;
  StreamSubscription? _dataSourceSubscription;
  StreamSubscription? _alertSubscription;

  Telemetry _telemetry = Telemetry.empty;
  bool _loading = true;
  String? _error;
  DateTime _lastDbInsert = DateTime.fromMillisecondsSinceEpoch(0);
  bool _bgServiceEnabled = false;
  DataSource _currentDataSource = DataSource.none;
  List<AlertEvent> _activeAlerts = [];

  Telemetry get telemetry => _telemetry;
  bool get loading => _loading;
  String? get error => _error;
  bool get bgServiceEnabled => _bgServiceEnabled;
  DataSource get currentDataSource => _currentDataSource;
  List<AlertEvent> get activeAlerts => _activeAlerts;

  DashboardViewModel() {
    _initPrefs();

    // Listen for alert changes
    _alertSubscription = AlertService.instance.activeAlertStream.listen((alerts) {
      _activeAlerts = alerts;
      notifyListeners();
    });

    _subscription = HybridTelemetryService.instance.telemetryStream.listen((newTelemetry) {
      _telemetry = newTelemetry;
      _error = null;
      if (_loading) _loading = false;
      notifyListeners();

      // Evaluate alerts against realtime data
      AlertService.instance.evaluate(newTelemetry);

      // Save to local DB every 1 minute
      if (DateTime.now().difference(_lastDbInsert) > const Duration(minutes: 1)) {
        DatabaseService.instance.insertTelemetry(newTelemetry);
        _lastDbInsert = DateTime.now();
      }
    }, onError: (e) {
      _error = e.toString();
      if (_loading) _loading = false;
      notifyListeners();
    });

    _dataSourceSubscription = HybridTelemetryService.instance.dataSourceStream.listen((source) {
      _currentDataSource = source;
      notifyListeners();
    });
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _bgServiceEnabled = prefs.getBool('bg_service_enabled') ?? false;
    notifyListeners();
  }

  Future<void> toggleBackgroundService(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_service_enabled', value);
    _bgServiceEnabled = value;
    notifyListeners();

    final service = FlutterBackgroundService();
    if (value) {
      await service.startService();
    } else {
      service.invoke("stopService");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dataSourceSubscription?.cancel();
    _alertSubscription?.cancel();
    super.dispose();
  }
}

