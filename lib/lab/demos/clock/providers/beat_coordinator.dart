import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/ffi_bindings.dart';

/// Internal sink so tests can replace the FFI surface.
abstract class BeatSink {
  void setBpm(double bpm);
  void setBeatsPerBar(int n);
  void setBeatAccentLevel(int idx, int level); // 0=weak, 1=medium, 2=accent
  void play();
  void pause();
}

class _OboeBeatSink implements BeatSink {
  @override
  void setBpm(double bpm) => MetronomeFFI.setBpm(bpm);
  @override
  void setBeatsPerBar(int n) => MetronomeFFI.setBeatsPerBar(n);
  @override
  void setBeatAccentLevel(int idx, int level) => MetronomeFFI.setBeatAccentLevel(idx, level);
  @override
  void play() => MetronomeFFI.play();
  @override
  void pause() => MetronomeFFI.pause();
}

/// Single owner of the Oboe audio stream. Both `LabClockProvider` and
/// `LabTrackProvider` must call [requestOwnership] before issuing FFI commands
/// and [releaseOwnership] when their entity stops. If another provider steals
/// ownership, the previous owner's `beatenOutCallback` fires.
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