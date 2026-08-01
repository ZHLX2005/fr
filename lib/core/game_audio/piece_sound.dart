// lib/core/game_audio/piece_sound.dart
//
// 落子音效 — 棋游共用单例。
// 五子棋 / 黑白翻转棋 / 围追堵截（本地+联机）/ 斗兽棋 在落子时调用 [PieceSound.instance.play]。
//
// 单例 + 预加载：AudioPlayer 全局复用，落子密集时零加载延迟、可快速重播。
// 依赖 just_audio（已在 pubspec），asset = assets/audio/piece.mp3。
//
// 设计要点：
//   - 懒加载 + 缓存 Future：首次 play 前加载，并发调用共享同一加载过程，不重复 setAsset。
//   - play 用 seek(0)+play：无论 player 当前是 idle / playing / completed，都能可靠重播。
//   - 全部 catch 吞错：音频加载/播放失败绝不影响对局主流程。

import 'package:just_audio/just_audio.dart';

class PieceSound {
  PieceSound._();
  static final PieceSound instance = PieceSound._();

  static const String _assetPath = 'assets/audio/piece.mp3';

  final AudioPlayer _player = AudioPlayer();
  // 缓存的「就绪 Future」。null 表示尚未加载或上次加载失败（下次重试）。
  Future<void>? _ready;

  /// 预加载 piece.mp3。
  /// 可在进入棋盘页 initState / ViewModel 构造时调用以消除首次落子的加载延迟；
  /// 不调用也无妨——首次 [play] 会兜底加载。
  Future<void> preload() => _ensureReady();

  Future<void> _ensureReady() {
    return _ready ??= () async {
      try {
        await _player.setAsset(_assetPath);
      } catch (_) {
        // 加载失败不阻塞对局：置空以便下次 play 重试。
        _ready = null;
      }
    }();
  }

  /// 播放一次落子音。fire-and-forget，调用方无需 await。
  Future<void> play() async {
    await _ensureReady();
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // 播放失败不影响对局。
    }
  }
}
