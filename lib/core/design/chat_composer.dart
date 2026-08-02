import 'package:flutter/material.dart';

import 'slate_palette.dart';

/// 输入区工具栏按钮项
class ComposerTool {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const ComposerTool({required this.icon, required this.label, this.onTap});
}

/// Slate 设计系统 —— 聊天输入区
///
/// 无边框设计：输入框用浅表面填充（无描边），发送按钮靛蓝圆形。
/// 可选顶部工具栏（语音/图片/文件/表情等）。
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintText;
  final bool isSending;
  final List<ComposerTool>? tools;
  final void Function(String)? onSubmitted;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.hintText = '输入消息…',
    this.isSending = false,
    this.tools,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 工具栏（语音/图片/文件/表情）
            if (tools != null && tools!.isNotEmpty)
              Container(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(SlatePalette.radius),
                  ),
                ),
                child: Row(
                  children: [
                    for (final tool in tools!) _ToolButton(tool: tool),
                  ],
                ),
              ),
            // 输入行
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: onSubmitted ?? (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: hintText,
                        filled: true,
                        fillColor: isDark
                            ? SlatePalette.darkSurfaceTint
                            : SlatePalette.lightSurfaceTint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark
                            ? SlatePalette.darkTextPrimary
                            : SlatePalette.lightTextPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送按钮：靛蓝圆形
                  GestureDetector(
                    onTap: isSending ? null : onSend,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: isSending
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.arrow_upward,
                              size: 20,
                              color: scheme.onPrimary,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final ComposerTool tool;

  const _ToolButton({required this.tool});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: tool.onTap,
        borderRadius: BorderRadius.circular(SlatePalette.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tool.icon, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                tool.label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
