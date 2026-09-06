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
  }) : _volume = volume.clamp(0.0, lineSfxVolumeMax);

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
  AndroidLoudnessEnhancer? _tapBoost;
  AndroidLoudnessEnhancer? _slideBoost;
  AndroidLoudnessEnhancer? _holdBoost;
  bool _ready = false;

  bool get isReady => _ready;
  double get volume => _volume;

  static bool get _useAndroidBoost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    _volume = v.clamp(0.0, lineSfxVolumeMax);
    // 线性 0~1 直接对应播放器；>1 仅 Android 轻度增强，避免刺耳
    final playerVol = _volume.clamp(0.0, 1.0);
    final gainDb = (_volume - 1.0).clamp(0.0, 0.5) * 6.0; // 最多约 +3dB

    await Future.wait([
      _tap?.setVolume(playerVol) ?? Future.value(),
      _slide?.setVolume(playerVol) ?? Future.value(),
      _hold?.setVolume(playerVol) ?? Future.value(),
      _applyBoost(_tapBoost, gainDb),
      _applyBoost(_slideBoost, gainDb),
      _applyBoost(_holdBoost, gainDb),
    ]);
  }

  Future<void> _applyBoost(AndroidLoudnessEnhancer? boost, double gainDb) async {
    if (boost == null) return;
    await boost.setEnabled(gainDb > 0.01);
    await boost.setTargetGain(gainDb);
  }

  Future<(AudioPlayer, AndroidLoudnessEnhancer?)> _createPlayer() async {
    if (_useAndroidBoost) {
      final boost = AndroidLoudnessEnhancer();
      final player = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [boost]),
      );
      await boost.setEnabled(true);
      return (player, boost);
    }
    return (AudioPlayer(), null);
  }

  Future<void> _loadPlayers() async {
    if (_ready) return;
    try {
      final tapPair = await _createPlayer();
      final slidePair = await _createPlayer();
      final holdPair = await _createPlayer();
      _tap = tapPair.$1;
      _tapBoost = tapPair.$2;
      _slide = slidePair.$1;
      _slideBoost = slidePair.$2;
      _hold = holdPair.$1;
      _holdBoost = holdPair.$2;

      await Future.wait([
        _tap!.setAsset(tapAsset),
        _slide!.setAsset(slideAsset),
        _hold!.setAsset(holdAsset),
      ]);
      await setVolume(_volume);
      await Future.wait([
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
    _tapBoost = null;
    _slideBoost = null;
    _holdBoost = null;
  }
}
