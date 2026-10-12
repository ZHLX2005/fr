// lib/lab/demos/remotetype/rt_connecting_overlay.dart
//
// 连接中遮罩（纯展示）：盖在配对页/输入页上，AbsorbPointer 挡输入，
// 显示目标电脑名。目标名的解析（computers/selectedClient → label）在 rt_page。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';

/// 连接中遮罩。
class RtConnectingOverlay extends StatelessWidget {
  const RtConnectingOverlay({super.key, required this.label});

  /// 目标电脑显示名（解析失败时是 clientId，未知时是「电脑」）。
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return AbsorbPointer(
      child: ColoredBox(
        color: c.text.withValues(alpha: 0.28),
        child: Center(
          child: Material(
            color: c.surface,
            elevation: 8,
            shadowColor: cs.shadow.withValues(alpha: 0.18),
            surfaceTintColor: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '正在连接',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
