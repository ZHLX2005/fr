import 'package:flutter/material.dart';

import '../../../../design_tokens/spacing.dart';
import '../mnws_blocks.dart';

/// nx-kv 界面里的状态徽标：**颜色只表达状态，不做底色块**。
///
/// 沿用 mn-ws 那套口径（`mnws_blocks.dart`：无色块、只用浅描边），
/// 状态用描边 + 文字色区分，页面才不会糊成一片。
class NxKvStatusTag extends StatelessWidget {
  const NxKvStatusTag(this.status, {super.key});

  final String status;

  static const Map<String, String> _labels = {
    'pending': '待领取',
    'claimed': '进行中',
    'done': '已完成',
    'cancelled': '已取消',
  };

  static const Map<String, String> _alias = {
    'ok': '成功',
    'timeout': '没活',
    'blocked': '被挡住',
  };

  Color _color(ColorScheme cs) => switch (status) {
        'pending' => cs.primary,
        'claimed' => cs.tertiary,
        'done' => cs.outline,
        'cancelled' => cs.error,
        'blocked' => cs.error,
        'timeout' => cs.outline,
        _ => cs.outline,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = _labels[status] ?? _alias[status] ?? status;
    final c = _color(cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: c)),
    );
  }
}

/// 空态 / 错误态：一行说明 + 一个动作，不占整屏。
class NxKvNotice extends StatelessWidget {
  const NxKvNotice({
    super.key,
    required this.text,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final String text;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = isError ? cs.error : cs.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isError ? Icons.error_outline : Icons.inbox_outlined, size: 22, color: c),
          const SizedBox(height: AppSpacing.xs),
          Text(text, style: TextStyle(fontSize: 13, color: c), textAlign: TextAlign.center),
          if (detail != null && detail!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail!,
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// 一行「键 · 值」，详情页的元信息用。
class NxKvMetaRow extends StatelessWidget {
  const NxKvMetaRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// 带标题的分组块（描边，不填色）。
class NxKvSection extends StatelessWidget {
  const NxKvSection({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MnWsBlock(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(AppSpacing.sm), child: child),
        ],
      ),
    );
  }
}
