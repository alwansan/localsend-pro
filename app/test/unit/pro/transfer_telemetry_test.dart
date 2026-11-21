import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pro/transfer_telemetry.dart';
import 'package:localsend_app/pro/throughput_health.dart';

void main() {
  test('progress events feed a read-side monitor without resetting transfers', () {
    final meter = ProTransferTelemetry(autoTick: false);
    final start = DateTime(2026, 11, 21);
    meter.startFile(sessionId: 's', fileId: 'f', size: 10000000, at: start);
    expect(meter.healthForSession('s'), ProTransferHealth.warmup);

    meter.recordProgress(sessionId: 's', fileId: 'f', progress: 0.5);
    meter.sampleAll(start.add(const Duration(seconds: 1)));
    expect(meter.healthForSession('s'), ProTransferHealth.healthy);

    // No new progress events for more than 8 seconds.
    meter.sampleAll(start.add(const Duration(seconds: 9)));
    expect(meter.healthForSession('s'), ProTransferHealth.stalled);

    // Sender read progress resumes; no file manipulation occurred.
    meter.recordProgress(sessionId: 's', fileId: 'f', progress: 0.8);
    meter.sampleAll(start.add(const Duration(seconds: 10)));
    expect(meter.healthForSession('s'), ProTransferHealth.healthy);

    meter.finishFile(sessionId: 's', fileId: 'f');
    expect(meter.healthForSession('s'), isNull);
    meter.dispose();
  });

  test('sessions remain isolated, cancellation clears state and ignores late callbacks', () {
    final meter = ProTransferTelemetry(autoTick: false);
    final start = DateTime(2026, 11, 21);
    meter.startFile(sessionId: 'a', fileId: 'file', size: 100, at: start);
    meter.startFile(sessionId: 'b', fileId: 'file', size: 100, at: start);
    meter.recordProgress(sessionId: 'b', fileId: 'file', progress: 1);
    meter.sampleAll(start.add(const Duration(seconds: 1)));
    expect(meter.healthForSession('b'), ProTransferHealth.healthy);
    meter.finishSession('a');
    meter.recordProgress(sessionId: 'a', fileId: 'file', progress: 1);
    meter.sampleAll(start.add(const Duration(seconds: 10)));
    expect(meter.healthForSession('a'), isNull);
    expect(meter.healthForSession('b'), ProTransferHealth.stalled);
    meter.reset();
    expect(meter.healthForSession('b'), isNull);
    meter.dispose();
  });

  test('invalid and regressing progress never corrupt telemetry state', () {
    final meter = ProTransferTelemetry(autoTick: false);
    final start = DateTime(2026, 11, 21);
    meter.startFile(sessionId: 's', fileId: 'f', size: 10000, at: start);
    meter.recordProgress(sessionId: 's', fileId: 'f', progress: 0.9);
    meter.recordProgress(sessionId: 's', fileId: 'f', progress: double.nan);
    meter.recordProgress(sessionId: 's', fileId: 'f', progress: 0.2);
    meter.sampleAll(start.add(const Duration(seconds: 1)));
    expect(meter.healthForSession('s'), ProTransferHealth.healthy);
    meter.finishSession('s');
    meter.dispose();
  });
}
