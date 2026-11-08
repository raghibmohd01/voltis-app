import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/controls_service.dart';
import '../services/hybrid_telemetry_service.dart';
import '../models/controls_state.dart';
import '../models/telemetry.dart';
import '../utils/formatters.dart';
import '../widgets/status_pill.dart';

class ControlsView extends StatefulWidget {
  const ControlsView({super.key});

  @override
  State<ControlsView> createState() => _ControlsViewState();
}

class _ControlsViewState extends State<ControlsView>
    with SingleTickerProviderStateMixin {
  final ControlsService _controlsService = ControlsService.instance;
  final HybridTelemetryService _telemetryService = HybridTelemetryService.instance;

  StreamSubscription<ControlsState>? _controlsSub;
  StreamSubscription<Telemetry>? _telemetrySub;

  ControlsState _controls = ControlsState.initial;
  Telemetry _telemetry = Telemetry.empty;
  bool _isSendingCommand = false;

  // Intermediate transition state tracking
  late AnimationController _transitionController;
  int? _transitioningSocket; // 1 or 2
  bool? _transitionTargetState; // Target state during transition (true = ON, false = OFF)

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _controlsService.start();
    _controls = _controlsService.latestState;

    _controlsSub = _controlsService.controlsStream.listen((state) {
      if (mounted) {
        setState(() {
          // If a socket is actively transitioning, don't let an in-flight delayed state revert it
          if (_transitioningSocket == 1 && _transitionTargetState != null) {
            _controls = state.copyWith(
              socket1: state.socket1.copyWith(
                state: _transitionTargetState,
                mode: 'MANUAL',
              ),
            );
          } else if (_transitioningSocket == 2 && _transitionTargetState != null) {
            _controls = state.copyWith(
              socket2: state.socket2.copyWith(
                state: _transitionTargetState,
                mode: 'MANUAL',
              ),
            );
          } else {
            _controls = state;
          }
        });
      }
    });

    _telemetrySub = _telemetryService.telemetryStream.listen((data) {
      if (mounted) {
        setState(() {
          _telemetry = data;
        });
      }
    });
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _controlsSub?.cancel();
    _telemetrySub?.cancel();
    super.dispose();
  }

  double _batteryPercent(double voltage) {
    var points = <double, double>{
      42.0: 0, 44.5: 10, 45.8: 20, 46.8: 30, 47.6: 40,
      48.2: 50, 48.7: 60, 49.1: 70, 49.6: 80, 50.0: 90, 50.4: 100,
      54.0: 100,
    };
    final keys = points.keys.toList()..sort();
    if (voltage <= keys.first) return 0;
    if (voltage >= keys.last) return 100;
    for (var n = 0; n < keys.length - 1; n++) {
      final a = keys[n], b = keys[n + 1];
      if (voltage >= a && voltage <= b) {
        final f = (voltage - a) / (b - a);
        return points[a]! + (points[b]! - points[a]!) * f;
      }
    }
    return 0;
  }

  Future<void> _handleModeChange(int socket, String newMode, bool currentState) async {
    if (_isSendingCommand || _transitioningSocket != null) return;
    HapticFeedback.selectionClick();
    setState(() => _isSendingCommand = true);
    try {
      await _controlsService.sendCommand(
        socket: socket,
        mode: newMode,
        state: currentState,
      );
      if (mounted) {
        setState(() {
          if (socket == 1) {
            _controls = _controls.copyWith(
              socket1: _controls.socket1.copyWith(mode: newMode),
            );
          } else {
            _controls = _controls.copyWith(
              socket2: _controls.socket2.copyWith(mode: newMode),
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isSendingCommand = false);
    }
  }

  Future<void> _toggleSocket(int socket, bool targetState) async {
    if (_isSendingCommand || _transitioningSocket != null) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isSendingCommand = true;
      _transitioningSocket = socket;
      _transitionTargetState = targetState;
    });
    _transitionController.repeat();

    final stopwatch = Stopwatch()..start();

    try {
      await _controlsService.sendCommand(
        socket: socket,
        mode: 'MANUAL',
        state: targetState,
      );

      // Optimistically apply target state immediately so the button transitions directly
      if (mounted) {
        setState(() {
          if (socket == 1) {
            _controls = _controls.copyWith(
              socket1: _controls.socket1.copyWith(
                state: targetState,
                mode: 'MANUAL',
                reason: targetState ? 'Manual ON' : 'Manual OFF',
              ),
            );
          } else {
            _controls = _controls.copyWith(
              socket2: _controls.socket2.copyWith(
                state: targetState,
                mode: 'MANUAL',
                reason: targetState ? 'Manual ON' : 'Manual OFF',
              ),
            );
          }
        });
      }

      // Ensure intermediate transition animation displays for at least 700ms for smooth visual feedback
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 700) {
        await Future.delayed(Duration(milliseconds: 700 - elapsed));
      }
    } catch (e) {
      debugPrint('Failed to send socket command: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingCommand = false;
          _transitioningSocket = null;
          _transitionTargetState = null;
        });
        _transitionController.stop();
        _transitionController.reset();
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _onPowerButtonPressed(int socket, bool currentState, bool isAuto) {
    if (_isSendingCommand || _transitioningSocket != null) return;
    final targetState = !currentState;
    _toggleSocket(socket, targetState);
  }

  void _showConfigSheet() {
    final cfg = _controls.config;
    double pvOn = cfg.s1PvOnWatts;
    double loadMax = cfg.s1LoadMaxPct;
    double socMin = cfg.s1SocMinPct;
    double socCut = cfg.s1SocCutoffPct;
    int cooldown = cfg.s1CooldownSec;
    int offHour = cfg.s2OffHour;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12161E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle pill
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Sheet Header
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF55D6BE).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Color(0xFF55D6BE), size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Automation Thresholds',
                                style: TextStyle(
                                  color: Color(0xFFDCE2EC),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'ESP32 Edge Protection Settings',
                                style: TextStyle(
                                  color: Color(0xFF8E9BAE),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF8E9BAE)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // Geyser Rules Title
                    const Text(
                      'SOCKET 1: GEYSER AUTOMATION',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Min Solar PV Slider
                    _buildSliderTile(
                      label: 'Min Solar Generation',
                      valueStr: '${pvOn.round()} W',
                      value: pvOn,
                      min: 500,
                      max: 3000,
                      divisions: 25,
                      unit: 'W',
                      onChanged: (v) => setSheetState(() => pvOn = v),
                    ),
                    const SizedBox(height: 12),

                    // Max House Load Slider
                    _buildSliderTile(
                      label: 'Max House Load Before Cutoff',
                      valueStr: '${loadMax.round()}%',
                      value: loadMax,
                      min: 20,
                      max: 80,
                      divisions: 12,
                      unit: '%',
                      onChanged: (v) => setSheetState(() => loadMax = v),
                    ),
                    const SizedBox(height: 12),

                    // Battery Turn-ON SOC Slider
                    _buildSliderTile(
                      label: 'Min Battery SOC to Turn ON',
                      valueStr: '${socMin.round()}%',
                      value: socMin,
                      min: 50,
                      max: 95,
                      divisions: 9,
                      unit: '%',
                      onChanged: (v) => setSheetState(() => socMin = v),
                    ),
                    const SizedBox(height: 12),

                    // Battery Cutoff SOC Slider
                    _buildSliderTile(
                      label: 'Safe Cutoff SOC (Immediate OFF)',
                      valueStr: '${socCut.round()}%',
                      value: socCut,
                      min: 40,
                      max: 85,
                      divisions: 9,
                      unit: '%',
                      onChanged: (v) => setSheetState(() => socCut = v),
                    ),
                    const SizedBox(height: 12),

                    // Cooldown Timer
                    _buildSliderTile(
                      label: 'Anti-Cycling Cooldown',
                      valueStr: '${cooldown}s (${(cooldown / 60).toStringAsFixed(1)}m)',
                      value: cooldown.toDouble(),
                      min: 60,
                      max: 600,
                      divisions: 18,
                      unit: 's',
                      onChanged: (v) => setSheetState(() => cooldown = v.round()),
                    ),
                    const SizedBox(height: 24),

                    // Outdoor Light Schedule Title
                    const Text(
                      'SOCKET 2: OUTDOOR LIGHT SCHEDULE',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Off Cutoff Hour
                    _buildSliderTile(
                      label: 'Night Turn-OFF Cutoff Hour',
                      valueStr: '${offHour.toString().padLeft(2, '0')}:00',
                      value: offHour.toDouble(),
                      min: 19,
                      max: 24,
                      divisions: 5,
                      unit: 'h',
                      onChanged: (v) => setSheetState(() => offHour = v.round()),
                    ),
                    const SizedBox(height: 28),

                    // Save & Apply Button
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF55D6BE), Color(0xFF2FA4FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF55D6BE).withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          final updated = ControlsConfig(
                            s1PvOnWatts: pvOn,
                            s1PvOffWatts: pvOn - 100.0,
                            s1LoadMaxPct: loadMax,
                            s1SocMinPct: socMin,
                            s1SocCutoffPct: socCut,
                            s1CooldownSec: cooldown,
                            s2OffHour: offHour,
                            s2OffMin: 0,
                          );
                          _controlsService.updateConfig(updated);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Thresholds updated and synced to ESP32!'),
                              backgroundColor: Color(0xFF1F2937),
                            ),
                          );
                        },
                        child: const Text(
                          'Save & Sync to ESP32',
                          style: TextStyle(
                            color: Color(0xFF0D1117),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSliderTile({
    required String label,
    required String valueStr,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFDCE2EC),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF55D6BE).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueStr,
                  style: const TextStyle(
                    color: Color(0xFF55D6BE),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF55D6BE),
              inactiveTrackColor: Colors.white.withOpacity(0.08),
              thumbColor: const Color(0xFF55D6BE),
              overlayColor: const Color(0xFF55D6BE).withOpacity(0.15),
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final soc = _batteryPercent(_telemetry.batteryVoltage);
    final isOnline = _telemetry.inverterConnected &&
        _telemetry.status.toLowerCase() == 'online';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
          children: [
            // ── Modern Header Unified with Dashboard ──────────────────
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF55D6BE), Color(0xFF2FA4FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF55D6BE).withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF0D1117), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Controls',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDCE2EC),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Dual-Relay Automation',
                        style: TextStyle(color: Color(0xFF8E9BAE), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Thresholds Settings Button
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.055),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.tune_rounded, color: Color(0xFFDCE2EC), size: 19),
                    onPressed: _showConfigSheet,
                    tooltip: 'Configure Thresholds',
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(online: isOnline),
              ],
            ),
            const SizedBox(height: 14),

            // ── Socket 1: Geyser Card ────────────────────────────────
            _buildSocket1Card(soc),
            const SizedBox(height: 14),

            // ── Socket 2: Outdoor Light Card ─────────────────────────
            _buildSocket2Card(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Socket 1: Geyser Card ──────────────────────────────────────────
  Widget _buildSocket1Card(double currentSoc) {
    final s1 = _controls.socket1;
    final isAuto = s1.isAuto;
    final isOn = s1.state;
    final cfg = _controls.config;

    final pvMet = _telemetry.pvPower >= cfg.s1PvOnWatts;
    final loadMet = _telemetry.loadPercentage < cfg.s1LoadMaxPct;
    final socMet = currentSoc >= cfg.s1SocMinPct;
    const accentColor = Color(0xFF55D6BE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12161E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isOn
              ? accentColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.04),
          width: isOn ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isOn
                ? accentColor.withOpacity(0.10)
                : Colors.black.withOpacity(0.2),
            blurRadius: isOn ? 18 : 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon, Title & Mode Badge
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isOn
                      ? accentColor.withOpacity(0.15)
                      : Colors.white.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.hot_tub_rounded,
                  color: isOn ? accentColor : const Color(0xFF8E9BAE),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Socket 1 • Geyser',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDCE2EC),
                        letterSpacing: -0.1,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Water Heater',
                      style: TextStyle(
                        color: Color(0xFF8E9BAE),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _buildPowerBadge(isOn, isAuto: isAuto),
            ],
          ),
          const SizedBox(height: 12),

          // ── Hero Section: Power Toggle & Clean State ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                _buildLargeCircularPowerButton(
                  socket: 1,
                  isOn: isOn,
                  isAuto: isAuto,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 13,
                            color: isOn ? const Color(0xFF2ECC71) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOn ? 'HEATING POWER' : 'POWER DRAW',
                            style: const TextStyle(
                              color: Color(0xFF8E9BAE),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isOn ? '2.0 kW' : '0 W',
                        style: TextStyle(
                          color: isOn ? const Color(0xFF2ECC71) : const Color(0xFFDCE2EC),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (s1.cooldownRemainingSec > 0)
                        Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded, size: 12, color: Color(0xFFFFB020)),
                            const SizedBox(width: 4),
                            Text(
                              'Cooldown: ${s1.cooldownRemainingSec}s',
                              style: const TextStyle(
                                color: Color(0xFFFFB020),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          isOn
                              ? 'Active heating load (~8.7A)'
                              : (isAuto ? 'Ready for solar heating' : 'Manual Standby'),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Compact Segmented Mode Selector (Prevents overflow)
          _buildSegmentedModeBar(
            isAuto: isAuto,
            onManualTap: () => _handleModeChange(1, 'MANUAL', isOn),
            onAutoTap: () => _handleModeChange(1, 'AUTO', isOn),
            autoLabel: 'Solar Auto',
          ),

          // Contextual State Display: Only shown in Auto mode to keep Manual clean
          if (isAuto) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.03)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOn ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                        size: 14,
                        color: isOn ? const Color(0xFF2ECC71) : const Color(0xFF8E9BAE),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s1.reason.isEmpty ? (isOn ? 'Auto Active' : 'Standby') : s1.reason,
                          style: TextStyle(
                            color: isOn ? const Color(0xFF2ECC71) : const Color(0xFF8E9BAE),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (s1.cooldownRemainingSec > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB020).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${s1.cooldownRemainingSec}s',
                            style: const TextStyle(
                              color: Color(0xFFFFB020),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildGateChip(
                          title: 'SOLAR PV',
                          target: '> ${cfg.s1PvOnWatts.round()}W',
                          actual: formatPower(_telemetry.pvPower),
                          isMet: pvMet,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildGateChip(
                          title: 'LOAD',
                          target: '< ${cfg.s1LoadMaxPct.round()}%',
                          actual: '${_telemetry.loadPercentage.toStringAsFixed(0)}%',
                          isMet: loadMet,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildGateChip(
                          title: 'SOC',
                          target: '≥ ${cfg.s1SocMinPct.round()}%',
                          actual: '${currentSoc.toStringAsFixed(0)}%',
                          isMet: socMet,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Socket 2: Outdoor Light Card ───────────────────────────────────
  Widget _buildSocket2Card() {
    final s2 = _controls.socket2;
    final isAuto = s2.isAuto;
    final isOn = s2.state;
    final cfg = _controls.config;
    const accentColor = Color(0xFFFFB020);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12161E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isOn
              ? accentColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.04),
          width: isOn ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isOn
                ? accentColor.withOpacity(0.10)
                : Colors.black.withOpacity(0.2),
            blurRadius: isOn ? 18 : 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Icon, Title & Mode Badge
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isOn
                      ? accentColor.withOpacity(0.15)
                      : Colors.white.withOpacity(0.055),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.lightbulb_rounded,
                  color: isOn ? accentColor : const Color(0xFF8E9BAE),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Socket 2 • Outdoor Light',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDCE2EC),
                        letterSpacing: -0.1,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Sunset Schedule',
                      style: TextStyle(
                        color: Color(0xFF8E9BAE),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _buildPowerBadge(isOn, isAuto: isAuto),
            ],
          ),
          const SizedBox(height: 12),

          // ── Hero Section: Power Toggle & Schedule State ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Row(
              children: [
                _buildLargeCircularPowerButton(
                  socket: 2,
                  isOn: isOn,
                  isAuto: isAuto,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.wb_twilight_rounded,
                            size: 14,
                            color: Color(0xFFFFB020),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'SCHEDULE',
                            style: TextStyle(
                              color: Color(0xFF8E9BAE),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Sunset → 22:00',
                        style: TextStyle(
                          color: Color(0xFFDCE2EC),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isOn
                            ? (isAuto ? '● Active until 22:00' : '● Manually switched ON')
                            : (isAuto ? 'Turns on at Sunset (~18:15)' : 'Standby (Schedule off)'),
                        style: TextStyle(
                          color: isOn ? const Color(0xFF2ECC71) : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Compact Segmented Mode Selector (Prevents overflow)
          _buildSegmentedModeBar(
            isAuto: isAuto,
            onManualTap: () => _handleModeChange(2, 'MANUAL', isOn),
            onAutoTap: () => _handleModeChange(2, 'AUTO', isOn),
            autoLabel: 'Schedule',
          ),
        ],
      ),
    );
  }

  // ── Large Circular Power Button with Animated Transition State ─────
  Widget _buildLargeCircularPowerButton({
    required int socket,
    required bool isOn,
    required bool isAuto,
  }) {
    const Color onColor = Color(0xFF2ECC71); // Vibrant Emerald Green for ON state
    final bool isThisSocketTransitioning = _transitioningSocket == socket;
    final bool? targetState = isThisSocketTransitioning ? _transitionTargetState : null;
    final Color transitionColor = (targetState == true) ? onColor : const Color(0xFFFFB020);

    return AnimatedBuilder(
      animation: _transitionController,
      builder: (context, _) {
        final double spinProgress = _transitionController.value;
        final double pulseScale = isThisSocketTransitioning
            ? (0.95 + 0.05 * math.sin(spinProgress * math.pi * 2))
            : 1.0;
        final double pulseOpacity = isThisSocketTransitioning
            ? (0.6 + 0.4 * math.sin(spinProgress * math.pi * 2).abs())
            : 1.0;

        return SizedBox(
          width: 90,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: (_transitioningSocket != null || _isSendingCommand)
                    ? null
                    : () => _onPowerButtonPressed(socket, isOn, isAuto),
                child: Transform.scale(
                  scale: pulseScale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isThisSocketTransitioning
                          ? transitionColor.withOpacity(0.12)
                          : (isOn
                              ? onColor.withOpacity(0.20)
                              : const Color(0xFF131720)),
                      border: Border.all(
                        color: isThisSocketTransitioning
                            ? transitionColor.withOpacity(0.50)
                            : (isOn
                                ? onColor.withOpacity(0.60)
                                : Colors.white.withOpacity(0.08)),
                        width: isOn || isThisSocketTransitioning ? 2.0 : 1.5,
                      ),
                      boxShadow: [
                        if (isThisSocketTransitioning) ...[
                          BoxShadow(
                            color: transitionColor.withOpacity(0.42 * pulseOpacity),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: transitionColor.withOpacity(0.18 * pulseOpacity),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ] else if (isOn) ...[
                          BoxShadow(
                            color: onColor.withOpacity(0.38),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: onColor.withOpacity(0.15),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ] else ...[
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Spinning neon gradient ring during intermediate transition
                        if (isThisSocketTransitioning)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TransitionRingPainter(
                                progress: spinProgress,
                                color: transitionColor,
                              ),
                            ),
                          ),

                        // Inner Button Surface
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: (isOn && !isThisSocketTransitioning)
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      onColor,
                                      Color(0xFF27AE60),
                                    ],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(0.06),
                                      Colors.white.withOpacity(0.01),
                                    ],
                                  ),
                          ),
                          child: Center(
                            child: isThisSocketTransitioning
                                ? Transform.rotate(
                                    angle: spinProgress * math.pi * 2,
                                    child: Icon(
                                      Icons.sync_rounded,
                                      color: transitionColor,
                                      size: 26,
                                    ),
                                  )
                                : Icon(
                                    Icons.power_settings_new_rounded,
                                    color: isOn ? const Color(0xFF0D1117) : const Color(0xFF64748B),
                                    size: 28,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),

              // Animated / Dynamic Status Label
              if (isThisSocketTransitioning) ...[
                Text(
                  targetState == true ? 'ENERGIZING...' : 'SWITCH OFF...',
                  style: TextStyle(
                    color: transitionColor.withOpacity(pulseOpacity),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else ...[
                Text(
                  isOn ? 'POWER ON' : 'STANDBY',
                  style: TextStyle(
                    color: isOn ? onColor : const Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Power ON/OFF Status Badge ─────────────────────────────────────
  Widget _buildPowerBadge(bool isOn, {bool isAuto = false}) {
    final color = isOn ? const Color(0xFF2ECC71) : const Color(0xFF64748B);
    final text = isAuto ? (isOn ? 'AUTO ON' : 'AUTO OFF') : (isOn ? 'ON' : 'OFF');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOn ? color.withOpacity(0.15) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOn ? color.withOpacity(0.4) : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: isOn
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.8),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: isOn ? const Color(0xFFDCE2EC) : const Color(0xFF8E9BAE),
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented Mode Bar ────────────────────────────────────────────
  Widget _buildSegmentedModeBar({
    required bool isAuto,
    required VoidCallback onManualTap,
    required VoidCallback onAutoTap,
    required String autoLabel,
  }) {
    final bool isLocked = _transitioningSocket != null || _isSendingCommand;
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (!isAuto || isLocked) ? null : onManualTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !isAuto ? const Color(0xFF1E2430) : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: !isAuto ? Border.all(color: Colors.white.withOpacity(0.08)) : null,
                  boxShadow: !isAuto
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 15,
                      color: !isAuto ? const Color(0xFFDCE2EC) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Manual',
                      style: TextStyle(
                        color: !isAuto ? const Color(0xFFDCE2EC) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: (isAuto || isLocked) ? null : onAutoTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isAuto ? const Color(0xFF55D6BE).withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: isAuto
                      ? Border.all(color: const Color(0xFF55D6BE).withOpacity(0.3))
                      : null,
                  boxShadow: isAuto
                      ? [
                          BoxShadow(
                            color: const Color(0xFF55D6BE).withOpacity(0.12),
                            blurRadius: 10,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_mode_rounded,
                      size: 15,
                      color: isAuto ? const Color(0xFF55D6BE) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      autoLabel,
                      style: TextStyle(
                        color: isAuto ? const Color(0xFF55D6BE) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Auto Gate Chip ────────────────────────────────────────────────
  Widget _buildGateChip({
    required String title,
    required String target,
    required String actual,
    required bool isMet,
  }) {
    final statusColor = isMet ? const Color(0xFF2ECC71) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMet ? const Color(0xFF2ECC71).withOpacity(0.08) : Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMet ? const Color(0xFF2ECC71).withOpacity(0.25) : Colors.white.withOpacity(0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 11,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            actual,
            style: TextStyle(
              color: isMet ? const Color(0xFFDCE2EC) : const Color(0xFF8E9BAE),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            target,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransitionRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _TransitionRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 5) / 2;
    const strokeWidth = 3.0;

    final paintBg = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, paintBg);

    final sweepGradient = SweepGradient(
      startAngle: 0.0,
      endAngle: math.pi * 2,
      colors: [
        color.withOpacity(0.0),
        color.withOpacity(0.3),
        color,
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: GradientRotation(progress * math.pi * 2),
    );

    final paintArc = Paint()
      ..shader = sweepGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * math.pi * 2,
      math.pi * 1.5,
      false,
      paintArc,
    );
  }

  @override
  bool shouldRepaint(_TransitionRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
