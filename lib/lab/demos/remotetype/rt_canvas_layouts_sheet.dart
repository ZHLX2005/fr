// lib/lab/demos/remotetype/rt_canvas_layouts_sheet.dart
//
// 画布布局选择 sheet：内置 + 自定义两组，均渲染**持久化版本**（用户改过的
// 内置布局在列表里就是改过的样子，与画布实际渲染同源——配置隔离的展示面）。
//   · 点按切换；每条带 16:9 迷你画布缩略图（模块矩形 + 按钮点）。
//   · 内置长按 → 「恢复出厂摆放」（改坏的内置布局可一键还原，不影响其他布局）。
//   · 自定义长按 → 重命名 / 删除（删除有确认）。
//   · 底部「复制当前为新自定义」创建副本并由画布页立即切到它。
//
// 画布 view 在 _openLayoutsSheet 里 showModalBottomSheet 调用本件；本件
// 只负责「展示 + 收集意图」，持久化与状态切换由页面的回调接管。

import 'package:flutter/material.dart';

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleInput,
        kRtCanvasModuleTouchpad,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW;

class RtCanvasLayoutsSheet extends StatelessWidget {
  const RtCanvasLayoutsSheet({
    super.key,
    required this.layouts,
    required this.activeId,
    required this.onSwitch,
    required this.onCopy,
    required this.onDelete,
    required this.onRename,
    required this.onResetBuiltin,
  });

  final RtCanvasLayouts layouts;
  final String activeId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onCopy;
  final ValueChanged<String> onDelete;

  /// 重命名自定义布局（id + 新名字，已 trim 非空）。
  final void Function(String id, String name) onRename;

  /// 把内置布局恢复出厂摆放（数据重置为代码预设，其它布局不动）。
  final ValueChanged<String> onResetBuiltin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 内置 + 自定义（已分组）。内置必须来自 layouts.list（持久化版本）
    // ——列表若直接渲染代码常量，用户改过的内置布局在 sheet 里就"失真"了。
    final builtIns =
        layouts.list.where((p) => p.builtIn).toList(growable: false);
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
                        onLongPress: () => _confirmReset(context, p),
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
                          onLongPress: () => _customActions(context, p),
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

  // ---- 内置：长按恢复出厂 ----

  Future<void> _confirmReset(BuildContext context, RtCanvasNamedLayout p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('恢复「${p.name}」出厂摆放？'),
        content: const Text('此布局的摆放修改将被还原，其他布局不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok == true) onResetBuiltin(p.id);
  }

  // ---- 自定义：长按 → 重命名 / 删除 ----

  Future<void> _customActions(BuildContext context, RtCanvasNamedLayout p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (context.mounted && action == 'rename') {
      await _promptRename(context, p);
    } else if (context.mounted && action == 'delete') {
      await _confirmDelete(context, p);
    }
  }

  Future<void> _promptRename(BuildContext context, RtCanvasNamedLayout p) async {
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名布局'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(labelText: '布局名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) onRename(p.id, name);
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

// ═══════════════════════════════════════════════════════════════
// 列表条目：缩略图 + 名字 + 状态
// ═══════════════════════════════════════════════════════════════

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: _LayoutThumb(data: entry.data),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// 16:9 迷你画布示意：可见模块画圆角矩形（触摸板/输入框同画布默认规格），
/// 可见按钮画小圆点。只求"每套布局一眼可辨"，不做交互。
class _LayoutThumb extends StatelessWidget {
  const _LayoutThumb({required this.data});

  final RtCanvasLayout data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final moduleBorder = cs.primary.withValues(alpha: 0.55);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final moduleBoxes = <Widget>[];
          // 与画布渲染同语义：锚点缺失 = 隐藏；宽高缺省 = 模块默认规格。
          final touchpad = data.modules[kRtCanvasModuleTouchpad];
          final input = data.modules[kRtCanvasModuleInput];
          void addModule(RtCanvasAnchor? a, double defW, double defH) {
            if (a == null || !a.visible) return;
            final fw = a.w ?? defW;
            final fh = a.h ?? defH;
            moduleBoxes.add(
              Positioned(
                left: (a.x - fw / 2).clamp(0.0, 1.0) * w,
                top: (a.y - fh / 2).clamp(0.0, 1.0) * h,
                width: fw * w,
                height: fh * h,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: moduleBorder, width: 1),
                  ),
                ),
              ),
            );
          }

          addModule(touchpad, kRtCanvasPadDefW, kRtCanvasPadDefH);
          addModule(input, kRtCanvasInputDefW, kRtCanvasInputDefH);
          return Stack(
            children: [
              ...moduleBoxes,
              for (final e in data.buttons.entries)
                if (e.value.v)
                  Positioned(
                    left: e.value.x * w - 3,
                    top: e.value.y * h - 3,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            ],
          );
        }),
      ),
    );
  }
}
