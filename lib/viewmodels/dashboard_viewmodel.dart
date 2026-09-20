import 'dart:async';
import 'package:flutter/material.dart';
import '../models/telemetry.dart';
import '../services/telemetry_service.dart';

class DashboardViewModel extends ChangeNotifier {
  final TelemetryService _service;
  Timer? _timer;

  Telemetry _telemetry = Telemetry.empty;
  bool _loading = true;
  String? _error;

  Telemetry get telemetry => _telemetry;
  bool get loading => _loading;
  String? get error => _error;

  DashboardViewModel({TelemetryService? service})
      : _service = service ?? TelemetryService() {
    _fetchTelemetry();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchTelemetry());
  }

  Future<void> _fetchTelemetry() async {
    try {
      final newTelemetry = await _service.fetchTelemetry();
      _telemetry = newTelemetry;
      _error = null;
    } catch (e) {
      _error = e.toString();
      // Keep old telemetry data if there's an error, just update error state
    } finally {
      if (_loading) {
        _loading = false;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
