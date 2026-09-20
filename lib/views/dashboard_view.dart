import 'package:flutter/material.dart';
import '../viewmodels/dashboard_viewmodel.dart';
import '../utils/color_helpers.dart';
import '../utils/formatters.dart';

import '../widgets/card_widget.dart';
import '../widgets/title_widget.dart';
import '../widgets/metric.dart';
import '../widgets/mini_panel.dart';
import '../widgets/info_strip.dart';
import '../widgets/status_pill.dart';
import '../widgets/warning_widget.dart';
import '../widgets/load_progress_bar.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  double batteryPercent(double voltage) {
    var points = <double, double>{
      46: 0, 47: 10, 48: 25, 49: 45, 50: 65, 51: 80, 52: 95, 53: 100,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final telemetry = _viewModel.telemetry;
            final loading = _viewModel.loading;
            final error = _viewModel.error;
            
            final online = telemetry.inverterConnected &&
                telemetry.status.toLowerCase() == 'online';
            final soc = batteryPercent(telemetry.batteryVoltage);
            final loadColor = getLoadColor(telemetry.loadPercentage);
            final batteryColor = getBatteryColor(telemetry.batteryVoltage);
            final solarColor = getSolarColor(telemetry.pvPower);

            return RefreshIndicator(
              onRefresh: () async {
                // Ignore since ViewModel auto polls, or could expose manual refresh
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF55D6BE), Color(0xFF2FA4FF)],
                          ),
                        ),
                        child: const Icon(Icons.bolt_rounded),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Inverter',
                                style: TextStyle(
                                    fontSize: 27, fontWeight: FontWeight.w800)),
                            Text('Live energy dashboard',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: loading ? null : () {},
                        icon: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh_rounded),
                      ),
                      StatusPill(online: online),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    WarningWidget(message: error),
                  ],

                  const SizedBox(height: 16),
                  LoadProgressBar(
                    loadPercent: telemetry.loadPercentage,
                    color: loadColor,
                  ),

                  const SizedBox(height: 14),
                  CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomTitle(
                          icon: Icons.battery_charging_full_rounded,
                          title: 'Battery',
                          subtitle: telemetry.batteryVoltage > 0
                              ? '48 V • ${getBatteryLabel(telemetry.batteryVoltage)}'
                              : '48 V tubular / lead-acid',
                          subtitleColor: telemetry.batteryVoltage > 0
                              ? batteryColor
                              : null,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            SizedBox(
                              width: 110,
                              height: 110,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 80,
                                    height: 80,
                                    child: CircularProgressIndicator(
                                      value: soc / 100,
                                      strokeWidth: 9,
                                      backgroundColor: Colors.white10,
                                      valueColor:
                                          AlwaysStoppedAnimation(batteryColor),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${soc.round()}%',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: batteryColor)),
                                      const Text('estimated',
                                          style: TextStyle(
                                              fontSize: 9, color: Colors.white38)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MiniPanel(
                                    title: 'VOLTAGE',
                                    icon: Icons.electrical_services_rounded,
                                    text: telemetry.batteryVoltage > 0
                                        ? '${telemetry.batteryVoltage.toStringAsFixed(2)} V'
                                        : '—',
                                  ),
                                  const SizedBox(height: 10),
                                  MiniPanel(
                                    title: 'CHRG CURRENT',
                                    icon: Icons.electric_meter_rounded,
                                    text: '${telemetry.batteryCurrent.abs().toStringAsFixed(1)} A',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        InfoStrip(
                          icon: Icons.bolt_rounded,
                          iconColor: batteryColor,
                          text: telemetry.batteryVoltage > 0
                              ? '${formatPower(telemetry.batteryVoltage * telemetry.batteryCurrent.abs())} battery power'
                              : 'No battery telemetry',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CustomTitle(
                          icon: Icons.wb_sunny_rounded,
                          title: 'Solar',
                          subtitle: telemetry.pvPower > 0
                              ? 'PV input • ${getSolarLabel(telemetry.pvPower)}'
                              : 'PV input',
                          subtitleColor: telemetry.pvPower > 0
                              ? solarColor
                              : null,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                                child: Metric('PV VOLTAGE',
                                    telemetry.pvVoltage.toStringAsFixed(0), 'V')),
                            Expanded(
                                child: Metric('PV CURRENT',
                                    telemetry.pvCurrent.toStringAsFixed(1), 'A')),
                            Expanded(
                                child: Metric(
                              'POWER',
                              formatPower(telemetry.pvPower),
                              '',
                              valueColor: solarColor,
                            )),
                          ],
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(
                          value: (telemetry.pvPower / 6100).clamp(0, 1),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(10),
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation(solarColor),
                        ),
                        const SizedBox(height: 7),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('6.1 kW inverter',
                              style: TextStyle(
                                  color: solarColor, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CustomTitle(
                          icon: Icons.power_rounded,
                          title: 'Grid & Load',
                          subtitle: 'AC input / inverter output',
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: MiniPanel(
                                title: 'OUTPUT',
                                icon: Icons.outlet_rounded,
                                text:
                                    '${telemetry.acOutputVoltage.toStringAsFixed(0)} V\n${telemetry.acOutputFrequency.toStringAsFixed(1)} Hz',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: MiniPanel(
                                title: 'GRID INPUT',
                                icon: Icons.electrical_services_rounded,
                                text: telemetry.acInputVoltage > 0
                                    ? '${telemetry.acInputVoltage.toStringAsFixed(0)} V  •  ${telemetry.acInputFrequency.toStringAsFixed(1)} Hz'
                                    : 'No grid',
                              ),
                            ),
                          ],
                        ),

                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  CustomCard(
                    child: Row(
                      children: [
                        const Icon(Icons.insights_rounded,
                            color: Color(0xFF5B9DFF), size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PV ENERGY',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1)),
                              Text(telemetry.pvEnergy.toStringAsFixed(0),
                                  style: const TextStyle(
                                      fontSize: 24, fontWeight: FontWeight.w800)),
                              const Text('as reported by inverter',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.white38)),
                            ],
                          ),
                        ),
                        Text('${telemetry.lastUpdateMs} ms',
                            style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text('Eastman Smart Max • ESP32 monitor',
                        style: TextStyle(color: Colors.white30, fontSize: 12)),
                  ),
                ],
              ),
            );
          }
        ),
      ),
    );
  }
}
