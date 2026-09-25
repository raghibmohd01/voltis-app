import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/telemetry_data.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Sign in anonymously
  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      print("Failed to sign in anonymously: $e");
      return null;
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of telemetry data
  Stream<TelemetryData> get telemetryStream {
    return _database.ref('/telemetry/live').onValue.map((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        return TelemetryData.fromJson(data);
      }
      throw Exception('Data is null');
    });
  }
}
