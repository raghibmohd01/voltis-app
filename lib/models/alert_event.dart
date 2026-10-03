/// Severity levels for inverter alerts
enum AlertSeverity {
  warning,  // ⚠️ Amber — heads-up
  alert,    // 🔶 Orange — action recommended
  critical, // 🚨 Red — immediate action required
}

/// What subsystem triggered the alert
enum AlertType {
  load,
  battery,
  grid,
  pv,
  system,
}

class AlertEvent {
  final int? id;
  final AlertSeverity severity;
  final AlertType type;
  final String title;
  final String message;
  final double value;
  final DateTime timestamp;
  final bool isActive; // still ongoing?

  const AlertEvent({
    this.id,
    required this.severity,
    required this.type,
    required this.title,
    required this.message,
    required this.value,
    required this.timestamp,
    this.isActive = true,
  });

  AlertEvent copyWith({bool? isActive}) => AlertEvent(
        id: id,
        severity: severity,
        type: type,
        title: title,
        message: message,
        value: value,
        timestamp: timestamp,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toMap() => {
        'severity': severity.index,
        'type': type.index,
        'title': title,
        'message': message,
        'value': value,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'isActive': isActive ? 1 : 0,
      };

  factory AlertEvent.fromMap(Map<String, dynamic> map) => AlertEvent(
        id: map['id'] as int?,
        severity: AlertSeverity.values[map['severity'] as int],
        type: AlertType.values[map['type'] as int],
        title: map['title'] as String,
        message: map['message'] as String,
        value: (map['value'] as num).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        isActive: (map['isActive'] as int) == 1,
      );

  /// Human-readable severity label
  String get severityLabel {
    switch (severity) {
      case AlertSeverity.warning:
        return 'WARNING';
      case AlertSeverity.alert:
        return 'ALERT';
      case AlertSeverity.critical:
        return 'CRITICAL';
    }
  }
}
