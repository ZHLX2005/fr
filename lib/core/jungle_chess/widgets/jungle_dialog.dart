// lib/core/jungle_chess/widgets/jungle_dialog.dart
import 'package:flutter/material.dart';

// 终局提示不再用单向弹窗：面对面热座时上方玩家读不了。改成页面内的双向覆盖层，
// 见 local/local_game_page.dart 的 _VictoryOverlay。

/// 退出确认弹窗
Future<bool> showJungleExitConfirmDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出游戏'),
      content: const Text('确定要退出当前对局吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ),
  );
  return result ?? false;
}
