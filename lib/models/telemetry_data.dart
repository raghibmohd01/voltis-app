class TelemetryData {
  final String status;
  final bool inverterConnected;
  final double batteryVoltage;
  final double batteryCurrent;
  final double pvVoltage;
  final double pvCurrent;
  final double pvPower;
  final double acInputVoltage;
  final double acInputFrequency;
  final double acOutputVoltage;
  final double acOutputFrequency;
  final double loadPercentage;
  final double pvEnergy;
  final int lastUpdateMs;
  final String rawHex;

  TelemetryData({
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
    required this.rawHex,
  });

  factory TelemetryData.fromJson(Map<dynamic, dynamic> json) {
    final data = json['data'] as Map<dynamic, dynamic>? ?? {};

    return TelemetryData(
      status: json['status']?.toString() ?? 'unknown',
      inverterConnected: json['inverter_connected'] as bool? ?? false,
      batteryVoltage: _parseDouble(data['batteryVoltage']),
      batteryCurrent: _parseDouble(data['batteryCurrent']),
      pvVoltage: _parseDouble(data['pvVoltage']),
      pvCurrent: _parseDouble(data['pvCurrent']),
      pvPower: _parseDouble(data['pvPower']),
      acInputVoltage: _parseDouble(data['acInputVoltage']),
      acInputFrequency: _parseDouble(data['acInputFrequency']),
      acOutputVoltage: _parseDouble(data['acOutputVoltage']),
      acOutputFrequency: _parseDouble(data['acOutputFrequency']),
      loadPercentage: _parseDouble(data['loadPercentage']),
      pvEnergy: _parseDouble(data['pvEnergy']),
      lastUpdateMs: _parseInt(data['lastUpdateMs']),
      rawHex: data['rawHex']?.toString() ?? '',
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
