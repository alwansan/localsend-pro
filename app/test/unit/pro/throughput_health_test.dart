import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/throughput_health.dart';

void main() {
  test('needs multiple sustained slow samples; one dip never restarts transfer', () {
    final h = ProThroughputHealthMonitor();
    final start = DateTime(2026, 11, 21);
    expect(h.observe(start, 0), ProTransferHealth.warmup);
    expect(h.observe(start.add(const Duration(seconds: 1)), 5000000), ProTransferHealth.healthy);
    expect(h.observe(start.add(const Duration(seconds: 2)), 5050000), ProTransferHealth.healthy);
    expect(h.observe(start.add(const Duration(seconds: 3)), 5100000), ProTransferHealth.healthy);
    expect(h.observe(start.add(const Duration(seconds: 4)), 5150000), ProTransferHealth.degraded);
    expect(h.observe(start.add(const Duration(seconds: 5)), 10150000), ProTransferHealth.healthy);
  });

  test('zero progress must persist before a stalled signal', () {
    final h = ProThroughputHealthMonitor();
    final start = DateTime(2026, 11, 21);
    expect(h.observe(start, 0), ProTransferHealth.warmup);
    expect(h.observe(start.add(const Duration(seconds: 1)), 2000000), ProTransferHealth.healthy);
    expect(h.observe(start.add(const Duration(seconds: 5)), 2000000), ProTransferHealth.healthy);
    expect(h.observe(start.add(const Duration(seconds: 9)), 2000000), ProTransferHealth.stalled);
    expect(h.observe(start.add(const Duration(seconds: 10)), 2100000), ProTransferHealth.healthy);
  });

  test('new transfer with lower byte count resets learned baseline', () {
    final h = ProThroughputHealthMonitor();
    final start = DateTime(2026, 11, 21);
    h.observe(start, 5000000);
    h.observe(start.add(const Duration(seconds: 1)), 10000000);
    expect(h.observe(start.add(const Duration(seconds: 2)), 0), ProTransferHealth.warmup);
    expect(h.referenceBytesPerSecond, 0);
  });
}
