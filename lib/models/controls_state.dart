class SocketControl {
  final bool state;
  final String mode; // 'AUTO' or 'MANUAL'
  final String reason;
  final int cooldownRemainingSec;
  final int sunsetMinutes;

  const SocketControl({
    required this.state,
    required this.mode,
    required this.reason,
    this.cooldownRemainingSec = 0,
    this.sunsetMinutes = 1080,
  });

  bool get isAuto => mode.toUpperCase() == 'AUTO';
  bool get isManual => !isAuto;

  factory SocketControl.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return const SocketControl(
        state: false,
        mode: 'AUTO',
        reason: 'No data',
      );
    }
    return SocketControl(
      state: json['state'] == true,
      mode: (json['mode'] ?? 'AUTO').toString().toUpperCase(),
      reason: json['reason']?.toString() ?? '',
      cooldownRemainingSec: (json['cooldown_remaining_sec'] as num?)?.toInt() ?? 0,
      sunsetMinutes: (json['sunset_minutes'] as num?)?.toInt() ?? 1080,
    );
  }

  SocketControl copyWith({
    bool? state,
    String? mode,
    String? reason,
    int? cooldownRemainingSec,
    int? sunsetMinutes,
  }) {
    return SocketControl(
      state: state ?? this.state,
      mode: mode ?? this.mode,
      reason: reason ?? this.reason,
      cooldownRemainingSec: cooldownRemainingSec ?? this.cooldownRemainingSec,
      sunsetMinutes: sunsetMinutes ?? this.sunsetMinutes,
    );
  }
}

class ControlsConfig {
  final double s1PvOnWatts;
  final double s1PvOffWatts;
  final double s1LoadMaxPct;
  final double s1SocMinPct;
  final double s1SocCutoffPct;
  final int s1CooldownSec;
  final int s2OffHour;
  final int s2OffMin;

  const ControlsConfig({
    this.s1PvOnWatts = 1000.0,
    this.s1PvOffWatts = 900.0,
    this.s1LoadMaxPct = 50.0,
    this.s1SocMinPct = 80.0,
    this.s1SocCutoffPct = 70.0,
    this.s1CooldownSec = 180,
    this.s2OffHour = 22,
    this.s2OffMin = 0,
  });

  factory ControlsConfig.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return const ControlsConfig();
    double d(String key, double fallback) {
      final v = json[key];
      return v is num ? v.toDouble() : fallback;
    }
    int i(String key, int fallback) {
      final v = json[key];
      return v is num ? v.toInt() : fallback;
    }
    return ControlsConfig(
      s1PvOnWatts: d('s1_pv_on', 1000.0),
      s1PvOffWatts: d('s1_pv_off', 900.0),
      s1LoadMaxPct: d('s1_load_max', 50.0),
      s1SocMinPct: d('s1_soc_min', 80.0),
      s1SocCutoffPct: d('s1_soc_cutoff', 70.0),
      s1CooldownSec: i('s1_cooldown', 180),
      s2OffHour: i('s2_off_hour', 22),
      s2OffMin: i('s2_off_min', 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      's1_pv_on': s1PvOnWatts,
      's1_pv_off': s1PvOffWatts,
      's1_load_max': s1LoadMaxPct,
      's1_soc_min': s1SocMinPct,
      's1_soc_cutoff': s1SocCutoffPct,
      's1_cooldown': s1CooldownSec,
      's2_off_hour': s2OffHour,
      's2_off_min': s2OffMin,
    };
  }
}

class ControlsState {
  final SocketControl socket1;
  final SocketControl socket2;
  final ControlsConfig config;
  final int lastUpdated;

  const ControlsState({
    required this.socket1,
    required this.socket2,
    required this.config,
    required this.lastUpdated,
  });

  static const initial = ControlsState(
    socket1: SocketControl(state: false, mode: 'AUTO', reason: 'Awaiting ESP32 firmware sync'),
    socket2: SocketControl(state: false, mode: 'AUTO', reason: 'Awaiting ESP32 firmware sync'),
    config: ControlsConfig(),
    lastUpdated: 0,
  );

  factory ControlsState.fromJson(Map<dynamic, dynamic> json) {
    final s1 = json['socket1'] as Map<dynamic, dynamic>?;
    final s2 = json['socket2'] as Map<dynamic, dynamic>?;
    final cfg = json['config'] as Map<dynamic, dynamic>?;

    return ControlsState(
      socket1: SocketControl.fromJson(s1),
      socket2: SocketControl.fromJson(s2),
      config: ControlsConfig.fromJson(cfg),
      lastUpdated: (json['last_updated'] as num?)?.toInt() ?? 0,
    );
  }

  ControlsState copyWith({
    SocketControl? socket1,
    SocketControl? socket2,
    ControlsConfig? config,
    int? lastUpdated,
  }) {
    return ControlsState(
      socket1: socket1 ?? this.socket1,
      socket2: socket2 ?? this.socket2,
      config: config ?? this.config,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

