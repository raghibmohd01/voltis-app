import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/telemetry.dart';
import '../config.dart';

enum DataSource { local, firebase, none }

class HybridTelemetryService {
  static final HybridTelemetryService instance = HybridTelemetryService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final String _endpoint;

  HybridTelemetryService._internal({String? endpoint}) : _endpoint = endpoint ?? telemetryEndpoint;

  final StreamController<Telemetry> _telemetryController = StreamController<Telemetry>.broadcast();
  final StreamController<DataSource> _dataSourceController = StreamController<DataSource>.broadcast();

  Timer? _pollingTimer;
  StreamSubscription? _firebaseSubscription;
  bool _isUsingFirebase = false;

  Stream<Telemetry> get telemetryStream => _telemetryController.stream;
  Stream<DataSource> get dataSourceStream => _dataSourceController.stream;

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      return userCredential.user;
    } catch (e) {
      print("Failed to sign in with email: $e");
      return null;
    }
  }

  void start() {
    _dataSourceController.add(DataSource.none);
    _startPolling();
  }

  void stop() {
    _pollingTimer?.cancel();
    _firebaseSubscription?.cancel();
  }

  int _localFailureCount = 0;
  static const int _maxLocalFailures = 3;

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      bool localSuccess = await _fetchLocal();
      if (!localSuccess) {
        _localFailureCount++;
        if (_localFailureCount >= _maxLocalFailures && !_isUsingFirebase) {
          _switchToFirebase();
        }
      } else {
        _localFailureCount = 0;
        if (_isUsingFirebase) {
          _switchToLocal();
        }
      }
    });
    // Trigger immediately
    _fetchLocal().then((success) {
      if (!success) {
        _localFailureCount = _maxLocalFailures;
        _switchToFirebase();
      } else {
        _localFailureCount = 0;
      }
    });
  }

  Future<bool> _fetchLocal() async {
    try {
      final response = await http.get(Uri.parse(_endpoint)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = Telemetry.fromJson(json);
        _telemetryController.add(data);
        _dataSourceController.add(DataSource.local);
        return true;
      }
    } catch (_) {
      // Ignored, will return false below
    }
    return false;
  }

  void _switchToFirebase() {
    _isUsingFirebase = true;
    _dataSourceController.add(DataSource.firebase);
    _firebaseSubscription = _database.ref('/telemetry/live').onValue.listen((event) {
      if (_isUsingFirebase && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        // Telemetry.fromJson takes Map<String, dynamic> so cast it
        _telemetryController.add(Telemetry.fromJson(Map<String, dynamic>.from(data)));
      }
    });
  }

  void _switchToLocal() {
    _isUsingFirebase = false;
    _firebaseSubscription?.cancel();
    _dataSourceController.add(DataSource.local);
  }

  Future<List<Map<String, dynamic>>> getFirebaseHistoryForDay(int day) async {
    try {
      final snapshot = await _database.ref('/telemetry/history/day_$day').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        final List<Map<String, dynamic>> history = [];
        data.forEach((key, value) {
          if (value == null) return;
          final entry = Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
          // Check if timestamp exists
          if (entry['timestamp'] != null) {
            // ESP32 sends timestamp in seconds, convert to milliseconds
            final int tsInSeconds = (entry['timestamp'] as num).toInt();
            entry['timestamp'] = tsInSeconds * 1000;
            history.add(entry);
          }
        });
        
        // Sort by timestamp
        history.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
        return history;
      }
    } catch (e) {
      print("Failed to fetch Firebase history: $e");
    }
    return [];
  }

  Future<Map<int, List<Map<String, dynamic>>>> getAllFirebaseHistory() async {
    try {
      final snapshot = await _database.ref('/telemetry/history').get();
      final Map<int, List<Map<String, dynamic>>> allData = {};
      
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((dayKey, dayData) {
          if (dayData == null) return;
          final dayString = dayKey.toString().replaceAll('day_', '');
          final dayInt = int.tryParse(dayString);
          if (dayInt == null) return;
          
          final List<Map<String, dynamic>> history = [];
          final slots = dayData as Map<dynamic, dynamic>;
          
          slots.forEach((slotKey, value) {
            if (value == null) return;
            final entry = Map<String, dynamic>.from(value as Map<dynamic, dynamic>);
            if (entry['timestamp'] != null) {
              final int tsInSeconds = (entry['timestamp'] as num).toInt();
              entry['timestamp'] = tsInSeconds * 1000;
              history.add(entry);
            }
          });
          
          history.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
          allData[dayInt] = history;
        });
        
        return allData;
      }
    } catch (e) {
      print("Failed to fetch all Firebase history: $e");
    }
    return {};
  }
}
