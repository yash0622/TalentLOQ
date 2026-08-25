import 'package:flutter/foundation.dart';

/// Lightweight performance logger for tracking time-to-first-content per screen.
///
/// Usage:
/// ```dart
/// final timer = PerfLogger.start('OpportunitiesScreen');
/// // ... fetch data ...
/// timer.stop(); // logs: [PERF] OpportunitiesScreen loaded in 342ms
/// ```
class PerfLogger {
  final String screenName;
  final Stopwatch _stopwatch;
  bool _stopped = false;

  PerfLogger._(this.screenName) : _stopwatch = Stopwatch()..start();

  /// Start a performance timer for a screen.
  static PerfLogger start(String screenName) {
    debugPrint('[PERF] $screenName: timer started');
    return PerfLogger._(screenName);
  }

  /// Stop the timer and log the elapsed duration.
  Duration stop() {
    if (_stopped) return _stopwatch.elapsed;
    _stopped = true;
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsed;
    debugPrint('[PERF] $screenName: loaded in ${elapsed.inMilliseconds}ms');
    return elapsed;
  }

  /// Log an intermediate checkpoint without stopping the timer.
  void checkpoint(String label) {
    debugPrint('[PERF] $screenName/$label: ${_stopwatch.elapsedMilliseconds}ms');
  }
}
