// lib/core/remotetype/settings/rt_layout_dialogs.dart
//
// 布局管理的三个对话框：恢复出厂 / 改名 / 删除。
//
// 独立成文件——它们与卡片布局无关，只被 ⋯ 菜单调用。

import 'package:flutter/material.dart';

import '../../ui/atomic/base_dialog.dart';
import '../data/rt_prefs.dart' show RtCanvasNamedLayout;

/// 恢复出厂确认（内置）。返回 true = 用户确认。
Future<bool> confirmResetBuiltin(
  BuildContext context,
  RtCanvasNamedLayout p,
) {
  // bool 合同保留给调用方（动作由调用方在拿到 true 后执行）。
  return BaseConfirmDialog.show(
    context: context,
    title: '恢复「${p.name}」出厂摆放？',
    message: '此布局的摆放修改将被还原，其他布局不受影响。',
    confirmLabel: '恢复',
    onConfirm: () {},
  );
}

/// 改名输入（自定义）。返回 null = 取消。
Future<String?> promptRenameLayout(
  BuildContext context,
  RtCanvasNamedLayout p,
) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RenameDialog(initialName: p.name),
  );
}

/// 删除自定义确认。返回 true = 用户确认。
Future<bool> confirmDeleteCustom(
  BuildContext context,
  RtCanvasNamedLayout p,
) {
  // bool 合同保留给调用方（动作由调用方在拿到 true 后执行）。
  return BaseConfirmDialog.show(
    context: context,
    title: '删除自定义布局？',
    message: '「${p.name}」将被删除；若它正在某朝向使用，该朝向回落默认布局。',
    confirmLabel: '删除',
    onConfirm: () {},
  );
}

/// 改名对话框自持 controller：退场动画期间 TextField 仍在树上，
/// 提前 dispose 会抛「controller used after being disposed」。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名布局'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 16,
        decoration: const InputDecoration(labelText: '布局名'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
