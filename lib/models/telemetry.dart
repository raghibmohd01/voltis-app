class Telemetry {
  final String status;
  final bool inverterConnected;
  final double batteryVoltage, batteryCurrent;
  final double pvVoltage, pvCurrent, pvPower;
  final double acInputVoltage, acInputFrequency;
  final double acOutputVoltage, acOutputFrequency;
  final double loadPercentage, pvEnergy;
  final int lastUpdateMs;

  const Telemetry({
    required this.status,
    required this.inverterConnected,
    required this.batteryVoltage,
    required this.batteryCurrent,
    required this.pvVoltage,
    required this.pvCurrent,
    required this.pvPower,
    required this.acInputVoltage,
    required this.acInputFrequency,
    required this.acOutputVoltage,
    required this.acOutputFrequency,
    required this.loadPercentage,
    required this.pvEnergy,
    required this.lastUpdateMs,
  });

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? {});

    double d(String key) {
      final v = data[key];
      return v is num ? v.toDouble() : 0;
    }

    int i(String key) {
      final v = data[key];
      return v is num ? v.toInt() : 0;
    }

    return Telemetry(
      status: '${json['status'] ?? 'offline'}',
      inverterConnected: json['inverter_connected'] == true,
      batteryVoltage: d('batteryVoltage'),
      batteryCurrent: d('batteryCurrent'),
      pvVoltage: d('pvVoltage'),
      pvCurrent: d('pvCurrent'),
      pvPower: d('pvPower'),
      acInputVoltage: d('acInputVoltage'),
      acInputFrequency: d('acInputFrequency'),
      acOutputVoltage: d('acOutputVoltage'),
      acOutputFrequency: d('acOutputFrequency'),
      loadPercentage: d('loadPercentage'), // Unclamped to allow 110% - 150% overloads
      pvEnergy: d('pvEnergy'),
      lastUpdateMs: i('lastUpdateMs'),
    );
  }

  static const empty = Telemetry(
    status: 'offline',
    inverterConnected: false,
    batteryVoltage: 0,
    batteryCurrent: 0,
    pvVoltage: 0,
    pvCurrent: 0,
    pvPower: 0,
    acInputVoltage: 0,
    acInputFrequency: 0,
    acOutputVoltage: 0,
    acOutputFrequency: 0,
    loadPercentage: 0,
    pvEnergy: 0,
    lastUpdateMs: 0,
  );
}
