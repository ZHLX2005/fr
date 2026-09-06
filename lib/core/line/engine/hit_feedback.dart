import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/constants.dart';
import '../domain/note_event.dart';
import 'judge_service.dart';

/// 打击反馈（触感 + 按音符类型的 mp3 音效）
///
/// 进局前必须 [ensureLoaded] 完成（选曲「开始」流程里 await），
/// 对局内复用同一批 [AudioPlayer]，避免首击才解码导致无声/卡顿。
class HitFeedback {
  HitFeedback({
    this.hapticsEnabled = true,
    this.sfxEnabled = true,
    double volume = lineDefaultSfxVolume,
  }) : _volume = volume.clamp(0.0, 1.0);

  static const String tapAsset = 'assets/line/sfx/tap.mp3';
  static const String slideAsset = 'assets/line/sfx/slide.mp3';
  static const String holdAsset = 'assets/line/sfx/hold.mp3';

  /// 会话级单例：选曲预加载后对局复用。
  static HitFeedback? _session;
  static Future<HitFeedback>? _loading;

  bool hapticsEnabled;
  bool sfxEnabled;
  double _volume;

  AudioPlayer? _tap;
  AudioPlayer? _slide;
  AudioPlayer? _hold;
  bool _ready = false;

  bool get isReady => _ready;
  double get volume => _volume;

  /// 进游戏前调用：加载并解码三路音效；已就绪则直接返回。
  static Future<HitFeedback> ensureLoaded({
    bool hapticsEnabled = true,
    bool sfxEnabled = true,
    double volume = lineDefaultSfxVolume,
    bool strict = true,
  }) async {
    final existing = _session;
    if (existing != null && existing._ready) {
      existing.hapticsEnabled = hapticsEnabled;
      existing.sfxEnabled = sfxEnabled;
      await existing.setVolume(volume);
      return existing;
    }

    _loading ??= () async {
      final fb = HitFeedback();
      await fb._loadPlayers();
      if (!fb._ready) {
        await fb.dispose();
        throw StateError('line sfx assets failed to load');
      }
      _session = fb;
      return fb;
    }();

    try {
      final fb = await _loading!;
      fb.hapticsEnabled = hapticsEnabled;
      fb.sfxEnabled = sfxEnabled;
      await fb.setVolume(volume);
      return fb;
    } catch (e, st) {
      _loading = null;
      _session = null;
      if (strict) {
        Error.throwWithStackTrace(e, st);
      }
      debugPrint('HitFeedback.ensureLoaded failed: $e');
      return HitFeedback(hapticsEnabled: hapticsEnabled, sfxEnabled: false);
    }
  }

  /// 离开「线」模块时释放会话音效。
  static Future<void> releaseSession() async {
    _loading = null;
    final s = _session;
    _session = null;
    await s?.dispose();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await Future.wait([
      _tap?.setVolume(_volume) ?? Future.value(),
      _slide?.setVolume(_volume) ?? Future.value(),
      _hold?.setVolume(_volume) ?? Future.value(),
    ]);
  }

  Future<void> _loadPlayers() async {
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
      await Future.wait([
        _tap!.setVolume(_volume),
        _slide!.setVolume(_volume),
        _hold!.setVolume(_volume),
        _tap!.seek(Duration.zero),
        _slide!.seek(Duration.zero),
        _hold!.seek(Duration.zero),
      ]);
      _ready = true;
    } catch (e, st) {
      debugPrint('HitFeedback._loadPlayers failed: $e\n$st');
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
    if (!sfxEnabled || !_ready || label == JudgeResultLabel.miss) return;
    if (_volume <= 0.001) return;
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
