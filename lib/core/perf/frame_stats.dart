import 'package:flutter/scheduler.dart';

/// Frame timing for tuning (build with --dart-define=LUMINA_PERF=true): every
/// two seconds with frames, one logcat line with UI-thread build and
/// raster-thread times (p50 / p90 / max, ms) and how many frames missed the
/// display's budget. Off in normal builds.
abstract final class FrameStats {
  static const enabled = bool.fromEnvironment('LUMINA_PERF');

  static final _build = <double>[];
  static final _raster = <double>[];
  static var _missed = 0;
  static DateTime _since = DateTime.now();

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      _build.add(b);
      _raster.add(r);
      // A 120 Hz panel gives 8.3 ms; count anything over a 60 Hz frame too.
      if (b > 16.7 || r > 16.7) _missed++;
    }
    if (DateTime.now().difference(_since).inMilliseconds < 2000 || _build.isEmpty) return;
    String q(List<double> v) {
      v.sort();
      double at(double p) => v[((v.length - 1) * p).round()];
      return '${at(0.5).toStringAsFixed(1)}/${at(0.9).toStringAsFixed(1)}/${v.last.toStringAsFixed(1)}';
    }

    // ignore: avoid_print
    print('LUMINA_PERF frames=${_build.length} build=${q(_build)} raster=${q(_raster)} missed=$_missed');
    _build.clear();
    _raster.clear();
    _missed = 0;
    _since = DateTime.now();
  }
}
