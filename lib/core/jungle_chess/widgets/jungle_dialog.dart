// lib/core/jungle_chess/widgets/jungle_dialog.dart
import 'package:flutter/material.dart';

/// 胜负弹窗
void showJungleGameOverDialog(BuildContext context, String winnerText, String reason, {VoidCallback? onRestart, VoidCallback? onExit}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('游戏结束'),
      content: Text('$winnerText 获胜！\n原因：$reason'),
      actions: [
        if (onRestart != null) TextButton(onPressed: () { Navigator.pop(ctx); onRestart(); }, child: const Text('再来一局')),
        if (onExit != null) TextButton(onPressed: () { Navigator.pop(ctx); onExit(); }, child: const Text('退出')),
      ],
    ),
  );
}

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
