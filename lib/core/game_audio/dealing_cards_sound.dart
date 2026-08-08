// lib/core/game_audio/dealing_cards_sound.dart
//
// 翻牌音效 — lab demo 卡牌游戏（Coup / team_card）共用单例。
//
// 六人 Coup 满员开局时，`on_action_START` 同帧为 6 个玩家各发 2 张牌，
// 服务端在一帧内把 12 个 `card1`/`card2` 从 null 置上 → 客户端在同帧
// 收到 12 个"翻牌"事件。沿用 `PieceSound` 的"单 AudioPlayer + seek+play"
// 模式会被 seek 抢断导致后 11 次吞掉。
//
// 设计：16 个 AudioPlayer 池，`play()` 取一个空闲或最早被占用的 player
// 加载 `dealingCards.mp3` 并 seek(0)+play。丢帧代价：忽略新调用。
//
// 资产：assets/audio/dealingCards.mp3（已在 pubspec 注册）。
// 依赖：just_audio（已在 pubspec）。
// 全局开关：static `_enabled`，默认 true；未来全局设置直接
// `DealingCardsSound.setEnabled(settings.soundOn)`。

import 'package:just_audio/just_audio.dart';

class DealingCardsSound {
  DealingCardsSound._();

  /// AudioPlayer 池大小。覆盖 6 人 Coup 满员（12 张同帧）的余量。
  static const int poolSize = 16;

  /// 资源路径。
  static const String _assetPath = 'assets/audio/dealingCards.mp3';

  /// 池内 player。
  final List<AudioPlayer> _pool =
      List<AudioPlayer>.generate(poolSize, (_) => AudioPlayer());

  /// 每个 player 是否空闲（"未在播放"语义：不在 playing；idle/completed/paused 都算空闲）。
  /// 真实使用时直接尝试 setAsset + seek+play；失败 catch 吞掉。
  static bool _enabled = true;

  /// 当前是否启用。
  static bool get enabled => _enabled;

  /// 设置静态开关。默认 true；全局设置面板未来通过这里统一静音。
  static void setEnabled(bool v) => _enabled = v;

  /// 翻牌音效 fire-and-forget 播放。
  /// 同帧多次调用会从池里依次取 player，互不抢断。
  /// 全部 catch 吞错，遵循 PieceSound 的健壮性。
  static Future<void> play() async {
    if (!_enabled) return;
    final self = instance;
    for (final p in self._pool) {
      try {
        await p.setAsset(_assetPath);
        await p.seek(Duration.zero);
        await p.play();
        return;
      } catch (_) {
        // 这个 player 加载失败或播放失败，下一个。
        continue;
      }
    }
    // 池里全部失败——吞掉，不影响对局。
  }

  /// 全局单例。
  static final DealingCardsSound instance = DealingCardsSound._();
}
