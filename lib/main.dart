import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';
import 'background_worker.dart';
import 'services/hybrid_telemetry_service.dart';
import 'views/login_screen.dart';
import 'views/main_scaffold.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Request notifications first
  await Permission.notification.request();
  // Request ignoring battery optimizations so OnePlus doesn't kill the worker
  await Permission.ignoreBatteryOptimizations.request();

  await NotificationService.instance.init();
  await initializeBackgroundService();

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    HybridTelemetryService.instance.start();
  }

  runApp(InverterDashboardApp(isLoggedIn: user != null));
}

class InverterDashboardApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const InverterDashboardApp({super.key, this.isLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voltis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080B10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D6BE),
          brightness: Brightness.dark,
        ),
      ),
      home: isLoggedIn ? const MainScaffold() : const LoginScreen(),
    );
  }
}
