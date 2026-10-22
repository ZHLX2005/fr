// lib/core/remotetype/ui/rt_layout_picker.dart
//
// 布局切换面板：**第一层是布局列表**，设置入口附在列表下面。
//
// 竖屏页头与横屏左上角共用这一份：
//   · 主体 = 所有布局的列表（按朝向分组，当前朝向那组可点，另一组灰显
//     「旋转到该朝向后可用」）——切布局是高频动作，占第一层；
//   · 尾巴 = 「远程输入设置」入口——设置与配置相关的功能尽量收进那里
//     （布局改名/删除/新建、模块编排、发送换行、灵敏度、快捷键），
//     让常用路径只留「切布局」这一件事。
//
// 画布与写字页是同一张布局表的两种渲染形态（kind=canvas / kind=writer），
// 所以切换面板对两者通用。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../data/rt_prefs.dart';

/// 打开布局切换面板。
///
/// [layouts] 当前布局集，[orientation] 当前朝向（该组可点），[activeId]
/// 当前激活项（打勾），[onPick] 选中回调（面板先自行关闭），
/// [onOpenSettings] 附在列表下的设置入口（可为 null → 不渲染该行）。
Future<void> showRtLayoutPicker(
  BuildContext context, {
  required RtCanvasLayouts layouts,
  required String orientation,
  required String activeId,
  required ValueChanged<String> onPick,
  VoidCallback? onOpenSettings,
}) {
  // 两组都列出来：当前朝向那组可点，另一组灰显（旋转过去才可用）。
  final groups = <(String, List<RtCanvasNamedLayout>)>[
    (
      kRtCanvasOrientPortrait,
      layouts.list
          .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p))
          .toList(growable: false),
    ),
    (
      kRtCanvasOrientLandscape,
      layouts.list
          .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p))
          .toList(growable: false),
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.colors;
      final cs = c.scheme;
      // 选中即关面板再回调（列表项的公共动作）。
      void pick(String id) {
        Navigator.of(ctx).pop();
        onPick(id);
      }
      return SafeArea(
        child: ConstrainedBox(
          // 列表长时占大半屏，设置入口始终贴在列表下面。
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    Text(
                      '切换布局',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '当前：${_nameOf(layouts, orientation, activeId) ?? '—'}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (final (groupOrient, entries) in groups)
                      if (entries.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                          child: Row(
                            children: [
                              Text(
                                groupOrient == kRtCanvasOrientPortrait
                                    ? '竖屏布局'
                                    : '横屏布局',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (groupOrient != orientation) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '（旋转到该朝向后可用）',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        for (final p in entries)
                          _LayoutRow(
                            entry: p,
                            interactive: groupOrient == orientation,
                            isActive: groupOrient == orientation && p.id == activeId,
                            onTap: groupOrient == orientation
                                ? () => pick(p.id)
                                : null,
                          ),
                      ],
                    ],
                ),
              ),
              if (onOpenSettings != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.tune, color: cs.primary),
                  title: const Text('远程输入设置'),
                  subtitle: const Text('布局编排 · 回车行为 · 快捷键'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onOpenSettings();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// 列表里的一条布局。
class _LayoutRow extends StatelessWidget {
  const _LayoutRow({
    required this.entry,
    required this.interactive,
    required this.isActive,
    required this.onTap,
  });

  final RtCanvasNamedLayout entry;
  final bool interactive;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final dim = !interactive;
    final titleColor = dim
        ? c.textMuted.withValues(alpha: 0.6)
        : (isActive ? cs.primary : c.text);
    return ListTile(
      enabled: interactive,
      leading: Icon(
        entry.kind == RtLayoutKind.writer
            ? Icons.keyboard_alt_outlined
            : Icons.dashboard_customize_outlined,
        color: dim
            ? c.textMuted.withValues(alpha: 0.5)
            : (isActive ? cs.primary : c.textMuted),
      ),
      title: Text(
        entry.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: titleColor,
        ),
      ),
      // 固定死的默认布局不做编排——标出来，免得用户去找编辑入口。
      subtitle: entry.editable
          ? null
          : Text(
              '固定布局',
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
      trailing: isActive
          ? Icon(Icons.check, color: cs.primary)
          : (entry.builtIn
                ? Text(
                    '内置',
                    style: TextStyle(fontSize: 10.5, color: c.textMuted),
                  )
                : null),
      onTap: onTap,
    );
  }
}

/// 当前激活布局的名字（查不到回 null）。
String? _nameOf(RtCanvasLayouts layouts, String orientation, String activeId) {
  for (final p in layouts.list) {
    if (p.id == activeId &&
        rtCanvasLayoutUsableIn(orientation, p)) {
      return p.name;
    }
  }
  return null;
}
