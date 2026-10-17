// lib/core/game_audio/piece_sound.dart
//
// 落子/吃子音效 — 棋游共用单例。
// 五子棋 / 黑白翻转棋 / 围追堵截（本地+联机）/ 斗兽棋 在落子时调用 [PieceSound.instance.play]；
// 国际跳棋吃子链走子时调用 [PieceSound.instance.playCapture]（capture.wav）。
//
// 单例 + 预加载：AudioPlayer 全局复用，落子密集时零加载延迟、可快速重播。
// 依赖 just_audio（已在 pubspec），asset = assets/audio/piece.mp3 / capture.wav。
//
// 设计要点：
//   - 单 AudioPlayer 承载双音源（piece.mp3 / capture.wav）：setAsset 是替换
//     唯一音源，切换音色必须重新加载 —— [_ensureAsset] 按 _loadedAsset 判定，
//     同源走零加载直响，换源自旋等待后重载（并发共享同一加载过程）。
//   - play 用 seek(0)+play：无论 player 当前是 idle / playing / completed，都能可靠重播。
//   - 全部 catch 吞错：音频加载/播放失败绝不影响对局主流程。

import 'package:just_audio/just_audio.dart';

class PieceSound {
  PieceSound._();
  static final PieceSound instance = PieceSound._();

  static const String _assetPath = 'assets/audio/piece.mp3';
  static const String _captureAssetPath = 'assets/audio/capture.wav';

  final AudioPlayer _player = AudioPlayer();

  /// 播放器当前已加载的音源。just_audio 的 setAsset 是**替换唯一音源**，
  /// 落子/吃子共用一个 player 时，切换音色必须重新 setAsset —— 只靠
  /// 「每种音效一个缓存 Future」会在第一次换源后永久串音（capture.wav
  /// 顶掉 piece.mp3，且再也切不回来）。
  String? _loadedAsset;

  /// 进行中的加载（并发调用共享同一过程，避免重复 setAsset）。
  Future<void>? _loading;

  /// 预加载落子音。可在进入棋盘页 initState / ViewModel 构造时调用以消除
  /// 首次落子的加载延迟；不调用也无妨——首次 [play] 会兜底加载。
  Future<void> preload() => _ensureAsset(_assetPath);

  Future<void> _ensureAsset(String path) async {
    // 自旋等待：并发请求不同音源时，后到者等 in-flight 完成后重查，
    // 必要时自己再加载 —— 返回时播放器音源就是 [path]（加载失败除外）。
    while (_loadedAsset != path) {
      final inFlight = _loading;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      final op = () async {
        try {
          await _player.setAsset(path);
          _loadedAsset = path;
        } catch (_) {
          // 加载失败不阻塞对局：保持 _loadedAsset 不变，下次调用重试。
        }
      }();
      _loading = op;
      try {
        await op;
      } finally {
        _loading = null;
      }
      return; // 只尝试一次；失败留给下次调用重试。
    }
  }

  /// 播放一次落子音。fire-and-forget，调用方无需 await。
  Future<void> play() => _playAsset(_assetPath);

  /// 播放一次吃子音。fire-and-forget，调用方无需 await。
  Future<void> playCapture() => _playAsset(_captureAssetPath);

  Future<void> _playAsset(String path) async {
    await _ensureAsset(path);
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // 播放失败不影响对局。
    }
  }
}
