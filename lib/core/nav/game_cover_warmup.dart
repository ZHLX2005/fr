// 游戏封面预热：不依赖打开游戏中心，启动后即可在设置 / 导航缩略图读到 KV 封面。

import 'dart:async' show unawaited;

import '../game_kit/skin/game_center_skin_spec.dart';

/// 先恢复本地落盘索引，再 best-effort 拉线上。失败静默。
Future<void> warmUpGameCenterCovers() async {
  await gameCenterSkinBundle.restorePersistedIndex().catchError(
    (Object _) => false,
  );
  await fetchAndMergeGameCenterSkins().catchError((Object _) => false);
}

/// fire-and-forget 包装，供 main 调用。
void scheduleGameCenterCoverWarmUp() {
  unawaited(warmUpGameCenterCovers());
}
