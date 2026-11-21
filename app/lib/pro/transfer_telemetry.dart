import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/pro/throughput_health.dart';

/// Diagnostics derived from Rust upload progress (bytes read by the sender).
///
/// A successfully read byte is NOT a remotely persisted or verified byte.
/// This service must never cancel an upload, switch its network or resume a
/// partial file. Only the future receiver-acknowledged resume protocol may do
/// any of those things.
class ProTransferTelemetry extends ChangeNotifier {
  final bool autoTick;
  final _active = <(String, String), _ProUploadSample>{};
  Timer? _timer;

  ProTransferTelemetry({this.autoTick = true});

  void startFile({required String sessionId, required String fileId, required int size, DateTime? at}) {
    final key = (sessionId, fileId);
    final sample = _ProUploadSample(size: size < 0 ? 0 : size);
    sample.monitor.observe(at ?? DateTime.now(), 0);
    _active[key] = sample;
    if (autoTick) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => sampleAll(DateTime.now()));
    }
    notifyListeners();
  }

  /// Called by the existing send event handler. Store progress only;
  /// sampling in a one-second timer avoids hundreds of UI updates per second.
  void recordProgress({required String sessionId, required String fileId, required double progress}) {
    final item = _active[(sessionId, fileId)];
    if (item == null || !progress.isFinite) return;
    final bytes = (progress.clamp(0.0, 1.0) * item.size).round();
    if (bytes >= item.readBytes) item.readBytes = bytes;
  }

  /// Periodic observation also detects stalls when no Rust events arrive.
  /// Public for deterministic, no-timer unit tests.
  void sampleAll(DateTime at) {
    var changed = false;
    for (final item in _active.values) {
      final health = item.monitor.observe(at, item.readBytes);
      if (health != item.health) {
        item.health = health;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  ProTransferHealth? healthForSession(String sessionId) {
    final states = [
      for (final entry in _active.entries)
        if (entry.key.$1 == sessionId) entry.value.health,
    ];
    if (states.isEmpty) return null;
    if (states.contains(ProTransferHealth.stalled)) return ProTransferHealth.stalled;
    if (states.contains(ProTransferHealth.degraded)) return ProTransferHealth.degraded;
    if (states.contains(ProTransferHealth.healthy)) return ProTransferHealth.healthy;
    return ProTransferHealth.warmup;
  }

  void finishFile({required String sessionId, required String fileId}) {
    if (_active.remove((sessionId, fileId)) != null) {
      _stopTimerWhenIdle();
      notifyListeners();
    }
  }

  void finishSession(String sessionId) {
    final oldCount = _active.length;
    _active.removeWhere((key, _) => key.$1 == sessionId);
    _stopTimerWhenIdle();
    if (oldCount != _active.length) notifyListeners();
  }

  void reset() {
    if (_active.isNotEmpty) {
      _active.clear();
      notifyListeners();
    }
    _stopTimerWhenIdle();
  }

  void _stopTimerWhenIdle() {
    if (_active.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

class _ProUploadSample {
  final int size;
  int readBytes = 0;
  ProTransferHealth health = ProTransferHealth.warmup;
  final ProThroughputHealthMonitor monitor = ProThroughputHealthMonitor();

  _ProUploadSample({required this.size});
}

/// In-memory observer; never writes file paths, content or credentials.
final proTransferTelemetry = ProTransferTelemetry();
