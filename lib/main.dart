import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'background_worker.dart';
import 'views/dashboard_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await registerBackgroundWorker();
  runApp(const InverterDashboardApp());
}

class InverterDashboardApp extends StatelessWidget {
  const InverterDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inverter Dashboard',
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
      home: const DashboardView(),
    );
  }
}
