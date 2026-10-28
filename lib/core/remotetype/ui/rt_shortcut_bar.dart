// lib/core/remotetype/ui/rt_shortcut_bar.dart
//
// 输入框上方的快捷键托盘 + 序列宏编排 / 历史 sheet。
//
// 视觉对齐 docs/prototypes/remotetype-input.html：嵌套托盘、小 chip、无 emoji。
//
// v2 重写：「快捷键」条上的每条 RtShortcutItem 现在是一个序列宏（1..N 个
// chord + 共享毫秒间隔）。编排 sheet 用自绘虚拟键盘（rt_virtual_keyboard.dart）
// 取代文本输入；序列里的每一条 chord 都展示修饰键 chip + 主键 label，可拖动
// 排序、左滑删除。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../../ui/global/dialog/main.dart';
import '../../ui/global/notification/main.dart';
import '../data/rt_constants.dart';
import '../data/rt_prefs.dart';
import 'rt_virtual_keyboard.dart';

// ============================================================
// 顶部托盘（chips + 历史 / 编排入口）
// ============================================================

class RtShortcutBar extends StatelessWidget {
  const RtShortcutBar({
    super.key,
    required this.shortcuts,
    required this.display,
    required this.connected,
    required this.firingId,
    required this.onFire,
    required this.onEdit,
    required this.onHistory,
    required this.onDisplay,
  });

  final List<RtShortcutItem> shortcuts;

