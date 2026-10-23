// lib/core/remotetype/settings/rt_layouts_card.dart
//
// 设置页的「布局大卡」：整个布局区是一张卡，里面上下两栏——竖屏组、
// 横屏组，两组各自独立管理。
//
//   · 可用性由分组表达：组员先经 rtCanvasLayoutUsableIn 过滤——不可用的
//     布局根本不进该组，行上没有「置灰」这个状态；双朝向布局两组各一行。
//   · 点行 = 切该组激活（分朝向各记一个 ✓，另一组不受影响）。
//   · 行首把手 = 组内拖拽排序（rtLayoutsReorder 只重排本组相对顺序）。
//   · 管理只从行尾 ⋯ 进入（无长按手势）：在画布上编辑（仅 RT 页入口，
//     自动转向）/ 恢复出厂摆放（仅内置）/ 改名·删除（仅自定义）。
//   · 卡下「新建自定义布局」虚线行（rt_new_layout_row.dart）。
//
// 变更全部走 rt_layout_ops.dart 纯函数（与旧管理面板同一套规则）：
// 内置不可删、不可改名；删掉激活中的自定义布局由 op 回退默认。
//
// 视觉（C 形态定稿）：灰底画布（页面）+ 白卡（本卡，无描边）+ 纯文字
// 组头；色彩只用于标出「当前在用的布局」——激活行图标进 primaryContainer
// 圆角井，名称/✓ 转 primary。

import 'package:flutter/material.dart';

import '../../theme/context/colors.dart';
import '../data/rt_prefs.dart'
    show
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        rtCanvasLayoutUsableIn;
import 'rt_layout_row_tile.dart' show RtLayoutRowTile, RtRowBadge;
import 'rt_layout_dialogs.dart'
    show confirmDeleteCustom, confirmResetBuiltin, promptRenameLayout;

/// 布局大卡：竖屏组在上、横屏组在下，组间一条分隔带。
class RtLayoutsCard extends StatelessWidget {
  const RtLayoutsCard({
    super.key,
    required this.layouts,
    required this.canEditOnCanvas,
    required this.onSwitch,
    required this.onReorder,
    required this.onResetBuiltin,
    required this.onRename,
    required this.onDelete,
    this.onEditOnCanvas,
  });

  final RtCanvasLayouts layouts;

  /// RT 页进入时为 true：⋯ 菜单展示「在画布上编辑」（应用设置入口无画布，隐藏）。
  final bool canEditOnCanvas;

  /// 点行切该组激活（orientation + 布局 id）。
  final void Function(String orientation, String id) onSwitch;

  /// 组内拖拽排序（orientation + ReorderableListView 原始 old/newIndex）。
  final void Function(String orientation, int oldIndex, int newIndex) onReorder;

  /// 在画布上编辑（参数 = 布局 id；页面负责关设置页、切布局、转向、进编辑）。
  final ValueChanged<String>? onEditOnCanvas;

  /// 内置恢复出厂摆放。
  final ValueChanged<String> onResetBuiltin;

  /// 自定义改名（id + 已 trim 非空新名）。
  final void Function(String id, String name) onRename;

  /// 自定义删除。
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    // 竖屏在上、横屏在下；触控屏这类双朝向布局会同时出现在两组。
    final groups = <(String, List<RtCanvasNamedLayout>)>[
      (
        kRtCanvasOrientPortrait,
        [
          for (final p in layouts.list)
            if (rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p)) p,
        ],
      ),
      (
        kRtCanvasOrientLandscape,
        [
          for (final p in layouts.list)
            if (rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p)) p,
        ],
      ),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var gi = 0; gi < groups.length; gi++) ...[
              _groupHeader(context, groups[gi].$1, groups[gi].$2, gi),
              if (groups[gi].$2.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Text(
                    '该朝向暂无可用布局',
                    style: TextStyle(fontSize: 12.5, color: c.textMuted),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: groups[gi].$2.length,
                  onReorder: (oldIndex, newIndex) =>
                      onReorder(groups[gi].$1, oldIndex, newIndex),
                  itemBuilder: (ctx, i) {
                    final p = groups[gi].$2[i];
                    return RtLayoutRowTile(
                      key: ValueKey('${groups[gi].$1}_${p.id}'),
                      entry: p,
                      index: i,
                      isActive: p.id == layouts.activeFor(groups[gi].$1)?.id,
                      onSwitch: () => onSwitch(groups[gi].$1, p.id),
                      onMore: p.editable
                          ? () => _openRowMenu(context, groups[gi].$1, p)
                          : null,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 组头：纯文字标题（朝向 + 数量），无底色——分组靠标题与留白呼吸
  ///（C 形态定稿：色彩只留给「当前在用的布局」）。
  Widget _groupHeader(
    BuildContext context,
    String orient,
    List<RtCanvasNamedLayout> entries,
    int groupIndex,
  ) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, groupIndex == 0 ? 12 : 14, 16, 2),
      child: Row(
        children: [
          Text(
            orient == kRtCanvasOrientPortrait ? '竖屏' : '横屏',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${entries.length}',
            style: TextStyle(
              fontSize: 10,
              color: c.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // 行尾 ⋯：唯一管理入口。菜单朝向随组而定，动作平铺——不再按朝向分组。
  Future<void> _openRowMenu(
    BuildContext context,
    String orient,
    RtCanvasNamedLayout p,
  ) {
    final c = context.colors;
    final cs = c.scheme;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    RtRowBadge(
                      label: orient == kRtCanvasOrientPortrait ? '竖屏' : '横屏',
                      accent: true,
                    ),
                  ],
                ),
              ),
              if (canEditOnCanvas && onEditOnCanvas != null)
                ListTile(
                  leading: const Icon(Icons.open_with),
                  title: const Text('在画布上编辑'),
                  subtitle: const Text('自动转向，直接拖动模块与按钮摆位'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onEditOnCanvas!(p.id);
                  },
                ),
              if (p.builtIn)
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('恢复出厂摆放'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final ok = await confirmResetBuiltin(context, p);
                    if (ok) onResetBuiltin(p.id);
                  },
                ),
              if (!p.builtIn) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('改名'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final name = await promptRenameLayout(context, p);
                    if (name != null && name.isNotEmpty) onRename(p.id, name);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: Text('删除布局', style: TextStyle(color: cs.error)),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final ok = await confirmDeleteCustom(context, p);
                    if (ok) onDelete(p.id);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
