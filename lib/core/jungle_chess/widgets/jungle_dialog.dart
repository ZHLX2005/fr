// lib/core/jungle_chess/widgets/jungle_dialog.dart
import 'package:flutter/material.dart';

import '../../ui/global/dialog/main.dart';

// 终局提示不再用单向弹窗：面对面热座时上方玩家读不了。改成页面内的双向覆盖层，
// 见 local/local_game_page.dart 的 _VictoryOverlay。

/// 退出确认弹窗
Future<bool> showJungleExitConfirmDialog(BuildContext context) {
  // bool 合同保留给调用方（onConfirm 动作由调用方在拿到 true 后执行）。
  return BaseConfirmDialog.show(
    context: context,
    title: '退出游戏',
    message: '确定要退出当前对局吗？',
    confirmLabel: '确定',
    onConfirm: () {},
  );
}
