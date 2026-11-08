import 'package:flutter_test/flutter_test.dart';
import 'package:inverter_dashboard/models/controls_state.dart';

void main() {
  testWidgets('Controls smoke test', (WidgetTester tester) async {
    const testState = ControlsState.initial;
    expect(testState.socket1.isAuto, true);
    expect(testState.socket2.isAuto, true);
    expect(testState.socket1.state, false);
    expect(testState.socket2.state, false);
  });
}
