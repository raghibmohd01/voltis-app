import 'package:flutter/material.dart';

Color getLoadColor(double load) {
  if (load >= 80) return const Color(0xFFE74C3C); // red
  if (load >= 51) return const Color(0xFFF39C12); // amber
  if (load >= 31) return const Color(0xFF5B9DFF); // blue
  return const Color(0xFF2ECC71); // green
}

String getLoadLabel(double load) {
  if (load >= 80) return 'Overloaded';
  if (load >= 51) return 'High';
  if (load >= 31) return 'Normal';
  return 'Low';
}

Color getBatteryColor(double voltage) {
  if (voltage >= 49) return const Color(0xFF2ECC71); // green – good
  if (voltage >= 48) return const Color(0xFF5B9DFF); // blue – ok
  if (voltage >= 47) return const Color(0xFFF39C12); // amber – low
  if (voltage >= 46) return const Color(0xFFE74C3C); // red – very low
  return const Color(0xFFC0392B); // dark red – critical
}

String getBatteryLabel(double voltage) {
  if (voltage >= 49) return 'Good';
  if (voltage >= 48) return 'OK';
  if (voltage >= 47) return 'Low';
  if (voltage >= 46) return 'Very Low';
  return 'Critical';
}

Color getSolarColor(double watts) {
  if (watts >= 3000) return const Color(0xFF1B8A2A); // dark green – excellent
  if (watts >= 1500) return const Color(0xFF2ECC71); // green – good
  if (watts >= 500) return const Color(0xFFF39C12); // amber – moderate
  if (watts >= 1) return const Color(0xFFE74C3C); // red – poor
  return const Color(0xFF888888); // grey – none
}

String getSolarLabel(double watts) {
  if (watts >= 3000) return 'Excellent';
  if (watts >= 1500) return 'Good';
  if (watts >= 500) return 'Moderate';
  if (watts >= 1) return 'Poor';
  return 'None';
}
