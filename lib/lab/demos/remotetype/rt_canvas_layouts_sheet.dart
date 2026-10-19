// lib/lab/demos/remotetype/rt_canvas_layouts_sheet.dart
//
// 画布布局选择 sheet：当前激活的条目打勾，点按切换；自定义可长按删除；
// 底部「复制当前为新自定义」创建副本并由画布页立即切到它。
//
// 画布 view 在 _openLayoutsSheet 里 showModalBottomSheet 调用本件；本件
// 只负责「展示 + 收集意图」，持久化与状态切换由页面的回调接管。

import 'package:flutter/material.dart';

import 'rt_canvas_presets.dart' show kRtCanvasBuiltinPresets;
import 'rt_prefs.dart' show RtCanvasLayouts, RtCanvasNamedLayout;

class RtCanvasLayoutsSheet extends StatelessWidget {
  const RtCanvasLayoutsSheet({
    super.key,
    required this.layouts,
    required this.activeId,
    required this.onSwitch,
    required this.onCopy,
    required this.onDelete,
  });

  final RtCanvasLayouts layouts;
  final String activeId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onCopy;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 内置 + 自定义（已分组）；内置按 kRtCanvasBuiltinPresets 顺序展示。
    final builtIns = kRtCanvasBuiltinPresets;
    final customs = layouts.list
        .where((p) => !p.builtIn)
        .toList(growable: false);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Text(
                      '画布布局',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '当前：${_nameOf(layouts, activeId) ?? '—'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final p in builtIns)
                      _LayoutTile(
                        entry: p,
                        isActive: p.id == activeId,
                        onTap: () => onSwitch(p.id),
                        onLongPress: null,
                      ),
                    if (customs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Text(
                          '自定义',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final p in customs)
                        _LayoutTile(
                          entry: p,
                          isActive: p.id == activeId,
                          onTap: () => onSwitch(p.id),
                          onLongPress: () => _confirmDelete(context, p),
                        ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('复制当前为新自定义'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String? _nameOf(RtCanvasLayouts layouts, String id) {
    for (final p in layouts.list) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  Future<void> _confirmDelete(BuildContext context, RtCanvasNamedLayout p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除自定义布局？'),
        content: Text('「${p.name}」将被删除，当前激活布局保持不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(p.id);
  }
}

class _LayoutTile extends StatelessWidget {
  const _LayoutTile({
    required this.entry,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  final RtCanvasNamedLayout entry;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (entry.builtIn)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '内置',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else
              Icon(
                Icons.more_horiz,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
