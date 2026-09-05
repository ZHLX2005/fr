import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/note_event.dart';
import 'judge_service.dart';

/// 打击反馈（触感 + 按音符类型的 wav 音效）
class HitFeedback {
  HitFeedback({
    this.hapticsEnabled = true,
    this.sfxEnabled = true,
  });

  static const String tapAsset = 'assets/line/sfx/tap.wav';
  static const String slideAsset = 'assets/line/sfx/slide.wav';
  static const String holdAsset = 'assets/line/sfx/hold.wav';

  bool hapticsEnabled;
  bool sfxEnabled;

  AudioPlayer? _tap;
  AudioPlayer? _slide;
  AudioPlayer? _hold;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      _tap = AudioPlayer();
      _slide = AudioPlayer();
      _hold = AudioPlayer();
      await Future.wait([
        _tap!.setAsset(tapAsset),
        _slide!.setAsset(slideAsset),
        _hold!.setAsset(holdAsset),
      ]);
      _ready = true;
    } catch (_) {
      // 资源缺失 / 平台不支持时静默降级（仅触感）
      await dispose();
    }
  }

  void play({
    required JudgeResultLabel label,
    required NoteType noteType,
  }) {
    if (hapticsEnabled) {
      switch (label) {
        case JudgeResultLabel.perfect:
          HapticFeedback.mediumImpact();
        case JudgeResultLabel.great:
          HapticFeedback.lightImpact();
        case JudgeResultLabel.good:
          HapticFeedback.selectionClick();
        case JudgeResultLabel.miss:
          HapticFeedback.heavyImpact();
      }
    }
    if (!sfxEnabled || label == JudgeResultLabel.miss) return;
    _playSfx(noteType);
  }

  void playMiss() {
    if (hapticsEnabled) {
      HapticFeedback.vibrate();
    }
  }

  void _playSfx(NoteType type) {
    final player = switch (type) {
      NoteType.tap => _tap,
      NoteType.slide => _slide,
      NoteType.hold => _hold,
    };
    if (player == null) return;
    // 快速连击：从头重播，允许打断上一发同类型
    player.seek(Duration.zero).then((_) => player.play()).catchError((_) {});
  }

  Future<void> dispose() async {
    _ready = false;
    await Future.wait([
      _tap?.dispose() ?? Future.value(),
      _slide?.dispose() ?? Future.value(),
      _hold?.dispose() ?? Future.value(),
    ]);
    _tap = null;
    _slide = null;
    _hold = null;
  }
}
