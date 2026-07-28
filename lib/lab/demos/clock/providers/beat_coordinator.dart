import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'package:xiaodouzi_fr/services/metronome/metronome_service.dart';

/// Internal sink so tests can replace the FFI surface.
/// All methods delegate to the shared [MetronomeService] singleton —
/// no static `MetronomeFFI` calls in here, so the BeatCoordinator can't
/// accidentally talk to a stale stream after a controller disposal.
abstract class BeatSink {
  void setBpm(double bpm);
  void setBeatsPerBar(int n);
  void setBeatAccentLevel(int idx, int level); // 0=weak, 1=medium, 2=accent
  void play();
  void pause();
}

class _OboeBeatSink implements BeatSink {
  MetronomeService get _svc => MetronomeService.instance;

  @override
  void setBpm(double bpm) => _svc.setBpm(bpm);
  @override
  void setBeatsPerBar(int n) => _svc.setBeatsPerBar(n);
  @override
  void setBeatAccentLevel(int idx, int level) => _svc.setBeatAccentLevel(idx, level);
  @override
  void play() => _svc.play();
  @override
  void pause() => _svc.pause();
}

/// Single owner of the Oboe audio stream. Both `LabClockProvider` and
/// `LabTrackProvider` must call [requestOwnership] before issuing FFI commands
/// and [releaseOwnership] when their entity stops. If another provider steals
/// ownership, the previous owner's `beatenOutCallback` fires.
///
/// The service is shared across the app (single Oboe stream + sample slots).
/// Releasing ownership only pauses playback — it never closes the stream —
/// so the next caller (clock demo, metronome demo) gets a ready service.
class BeatCoordinator {
  static String? _ownerId;
  static ValueChanged<String>? _onBeatenOut;
  static BeatSink _sink = _OboeBeatSink();

  static String? get ownerId => _ownerId;

  /// Test-only: replace the FFI sink.
  static void setSinkForTest(BeatSink sink) => _sink = sink;

  /// Test-only: clear all coordinator state.
  static void resetForTest() {
    _ownerId = null;
    _onBeatenOut = null;
    _sink = _OboeBeatSink();
  }

  /// Request exclusive control of the metronome. Returns true if granted.
  /// If [bpm] / [beatPattern] are non-null, configures the audio stream
  /// before starting playback.
  static bool requestOwnership({
    required String providerId,
    int? bpm,
    String? beatPattern,
  }) {
    if (_ownerId != null && _ownerId != providerId) {
      final stolen = _ownerId!;
      _onBeatenOut?.call(stolen);
    }
    _ownerId = providerId;
    if (bpm != null) {
      _sink.setBpm(bpm.toDouble().clamp(20.0, 300.0));
    }
    if (beatPattern != null) {
      BeatPattern? pattern;
      for (final p in MetronomePresets.patterns) {
        if (p.name == beatPattern) {
          pattern = p;
          break;
        }
      }
      if (pattern != null) {
        _sink.setBeatsPerBar(pattern.beatsPerMeasure);
        for (var i = 0; i < pattern.beatsPerMeasure; i++) {
          final isAccent = pattern.accentIndices.contains(i);
          _sink.setBeatAccentLevel(i, isAccent ? 2 : 0);
        }
      }
    }
    _sink.play();
    return true;
  }

  /// Release ownership. No-op if [providerId] is not the current owner.
  static void releaseOwnership(String providerId) {
    if (_ownerId != providerId) return;
    _ownerId = null;
    _sink.pause();
  }

  /// Register a callback fired when this provider's ownership is stolen.
  static void registerBeatenOutCallback(ValueChanged<String> cb) {
    _onBeatenOut = cb;
  }
}