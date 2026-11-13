import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../api/mnws/nxnx/nxnx_models.dart';

/// CLI 等价提示：列出当前模块的全部同构命令。
///
/// ## 为什么由数据派生而不是手写
///
/// 这行提示是用户核对「面板上这个按钮到底有没有 CLI 等价」的唯一依据。
/// 手写的话，命令一改提示就悄悄过期 —— 提示说「有」、实际没有，
/// 比没有提示更糟。所以它来自 **bootstrap 下发的命令表**，与 CLI 实际注册的
/// 命令同源。
class NxNxCliHints extends StatelessWidget {
  /// 模块名（`template` / `script` / `system` / `skill`）。
  final String module;

  /// 命令表（bootstrap 的 `commands[]`）。
  final List<NxNxCommand> commands;

  const NxNxCliHints({
    super.key,
    required this.module,
    required this.commands,
  });

  @override
  Widget build(BuildContext context) {
    final cmds = commands.where((c) => c.module == module).toList();
    if (cmds.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这个页面上的每个按钮都有一条同构的 CLI 命令',
            style: TextStyle(fontSize: 10, color: cs.outline),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: cmds
                .map((c) => InkWell(
                      onTap: () => _copy(context, c.command),
                      borderRadius: BorderRadius.circular(4),
                      child: Tooltip(
                        message: c.usage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            c.command,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          Text(
            '（点一下复制）。加 --json 得机器可读输出。',
            style: TextStyle(fontSize: 10, color: cs.outline),
          ),
        ],
      ),
    );
  }

  static void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 $text')),
    );
  }
}
