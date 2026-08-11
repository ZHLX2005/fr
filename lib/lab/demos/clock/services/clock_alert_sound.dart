// lib/lab/demos/clock/services/clock_alert_sound.dart
//
// clock 预设归零提醒音 —— just_audio 一次性音效单例（fr #3，方案 A）。
// 仿 PieceSound：单例 + 懒加载缓存就绪 Future + seek(0)+play 可快速重播。
// asset = assets/audio/woodfish.wav（clock 主题音，零新增资产；后续可换专属提示音）。

import 'package:just_audio/just_audio.dart';

class ClockAlertSound {
  ClockAlertSound._();
  static final ClockAlertSound instance = ClockAlertSound._();

  static const String _assetPath = 'assets/audio/woodfish.wav';

  final AudioPlayer _player = AudioPlayer();
  // 缓存的「就绪 Future」。null 表示尚未加载或上次加载失败（下次重试）。
  Future<void>? _ready;

  /// 可在 ClockDemo 打开时调用以消除首次归零的加载延迟；不调用也无妨。
  Future<void> preload() => _ensureReady();

  Future<void> _ensureReady() {
    return _ready ??= () async {
      try {
        await _player.setAsset(_assetPath);
      } catch (_) {
        _ready = null;
      }
    }();
  }

  /// 播放一次归零提醒音。fire-and-forget，调用方无需 await。
  Future<void> play() async {
    await _ensureReady();
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // 播放失败不影响倒计时主流程。
    }
  }
}