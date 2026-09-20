# Inverter Dashboard

Real-time Flutter dashboard for the ESP32 endpoint:

`http://192.168.31.127/telemetry`

## Run

Create a normal Flutter project, then copy `lib/main.dart` and `pubspec.yaml` from this package:

```bash
flutter pub get
flutter run
```

For Android, because the ESP32 uses plain HTTP on the local network, ensure the app has INTERNET permission and, if required by your target SDK/configuration, allow cleartext traffic.

## Battery SOC

The circular battery percentage is deliberately labelled **estimated**. It uses a simple voltage curve for a 48 V tubular/lead-acid bank. It is not a true SOC measurement. Later, replace it with coulomb counting plus battery-specific calibration.
