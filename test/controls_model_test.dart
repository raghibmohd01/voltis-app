import 'package:flutter_test/flutter_test.dart';
import 'package:inverter_dashboard/models/controls_state.dart';

void main() {
  group('ControlsState Models Test', () {
    test('Correctly parses ControlsState from JSON map', () {
      final json = {
        'socket1': {
          'state': true,
          'mode': 'AUTO',
          'reason': 'Auto ON: Solar surplus active',
          'cooldown_remaining_sec': 0,
        },
        'socket2': {
          'state': false,
          'mode': 'MANUAL',
          'reason': 'Manual OFF',
          'sunset_minutes': 1052,
        },
        'config': {
          's1_pv_on': 1200.0,
          's1_pv_off': 1050.0,
          's1_load_max': 45.0,
          's1_soc_min': 85.0,
          's1_soc_cutoff': 75.0,
          's1_cooldown': 240,
          's2_off_hour': 23,
          's2_off_min': 30,
        },
        'last_updated': 1729000000,
      };

      final state = ControlsState.fromJson(json);

      expect(state.socket1.state, true);
      expect(state.socket1.mode, 'AUTO');
      expect(state.socket1.isAuto, true);
      expect(state.socket1.isManual, false);
      expect(state.socket1.reason, 'Auto ON: Solar surplus active');
      expect(state.socket1.cooldownRemainingSec, 0);

      expect(state.socket2.state, false);
      expect(state.socket2.mode, 'MANUAL');
      expect(state.socket2.isAuto, false);
      expect(state.socket2.isManual, true);
      expect(state.socket2.reason, 'Manual OFF');
      expect(state.socket2.sunsetMinutes, 1052);

      expect(state.config.s1PvOnWatts, 1200.0);
      expect(state.config.s1PvOffWatts, 1050.0);
      expect(state.config.s1LoadMaxPct, 45.0);
      expect(state.config.s1SocMinPct, 85.0);
      expect(state.config.s1SocCutoffPct, 75.0);
      expect(state.config.s1CooldownSec, 240);
      expect(state.config.s2OffHour, 23);
      expect(state.config.s2OffMin, 30);
    });

    test('Serializes ControlsConfig to JSON', () {
      const cfg = ControlsConfig(
        s1PvOnWatts: 1500.0,
        s1LoadMaxPct: 40.0,
      );
      final json = cfg.toJson();
      expect(json['s1_pv_on'], 1500.0);
      expect(json['s1_load_max'], 40.0);
    });
  });
}

