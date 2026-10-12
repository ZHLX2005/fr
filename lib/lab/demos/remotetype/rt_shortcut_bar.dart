// 输入框上方的快捷键托盘 + 编排 / 历史 sheet。
// 视觉对齐 docs/prototypes/remotetype-input.html：嵌套托盘、小 chip、无 emoji。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';
import 'rt_prefs.dart';

/// 输入框上方：快捷键 chips + 历史 / 编排入口。
class RtShortcutBar extends StatelessWidget {
  const RtShortcutBar({
    super.key,
    required this.shortcuts,
    required this.connected,
    required this.firingId,
    required this.onFire,
    required this.onEdit,
    required this.onHistory,
  });

  final List<RtShortcutItem> shortcuts;
  final bool connected;
  final String? firingId;
  final Future<void> Function(RtShortcutItem item) onFire;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '快捷键',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.textMuted,
                ),
              ),
              const Spacer(),
              _GhostBtn(label: '历史', onTap: onHistory),
              const SizedBox(width: 6),
              _GhostBtn(label: '编排', onTap: onEdit),
            ],
          ),
          const SizedBox(height: 8),
          if (shortcuts.isEmpty)
            Text(
              '暂无快捷键，点「编排」添加',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in shortcuts)
                  _ShortcutChip(
                    item: item,
                    busy: firingId == item.id,
                    enabled: connected && firingId == null,
                    onTap: () => onFire(item),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  const _GhostBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.item,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final RtShortcutItem item;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final bg = busy ? cs.primary : c.surface;
    final fg = busy ? cs.onPrimary : (enabled ? c.text : c.textMuted);
    return Material(
      color: bg,
      elevation: busy ? 0 : 0.5,
      shadowColor: cs.shadow.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 编排 sheet：拖拽排序 / 删除 / 从默认库添加。
Future<List<RtShortcutItem>?> showRtShortcutEditor({
  required BuildContext context,
  required List<RtShortcutItem> current,
}) {
  return showModalBottomSheet<List<RtShortcutItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShortcutEditorSheet(initial: current),
  );
}

class _ShortcutEditorSheet extends StatefulWidget {
  const _ShortcutEditorSheet({required this.initial});
  final List<RtShortcutItem> initial;

  @override
  State<_ShortcutEditorSheet> createState() => _ShortcutEditorSheetState();
}

class _ShortcutEditorSheetState extends State<_ShortcutEditorSheet> {
  late List<RtShortcutItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initial);
  }

  Future<void> _addFromDefaults() async {
    final defaults = kDefaultRtShortcuts();
    final existing = _items.map((e) => e.keys.join('+')).toSet();
    final pickable = defaults
        .where((d) => !existing.contains(d.keys.join('+')))
        .toList();
    if (pickable.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('默认库里的快捷键都已添加')),
      );
      return;
    }
    final picked = await showModalBottomSheet<RtShortcutItem>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('从默认库添加',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final d in pickable)
                ListTile(
                  title: Text(d.label),
                  subtitle: Text(d.keys.join(' + ')),
                  trailing: Icon(Icons.add, color: cs.primary),
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _items.add(RtShortcutItem(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        label: picked.label,
        keys: List.of(picked.keys),
      ));
    });
  }

  Future<void> _addCustom() async {
    final labelCtrl = TextEditingController();
    final keysCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: '显示名',
                hintText: '如：Win+R 运行',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keysCtrl,
              decoration: const InputDecoration(
                labelText: '按键（+ 分隔）',
                hintText: 'win+r 或 ctrl+shift+t',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '修饰键：win/ctrl/alt/shift；末位为主键（字母、f5、tab、escape…）',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(ctx).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final label = labelCtrl.text.trim();
    final keys = keysCtrl.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'[+\s]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    labelCtrl.dispose();
    keysCtrl.dispose();
    if (ok != true || !mounted) return;
    if (label.isEmpty || keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('显示名与按键不能为空')),
      );
      return;
    }
    setState(() {
      _items.add(RtShortcutItem(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        label: label,
        keys: keys,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text('编排快捷键',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        setState(() => _items = kDefaultRtShortcuts());
                      },
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '长按拖动排序 · 左滑删除',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _items.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _items.removeAt(oldIndex);
                      _items.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: cs.errorContainer,
                        child: Icon(Icons.delete_outline, color: cs.error),
                      ),
                      onDismissed: (_) {
                        setState(
                          () => _items.removeWhere((e) => e.id == item.id),
                        );
                      },
                      child: ListTile(
                        leading: Icon(Icons.drag_handle, color: cs.outline),
                        title: Text(item.label),
                        subtitle: Text(item.keys.join(' + ')),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addFromDefaults,
                        icon: const Icon(Icons.library_add_outlined, size: 18),
                        label: const Text('默认库'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addCustom,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('自定义'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _items),
                        child: const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史输入记录 sheet。
Future<String?> showRtHistorySheet({
  required BuildContext context,
  required List<String> history,
  required Future<void> Function() onClear,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HistorySheet(history: history, onClear: onClear),
  );
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.history, required this.onClear});

  final List<String> history;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Text('历史输入',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (history.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await onClear();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text('清空', style: TextStyle(color: cs.error)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Text(
                        '暂无记录\n发送（回车注入=发送）后会自动保存',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final text = history[i];
                        return Material(
                          color: c.surface,
                          elevation: 0.5,
                          shadowColor: cs.shadow.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => Navigator.pop(context, text),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Text(
                                text,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
