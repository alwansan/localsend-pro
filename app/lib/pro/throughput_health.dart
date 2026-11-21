/// Lightweight byte-progress monitor. It NEVER restarts or truncates a transfer.
///
/// A future recovery controller may use these signals to run non-destructive
/// network probes. Resumption itself requires a separately agreed server offset.
enum ProTransferHealth { warmup, healthy, degraded, stalled }

class ProThroughputHealthMonitor {
  final Duration stallAfter;
  final double lowRateFraction;
  final int lowSamplesRequired;

  ProThroughputHealthMonitor({
    this.stallAfter = const Duration(seconds: 8),
    this.lowRateFraction = 0.15,
    this.lowSamplesRequired = 3,
  }) : assert(lowRateFraction > 0 && lowRateFraction < 1),
       assert(lowSamplesRequired >= 1);

  DateTime? _lastSample;
  DateTime? _lastProgress;
  int? _lastBytes;
  double _referenceBytesPerSecond = 0;
  int _lowSamples = 0;

  double get referenceBytesPerSecond => _referenceBytesPerSecond;

  ProTransferHealth observe(DateTime at, int completedBytes) {
    if (_lastSample == null || _lastBytes == null || completedBytes < _lastBytes!) {
      reset();
      _lastSample = at;
      _lastProgress = at;
      _lastBytes = completedBytes;
      return ProTransferHealth.warmup;
    }

    final elapsedMicros = at.difference(_lastSample!).inMicroseconds;
    if (elapsedMicros <= 0) return ProTransferHealth.warmup;

    final delta = completedBytes - _lastBytes!;
    _lastSample = at;
    _lastBytes = completedBytes;

    if (delta <= 0) {
      if (at.difference(_lastProgress!) >= stallAfter) {
        return ProTransferHealth.stalled;
      }
      return ProTransferHealth.healthy;
    }

    _lastProgress = at;
    final bytesPerSecond = delta * Duration.microsecondsPerSecond / elapsedMicros;

    // Preserve an established reference while allowing it to slowly decay.
    final referenceBefore = _referenceBytesPerSecond;
    if (referenceBefore > 0 && bytesPerSecond < referenceBefore * lowRateFraction) {
      _lowSamples++;
    } else {
      _lowSamples = 0;
    }
    _referenceBytesPerSecond = bytesPerSecond > referenceBefore * 0.985 ? bytesPerSecond : referenceBefore * 0.985;

    if (_lowSamples >= lowSamplesRequired) return ProTransferHealth.degraded;
    return ProTransferHealth.healthy;
  }

  void reset() {
    _lastSample = null;
    _lastProgress = null;
    _lastBytes = null;
    _referenceBytesPerSecond = 0;
    _lowSamples = 0;
  }
}
