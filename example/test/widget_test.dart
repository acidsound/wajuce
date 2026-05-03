import 'package:flutter_test/flutter_test.dart';
import 'package:wajuce_example/main.dart';

void main() {
  test('scheduler labels match the selected timing policy', () {
    expect(
      WASchedulerTimingPolicy.modeLabel(WASchedulerMode.precise),
      'Precise (Timeline)',
    );
    expect(
      WASchedulerTimingPolicy.modeLabel(WASchedulerMode.live),
      'Live (Low Latency)',
    );
  });
}
