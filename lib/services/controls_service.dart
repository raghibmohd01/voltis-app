import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import '../models/controls_state.dart';
import '../config.dart';
import 'hybrid_telemetry_service.dart';

class ControlsService {
  static final ControlsService instance = ControlsService._internal();

  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final StreamController<ControlsState> _controlsController =
      StreamController<ControlsState>.broadcast();

  StreamSubscription? _rtdbSubscription;
  Timer? _localPollTimer;
  ControlsState _latestState = ControlsState.initial;

  String get _localControlsUrl {
    final uri = Uri.parse(telemetryEndpoint);
    return '${uri.scheme}://${uri.host}:${uri.port}/controls';
  }

  ControlsService._internal();

  Stream<ControlsState> get controlsStream => _controlsController.stream;
  ControlsState get latestState => _latestState;

  void start() {
    _subscribeRtdb();
    // Only poll local HTTP periodically if connected to home Wi-Fi
    _localPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollLocal();
    });
  }

  void stop() {
    _rtdbSubscription?.cancel();
    _localPollTimer?.cancel();
  }

  void _subscribeRtdb() {
    _rtdbSubscription =
        _database.ref('/telemetry/controls/state').onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          final parsed = ControlsState.fromJson(data);
          _latestState = parsed;
          _controlsController.add(parsed);
        } catch (e) {
          debugPrint('Error parsing /telemetry/controls/state from Firebase: $e');
        }
      }
    }, onError: (err) {
      debugPrint('Firebase /telemetry/controls/state stream error: $err');
    });
  }

  Future<void> _pollLocal() async {
    // When away from home on mobile data, don't waste battery/traffic probing LAN
    if (HybridTelemetryService.instance.isUsingFirebase) return;
    try {
      final res = await http
          .get(Uri.parse(_localControlsUrl))
          .timeout(const Duration(milliseconds: 700));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<dynamic, dynamic>;
        final parsed = ControlsState.fromJson(data);
        _latestState = parsed;
        _controlsController.add(parsed);
      }
    } catch (_) {
      // Local LAN endpoint unavailable, fallback is already Firebase RTDB
    }
  }

  /// Send mode and target state command
  Future<bool> sendCommand({
    required int socket,
    required String mode,
    required bool state,
  }) async {
    bool localSuccess = false;
    final isUsingFirebase = HybridTelemetryService.instance.isUsingFirebase;

    // 1. Try local HTTP for immediate sub-10ms response ONLY if on home Wi-Fi
    if (!isUsingFirebase) {
      try {
        final res = await http
            .post(
              Uri.parse(_localControlsUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'socket': socket,
                'mode': mode,
                'state': state,
              }),
            )
            .timeout(const Duration(milliseconds: 700));
        if (res.statusCode == 200) {
          localSuccess = true;
          final data = json.decode(res.body) as Map<dynamic, dynamic>;
          _latestState = ControlsState.fromJson(data);
          _controlsController.add(_latestState);
        }
      } catch (_) {
        localSuccess = false;
      }
    }

    // 2. Always publish command to Firebase RTDB so state is synced globally
    // Zero increase in read/writes: exactly 1 write per user button tap
    try {
      await _database.ref('/telemetry/controls/commands').set({
        'socket': socket,
        'mode': mode,
        'state': state,
        'pending': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      debugPrint('Failed to set command in Firebase: $e');
      return localSuccess;
    }
  }

  /// Update automation thresholds & config
  Future<bool> updateConfig(ControlsConfig config) async {
    bool localSuccess = false;
    final bodyJson = {'config': config.toJson()};
    final isUsingFirebase = HybridTelemetryService.instance.isUsingFirebase;

    // 1. Try local HTTP ONLY if on home Wi-Fi
    if (!isUsingFirebase) {
      try {
        final res = await http
            .post(
              Uri.parse(_localControlsUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(bodyJson),
            )
            .timeout(const Duration(milliseconds: 700));
        if (res.statusCode == 200) {
          localSuccess = true;
          final data = json.decode(res.body) as Map<dynamic, dynamic>;
          _latestState = ControlsState.fromJson(data);
          _controlsController.add(_latestState);
        }
      } catch (_) {
        localSuccess = false;
      }
    }

    // 2. Firebase RTDB: exactly 1 write only when user edits thresholds
    try {
      await _database.ref('/telemetry/controls/config').set(config.toJson());
      return true;
    } catch (e) {
      debugPrint('Failed to set config in Firebase: $e');
      return localSuccess;
    }
  }
}