  /// 托盘显示配置（只显名字 / 明细；1 行 / 2 行）。
  final RtBarDisplay display;
  final bool connected;
  final String? firingId;
  final Future<void> Function(RtShortcutItem item) onFire;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onDisplay;

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
              _GhostBtn(label: '显示', onTap: onDisplay),
              const SizedBox(width: 6),
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
          else if (display.rows == 2)
            // 双行：各放一半，仍横向滑动——顺序保持先上后下。
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chipRow(
                  context,
                  shortcuts.sublist(0, (shortcuts.length / 2).ceil()),
                ),
                const SizedBox(height: 6),
                if (shortcuts.length > 1)
                  _chipRow(
                    context,
                    shortcuts.sublist((shortcuts.length / 2).ceil()),
                  ),
              ],
            )
          else
            // 单行横向滑动：条数多时不再折行堆叠占满整页，左右滑即可。
            _chipRow(context, shortcuts),
        ],
      ),
    );
  }

  Widget _chipRow(BuildContext context, List<RtShortcutItem> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ShortcutChip(
                item: item,
                showDetail: display.showDetail,
                busy: firingId == item.id,
                enabled: connected && firingId == null,
                onTap: () => onFire(item),
              ),
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

/// 单条快捷键 chip：
///   - showDetail=false → 只显示名字（配置「只显名字」时）
///   - 单 chord + 无间隔 → 紧凑形态（只显示 label）
///   - 多 chord 或 非零间隔 → 序列形态（在 label 下显示 "× N · YYYms"）
///  chip 内部能容下 1..3 个小 chord 预览（modifier+main 的字符串形式）；超过
///  3 个就出 "…" 概览，避免占满半屏。
class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.item,
    required this.showDetail,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final RtShortcutItem item;

  /// 托盘配置：是否显示按键明细（false 时无论什么形态都只显示名字）。
  final bool showDetail;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  static const int _previewMax = 3;

  bool get _isCompact =>
      item.chords.length <= kRtShortcutCompactChordCap && item.intervalMs == 0;

  bool get _showMeta => showDetail && !_isCompact;

  String _chordPreviewText(RtChord chord) {
    if (chord.keys.length <= 1) {
      final last = chord.keys.isEmpty ? '?' : chord.keys.last;
      return RtKeyDisplay.labelFor(last);
    }
    final mods = chord.keys.sublist(0, chord.keys.length - 1);
    final main = chord.keys.last;
    final buf = StringBuffer();
    for (final m in mods) {
      buf.write(RtKeyDisplay.labelFor(m));
      buf.write(' + ');
    }
    buf.write(RtKeyDisplay.labelFor(main));
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final bg = busy ? cs.primary : c.surface;
    final fg = busy ? cs.onPrimary : (enabled ? c.text : c.textMuted);
    final muted = busy ? cs.onPrimary.withValues(alpha: 0.8) : c.textMuted;

    final showMeta = _showMeta;
    final previewCount = item.chords.length.clamp(0, _previewMax);
    return Material(
      color: bg,
      elevation: busy ? 0 : 0.5,
      shadowColor: cs.shadow.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    if (showMeta) ...[
                      const SizedBox(height: 2),
                      Text(
                        '× ${item.chords.length}'
                        '${item.intervalMs > 0 ? ' · ${item.intervalMs} ms' : ''}',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      const SizedBox(height: 3),
                      for (var i = 0; i < previewCount; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            _chordPreviewText(item.chords[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                      if (item.chords.length > _previewMax)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '… +${item.chords.length - _previewMax}',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// ============================================================
// 托盘显示配置 sheet
// ============================================================

/// 托盘外观配置：只显名字 / 显示按键明细；单行 / 双行。
Future<RtBarDisplay?> showRtBarDisplaySheet({
  required BuildContext context,
  required RtBarDisplay current,
}) {
  return showModalBottomSheet<RtBarDisplay>(
    context: context,
    showDragHandle: true,
    builder: (_) => _BarDisplaySheet(current: current),
  );
}

class _BarDisplaySheet extends StatefulWidget {
  const _BarDisplaySheet({required this.current});
  final RtBarDisplay current;

  @override
  State<_BarDisplaySheet> createState() => _BarDisplaySheetState();
}

class _BarDisplaySheetState extends State<_BarDisplaySheet> {
  late bool _showDetail = widget.current.showDetail;
  late int _rows = widget.current.rows;

  void _pop() => Navigator.pop(
    context,
    RtBarDisplay(showDetail: _showDetail, rows: _rows),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '快捷键显示',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('只显示名字'),
            subtitle: Text(
              _showDetail ? '关闭后 chip 会带上按键明细' : 'chip 只显示名字，不显示按键明细',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            value: !_showDetail,
            onChanged: (v) => setState(() => _showDetail = !v),
          ),
          SwitchListTile(
            title: const Text('双行排列'),
            subtitle: Text(
              _rows == 2 ? 'chip 分两行排，仍可左右滑' : '单行排列，条多时左右滑',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            value: _rows == 2,
            onChanged: (v) => setState(() => _rows = v ? 2 : 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton(onPressed: _pop, child: const Text('完成')),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 编排 sheet
// ============================================================

/// 显示名 + 序列 (chord[]) + intervalMs 的完整编辑形态。
Future<RtShortcutItem?> showRtShortcutItemEditor({
  required BuildContext context,
  required RtShortcutItem? initial,
}) {
  return showModalBottomSheet<RtShortcutItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShortcutItemEditorSheet(initial: initial),
  );
}

/// 仅修改一条完整 RtShortcutItem（含 label）的入口；删除走「清空序列」后完
/// 成。如果 initial 为空表示新增。
class _ShortcutItemEditorSheet extends StatefulWidget {
  const _ShortcutItemEditorSheet({required this.initial});
  final RtShortcutItem? initial;

  @override
  State<_ShortcutItemEditorSheet> createState() =>
      _ShortcutItemEditorSheetState();
}

class _ShortcutItemEditorSheetState extends State<_ShortcutItemEditorSheet> {
  late TextEditingController _labelCtrl;
  late List<RtChord> _chords;
  late int _intervalMs;
  late String _id;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _id = init?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _labelCtrl = TextEditingController(text: init?.label ?? '');
    _chords = init == null
        ? <RtChord>[]
        : [for (final c in init.chords) RtChord(keys: List<String>.of(c.keys))];
    _intervalMs = init?.intervalMs ?? kRtShortcutIntervalDefaultMs;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _labelCtrl.text.trim().isNotEmpty && _chords.isNotEmpty;

  Future<void> _addChord() async {
    final picked = await showRtChordComposer(context: context);
    if (picked == null || !mounted) return;
    setState(() => _chords.add(picked));
  }

  Future<void> _addFromDefaults() async {
    // 默认库每一项 = 单 chord RtShortcutItem，添加时只摘它的 chords[0]，避免把
    // 「默认库里的快捷键」当成"包含一条预设 chord 的宏"。重名检查用 chords 序
    // 列化的字符串。
    final defaults = kDefaultRtShortcuts();
    final existing = _chords.map((c) => c.keys.join('+')).toSet();
    final pickable = defaults.where((d) {
      final firstKeys = d.chords.isEmpty
          ? const <String>[]
          : d.chords.first.keys;
      return firstKeys.isNotEmpty && !existing.contains(firstKeys.join('+'));
    }).toList();
    if (pickable.isEmpty) {
      if (!mounted) return;
      AppNotification.show(context, '默认库里的快捷键都已添加');
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
                child: Text(
                  '从默认库添加',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              for (final d in pickable)
                ListTile(
                  title: Text(d.label),
                  subtitle: Text(d.chords.first.keys.join(' + ')),
                  trailing: Icon(Icons.add, color: cs.primary),
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(
      () =>
          _chords.add(RtChord(keys: List<String>.of(picked.chords.first.keys))),
    );
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty || _chords.isEmpty) {
      AppNotification.show(context, '显示名与至少一条快捷键都不能为空',
          type: AppNotificationType.error);
      return;
    }
    Navigator.pop(
      context,
      RtShortcutItem(
        id: _id,
        label: label,
        chords: _chords,
        intervalMs: _intervalMs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      widget.initial == null ? '新增快捷键' : '编辑快捷键',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              // —— 显示名 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _labelCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '显示名',
                    hintText: '如：保存宏',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    enabledBorder: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: cs.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Text(
                      '键序列',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '长按拖动排序 · 左滑删除',
                      style: TextStyle(fontSize: 11, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _chords.isEmpty
                    ? Center(
                        child: Text(
                          '序列为空，点下方按钮加一组',
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        itemCount: _chords.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _chords.removeAt(oldIndex);
                            _chords.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final chord = _chords[index];
                          return Dismissible(
                            key: ValueKey(
                              'chord_${index}_${chord.keys.join('_')}',
                            ),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: cs.error,
                              ),
                            ),
                            onDismissed: (_) {
                              setState(() => _chords.removeAt(index));
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _ChordCard(
                                index: index,
                                chord: chord,
                                total: _chords.length,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // —— 间隔 slider ——
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '各组间隔',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.text,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$_intervalMs ms',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          min: kRtShortcutIntervalMinMs.toDouble(),
                          max: kRtShortcutIntervalMaxMs.toDouble(),
                          divisions: kRtShortcutIntervalDivisions,
                          value: _intervalMs.toDouble(),
                          onChanged: (v) =>
                              setState(() => _intervalMs = v.round()),
                        ),
                      ),
                      Text(
                        '0 = 立即接龙；1000 = 1 秒（上限）',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              // —— 加入按钮：自绘键盘 / 默认库 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _addChord,
                        icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                        label: const Text('+ 加一组快捷键'),
                      ),
                    ),
                  ],
                ),
              ),
              // —— 取消 / 完成 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canSave ? _save : null,
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

/// 序列里的一组卡片：修饰键 chips + 主键 label + 拖动手柄。
class _ChordCard extends StatelessWidget {
  const _ChordCard({
    required this.index,
    required this.chord,
    required this.total,
  });

  final int index;
  final RtChord chord;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final mods = chord.keys.length <= 1
        ? const <String>[]
        : chord.keys.sublist(0, chord.keys.length - 1);
    final mainKey = chord.keys.isEmpty ? '?' : chord.keys.last;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 0.5,
      shadowColor: cs.shadow.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
        child: Row(
          children: [
            // buildDefaultDragHandles:false 时拖拽手势必须自己绑在手柄上，
            // 否则列表看起来有手柄却拖不动。
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, size: 18, color: cs.outline),
            ),
            const SizedBox(width: 6),
            Text(
              '${index + 1}.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final m in mods)
                    _ModifierChip(label: RtKeyDisplay.labelFor(m)),
                  if (mods.isNotEmpty)
                    Text(
                      '+',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      RtKeyDisplay.labelFor(mainKey),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
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

class _ModifierChip extends StatelessWidget {
  const _ModifierChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

// ============================================================
// 自绘键盘 composer（sheet 套 sheet）
// ============================================================

/// 弹出虚拟键盘 + modifier chip 选择面板；用户按非修饰主键收一组，回传。
///
/// 设计：
///   - modifier 状态内部持有；modifier 键被点 → toggle；主键被点 → 用当前
///     modifiers 拼成 RtChord，弹回结果并保留键盘打开（连续录一组）。但因为
///     实际体验"录完"更清晰，**主键收完一次后 modifier 自动清空**——保持单
///     组操作的简单。
///   - 「修饰重置」清 modifier 但不收键。
Future<RtChord?> showRtChordComposer({required BuildContext context}) {
  return showModalBottomSheet<RtChord>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ChordComposerSheet(),
  );
}

class _ChordComposerSheet extends StatefulWidget {
  const _ChordComposerSheet();

  @override
  State<_ChordComposerSheet> createState() => _ChordComposerSheetState();
}

class _ChordComposerSheetState extends State<_ChordComposerSheet> {
  final Set<String> _activeMods = <String>{};
  bool _showFn = false;

  void _onKey(String keyId, {required bool isModifier}) {
    if (isModifier) {
      setState(() {
        if (_activeMods.contains(keyId)) {
          _activeMods.remove(keyId);
        } else {
          _activeMods.add(keyId);
        }
      });
      return;
    }
    // 主键 → 收 chord 并保持 modifier 状态，便于用户连点主键补一组。但实际上
    // 序列里同一组合多次出现很罕见，所以「收后不清 modifier」反而会让人搞不清
    // 当前录的是哪个 —— 选「收后清」更直观，modifier 需要时再点。
    final chord = RtChord(keys: [..._activeMods, keyId]);
    Navigator.pop(context, chord);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final modLabels = _activeMods.map((m) => RtKeyDisplay.labelFor(m)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Text(
                      '点键录一组',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _activeMods.isEmpty
                          ? null
                          : () => setState(_activeMods.clear),
                      child: const Text('修饰重置'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '当前：',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modLabels.isEmpty
                              ? '（无修饰）'
                              : '${modLabels.join(' + ')}  +  _',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showFn = !_showFn),
                    icon: Icon(
                      _showFn ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: Text(_showFn ? '收起 Fn' : '展开 Fn (Esc/F1-F12)'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: RtVirtualKeyboard(
                    activeModifiers: _activeMods,
                    showFnRow: _showFn,
                    onKey: _onKey,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('取消'),
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

// ============================================================
// 按键名 → 人话 label 映射（modifier 键 RT1 白名单 + 主键按用户视觉习惯命名）
// ============================================================

class RtKeyDisplay {
  RtKeyDisplay._();

  /// 把 `RtChord.keys` 元素转成 UI 显示用的短词。modifier 优先用自己的名字，主
  /// 键按 PC 常见习惯大写/图标化。
  static String labelFor(String keyId) {
    switch (keyId) {
      // —— modifiers ——
      case 'win':
      case 'meta':
      case 'cmd':
      case 'super':
        return 'Win';
      case 'ctrl':
      case 'control':
        return 'Ctrl';
      case 'alt':
      case 'option':
        return 'Alt';
      case 'shift':
        return 'Shift';
      // —— 命名键 ——
      case 'escape':
      case 'esc':
        return 'Esc';
      case 'tab':
        return 'Tab';
      case 'enter':
      case 'return':
        return 'Enter';
      case 'backspace':
        return '⌫';
      case 'delete':
      case 'del':
        return 'Del';
      case 'caps':
      case 'capslock':
        return 'Caps';
      case 'space':
        return 'Space';
      case 'left':
      case 'arrowleft':
        return '←';
      case 'right':
      case 'arrowright':
        return '→';
      case 'up':
      case 'arrowup':
        return '↑';
      case 'down':
      case 'arrowdown':
        return '↓';
      case 'home':
        return 'Home';
      case 'end':
        return 'End';
      case 'pageup':
        return 'PgUp';
      case 'pagedown':
        return 'PgDn';
      // f1..f12 / others 走 fallback：单字符 / f-名前
    }
    final fMatch = RegExp(r'^f([1-9]|1[0-2])$').firstMatch(keyId);
    if (fMatch != null) return 'F${fMatch.group(1)}';
    // 单字符 / 标点：单字符大写；其余原样返回（避免无端截断）。
    if (keyId.length == 1) return keyId.toUpperCase();
    return keyId;
  }
}

// ============================================================
// 旧入口兼容 / 列表级编排入口
// ============================================================

/// 列表级编排 sheet：编辑 / 删除 / 排序 / 新增整条 `RtShortcutItem`。
///
/// 跟「编辑单条 RtShortcutItem」的区别：单条 sheet 改的是 chords + intervalMs；
/// 这里改的是整张列表（多 chip 之间的顺序与存在性）。
///
/// 单条编辑走 `showRtShortcutItemEditor(initial: item)` 嵌套打开；用户回到
/// 本 sheet 后回填改后的 item。
Future<List<RtShortcutItem>?> showRtShortcutListEditor({
  required BuildContext context,
  required List<RtShortcutItem> current,
}) {
  return showModalBottomSheet<List<RtShortcutItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShortcutListEditorSheet(initial: current),
  );
}

class _ShortcutListEditorSheet extends StatefulWidget {
  const _ShortcutListEditorSheet({required this.initial});
  final List<RtShortcutItem> initial;

  @override
  State<_ShortcutListEditorSheet> createState() =>
      _ShortcutListEditorSheetState();
}

class _ShortcutListEditorSheetState extends State<_ShortcutListEditorSheet> {
  late List<RtShortcutItem> _items;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final e in widget.initial)
        // 深拷贝 chord.keys —— 编辑单条时不污染外部。
        RtShortcutItem(
          id: e.id,
          label: e.label,
          chords: [
            for (final c in e.chords) RtChord(keys: List<String>.of(c.keys)),
          ],
          intervalMs: e.intervalMs,
        ),
    ];
  }

  Future<void> _editAt(int index) async {
    final next = await showRtShortcutItemEditor(
      context: context,
      initial: _items[index],
    );
    if (next == null || !mounted) return;
    setState(() => _items[index] = next);
  }

  Future<void> _addNew() async {
    final next = await showRtShortcutItemEditor(
      context: context,
      initial: null,
    );
    if (next == null || !mounted) return;
    setState(() => _items.add(next));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '编排快捷键（${_items.length}）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await BaseConfirmDialog.show(
                          context: context,
                          title: '恢复默认？',
                          message: '当前编排将被覆盖为 10 条默认快捷键',
                          confirmLabel: '恢复',
                          onConfirm: () =>
                              setState(() => _items = kDefaultRtShortcuts()),
                        );
                      },
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  '点卡片编辑 · 长按拖动排序 · 左滑删除',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          '列表为空，点下方按钮加一条',
                          style: TextStyle(color: context.colors.textMuted),
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
                            key: ValueKey('item_${item.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: cs.error,
                              ),
                            ),
                            onDismissed: (_) {
                              setState(
                                () =>
                                    _items.removeWhere((e) => e.id == item.id),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Material(
                                color: cs.surface,
                                elevation: 0.5,
                                shadowColor: cs.shadow.withValues(alpha: 0.06),
                                surfaceTintColor: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () => _editAt(index),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      14,
                                      10,
                                    ),
                                    child: Row(
                                      children: [
                                        // 同 chord 卡片：手柄自带拖拽手势。
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Icon(
                                            Icons.drag_handle,
                                            color: cs.outline,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                item.label,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: context
                                                      .colors
                                                      .scheme
                                                      .onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.chords.length == 1 &&
                                                        item.intervalMs == 0
                                                    ? item.chords.first.keys
                                                          .join(' + ')
                                                    : '× ${item.chords.length}'
                                                          '${item.intervalMs > 0 ? ' · ${item.intervalMs} ms' : ''}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      context.colors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: cs.outline,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
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
                        onPressed: _addNew,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('+ 新增'),
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

/// 锁屏类快捷键（Win+L 等）的确认弹窗：条上一点即发、误触代价高，先确认。
Future<bool> showRtLockConfirm({
  required BuildContext context,
  required RtShortcutItem item,
}) {
  // bool 合同保留给调用方（发送动作由调用方在拿到 true 后执行）。
  return BaseConfirmDialog.show(
    context: context,
    title: '锁屏？',
    message: '将向电脑发送 ${item.label}',
    confirmLabel: '锁屏',
    onConfirm: () {},
  );
}

// ============================================================
// 历史输入记录 sheet（保留）
// ============================================================

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
                  Text('历史输入', style: Theme.of(context).textTheme.titleMedium),
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
                          surfaceTintColor: Colors.transparent,
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
