// lib/core/remotetype/canvas/rt_canvas_layouts_sheet.dart
//
// 画布布局管理面板（对齐 docs/prototypes/rt-canvas-layouts-manage.html）：
//   · 横屏 / 竖屏两组各自可拖拽编排顺序（组内 ReorderableListView）；
//   · 仅当前朝向的组可点按切换激活；另一组半透明（旋转后可用）；
//   · ⋯ 与长按同一套小圆角菜单：修改布局 / 恢复出厂（内置）/
//     重命名·删除（自定义）；固定死布局（writable=false）无菜单；
//   · 「修改」→ 回调 onEdit（可跨朝向；页面切布局、自动转向并进编辑）；
//   · 底部「新建自定义布局」→ 先选朝向再创建空画布。
//
// 本件只负责「展示 + 收集意图」，持久化与状态切换由页面的回调接管。

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/rt_layout_ops.dart'
    show
        rtLayoutsCopyToCustom,
        rtLayoutsDeleteCustom,
        rtLayoutsRename,
        rtLayoutsReorder,
        rtLayoutsResetBuiltin;
import '../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonShape,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleDpad,
        kRtCanvasModuleInput,
        kRtCanvasModuleKb,
        kRtCanvasModuleTouchpad,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW,
        rtCanvasLayoutUsableIn;

class RtCanvasLayoutsSheet extends StatelessWidget {
  const RtCanvasLayoutsSheet({
    super.key,
    required this.layouts,
    required this.activeId,
    required this.orientation,
    required this.onSwitch,
    required this.onCopy,
    required this.onDelete,
    required this.onRename,
    required this.onResetBuiltin,
    required this.onReorder,
    this.onEdit,
    this.scrollController,
  });

  final RtCanvasLayouts layouts;

  /// 当前朝向的激活布局 id（高亮用；另一侧激活不参与本面板）。
  final String activeId;

  /// 画布当前朝向（kRtCanvasOrient*）：决定哪一组可点选激活。
  final String orientation;

  /// 列表滚动控制器：底部上滑壳传入 DraggableScrollableSheet 的控制器
  /// （拖拽条联动列表）；抽屉壳传 null（列表自管）。
  final ScrollController? scrollController;

  /// 点按切换当前朝向的激活布局。
  final ValueChanged<String> onSwitch;

  /// 复制当前为新自定义（参数 = 用户选的朝向 kRtCanvasOrient*）。
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onDelete;

  /// 重命名自定义布局（id + 新名字，已 trim 非空）。
  final void Function(String id, String name) onRename;

  /// 把内置布局恢复出厂摆放（数据重置为代码预设，其它布局不动）。
  final ValueChanged<String> onResetBuiltin;

  /// 组内拖拽排序（orientation + ReorderableListView 原始 old/newIndex）。
  final void Function(String orientation, int oldIndex, int newIndex) onReorder;

  /// 「修改布局」：切到该布局并进编辑态。空 = 菜单不展示该项。
  final ValueChanged<String>? onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 内置 + 自定义，各按朝向可用分组（触控屏双朝向会出现在两组）。
    // 渲染持久化版本——列表若直接渲染代码常量，用户改过的内置会"失真"。
    final groups = <(String, List<RtCanvasNamedLayout>)>[
      (
        kRtCanvasOrientLandscape,
        layouts.list
            .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientLandscape, p))
            .toList(growable: false),
      ),
      (
        kRtCanvasOrientPortrait,
        layouts.list
            .where((p) => rtCanvasLayoutUsableIn(kRtCanvasOrientPortrait, p))
            .toList(growable: false),
      ),
    ];

    // 纯内容：标题 + 分组可拖列表 + 底部新建。外壳由 showRtCanvasLayoutsPanel 装配。
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Text(
                '画布布局',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '当前：${_nameOf(layouts, orientation, activeId) ?? '—'}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            primary: false,
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final (groupOrient, entries) in groups)
                if (entries.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        Text(
                          groupOrient == kRtCanvasOrientPortrait
                              ? '竖屏编排'
                              : '横屏编排',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (groupOrient != orientation) ...[
                          const SizedBox(width: 6),
                          Text(
                            '（旋转后可激活）',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: entries.length,
                    onReorder: (oldIndex, newIndex) =>
                        onReorder(groupOrient, oldIndex, newIndex),
                    itemBuilder: (ctx, i) {
                      final p = entries[i];
                      final canActivate = groupOrient == orientation;
                      return _LayoutTile(
                        key: ValueKey('${groupOrient}_${p.id}'),
                        entry: p,
                        index: i,
                        isActive: canActivate && p.id == activeId,
                        interactive: canActivate,
                        onTap: canActivate ? () => onSwitch(p.id) : null,
                        // 「修改」两组都给：跨朝向由页面切布局并自动转向。
                        onMore: p.editable
                            ? (anchor) => _openActions(
                                  ctx,
                                  p,
                                  anchor,
                                  allowEdit: true,
                                )
                            : null,
                        onLongPress: p.editable
                            ? () => _openActions(
                                  ctx,
                                  p,
                                  null,
                                  allowEdit: true,
                                )
                            : null,
                      );
                    },
                  ),
                ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _pickCopyOrientation(context),
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('新建自定义布局'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '拖左侧 ≡ 排序 · ⋯ / 长按打开操作',
                  style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String? _nameOf(
    RtCanvasLayouts layouts,
    String orientation,
    String id,
  ) {
    for (final p in layouts.list) {
      if (p.id == id && rtCanvasLayoutUsableIn(orientation, p)) return p.name;
    }
    return null;
  }

  // ---- 复制：先选朝向 ----

  Future<void> _pickCopyOrientation(BuildContext context) async {
    final orient = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('新建自定义布局（选择朝向）'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(kRtCanvasOrientLandscape),
            child: const ListTile(
              leading: Icon(Icons.stay_current_landscape),
              title: Text('横屏布局'),
              subtitle: Text('空画布，归入横屏组'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(kRtCanvasOrientPortrait),
            child: const ListTile(
              leading: Icon(Icons.stay_current_portrait),
              title: Text('竖屏布局'),
              subtitle: Text('空画布，归入竖屏组（旋转后可用）'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (orient != null) onCopy(orient);
  }

  // ---- ⋯ / 长按：小圆角操作卡（对齐原型） ----

  Future<void> _openActions(
    BuildContext context,
    RtCanvasNamedLayout p,
    Offset? anchorGlobal, {
    required bool allowEdit,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position;
    if (anchorGlobal != null && overlay != null) {
      final topLeft = overlay.globalToLocal(anchorGlobal);
      position = RelativeRect.fromLTRB(
        topLeft.dx - 168,
        topLeft.dy,
        overlay.size.width - topLeft.dx,
        0,
      );
    } else {
      // 长按无锚点：落在屏幕中部偏上。
      final size = MediaQuery.sizeOf(context);
      position = RelativeRect.fromLTRB(
        size.width - 200,
        size.height * 0.35,
        24,
        size.height * 0.35,
      );
    }

    final action = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: cs.surface.withValues(alpha: 0.98),
      elevation: 8,
      items: [
        PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            p.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        if (onEdit != null && allowEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined, size: 20),
              title: Text('修改布局'),
            ),
          ),
        if (p.builtIn)
          const PopupMenuItem(
            value: 'reset',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restart_alt, size: 20),
              title: Text('恢复出厂'),
            ),
          )
        else ...[
          const PopupMenuItem(
            value: 'rename',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.drive_file_rename_outline, size: 20),
              title: Text('重命名'),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, size: 20, color: cs.error),
              title: Text('删除', style: TextStyle(color: cs.error)),
            ),
          ),
        ],
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'edit':
        onEdit?.call(p.id);
      case 'reset':
        await _confirmReset(context, p);
      case 'rename':
        await _promptRename(context, p);
      case 'delete':
        await _confirmDelete(context, p);
    }
  }

  Future<void> _confirmReset(
    BuildContext context,
    RtCanvasNamedLayout p,
  ) async {
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

  Future<void> _promptRename(
    BuildContext context,
    RtCanvasNamedLayout p,
  ) async {
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
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) onRename(p.id, name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RtCanvasNamedLayout p,
  ) async {
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
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    required this.interactive,
    required this.onTap,
    this.onMore,
    this.onLongPress,
  });

  final RtCanvasNamedLayout entry;
  final int index;
  final bool isActive;

  /// false = 另一朝向的组：置灰展示，点按不响应（旋转后可用）。
  final bool interactive;
  final VoidCallback? onTap;

  /// ⋯：回报锚点全局坐标，供小圆角菜单定位。
  final void Function(Offset anchorGlobal)? onMore;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final portrait = entry.orientation == kRtCanvasOrientPortrait;
    return Opacity(
      opacity: interactive ? 1.0 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 10),
                SizedBox(width: 96, child: _LayoutThumb(data: entry.data)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          if (portrait) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.stay_current_portrait,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (entry.builtIn)
                            _MiniBadge(
                              label: '内置',
                              color: cs.onSurfaceVariant,
                              bg: cs.surfaceContainerHighest,
                            ),
                          if (!entry.editable)
                            _MiniBadge(
                              label: '固定',
                              color: cs.onSurfaceVariant,
                              bg: cs.surfaceContainerHighest,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onMore != null)
                  Builder(
                    builder: (btnCtx) {
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '更多',
                        icon: Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          final box =
                              btnCtx.findRenderObject() as RenderBox?;
                          final origin = box?.localToGlobal(Offset.zero) ??
                              Offset.zero;
                          final size = box?.size ?? Size.zero;
                          onMore!(
                            Offset(
                              origin.dx + size.width,
                              origin.dy + size.height,
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.label,
    required this.color,
    required this.bg,
  });

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: color)),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final moduleBoxes = <Widget>[];
            // 与画布渲染同语义：锚点缺失 = 隐藏；宽高缺省 = 模块默认规格。
            final touchpad = data.modules[kRtCanvasModuleTouchpad];
            final input = data.modules[kRtCanvasModuleInput];
            final dpad = data.modules[kRtCanvasModuleDpad];
            final vpad = data.modules[kRtCanvasModuleVpad];
            final kb = data.modules[kRtCanvasModuleKb];
            void addModule(RtCanvasAnchor? a, double defW, double defH) {
              if (a == null || !a.visible) return;
              final fw = a.w ?? defW;
              final fh = a.h ?? defH;
              // 满屏（w/h≈1）贴边无圆角，与原型 .pad.full 一致。
              final full = fw >= 0.98 && fh >= 0.98;
              moduleBoxes.add(
                Positioned(
                  left: full ? 0 : (a.x - fw / 2).clamp(0.0, 1.0) * w,
                  top: full ? 0 : (a.y - fh / 2).clamp(0.0, 1.0) * h,
                  width: full ? w : fw * w,
                  height: full ? h : fh * h,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: full
                          ? BorderRadius.zero
                          : BorderRadius.circular(4),
                      border: Border.all(color: moduleBorder, width: 1),
                    ),
                  ),
                ),
              );
            }

            // 方向模块缩略：四向键 = 十字；八向轮盘 = 圆（一眼可辨两套游戏布局）。
            if (dpad != null && dpad.visible) {
              final fw = dpad.w ?? 0.22;
              final fh = dpad.h ?? 0.52;
              final side = math.min(fw * w, fh * h);
              final left = (dpad.x * w - side / 2).clamp(0.0, w - side);
              final top = (dpad.y * h - side / 2).clamp(0.0, h - side);
              if (dpad.dir8) {
                moduleBoxes.add(
                  Positioned(
                    left: left,
                    top: top,
                    width: side,
                    height: side,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surface,
                        border: Border.all(color: moduleBorder, width: 1),
                      ),
                    ),
                  ),
                );
              } else {
                final arm = side * 0.28;
                moduleBoxes.add(
                  Positioned(
                    left: left,
                    top: top,
                    width: side,
                    height: side,
                    child: Stack(
                      children: [
                        Align(
                          child: Container(
                            width: side * 0.72,
                            height: arm,
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: moduleBorder,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          child: Container(
                            width: arm,
                            height: side * 0.72,
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: moduleBorder,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }
            addModule(touchpad, kRtCanvasPadDefW, kRtCanvasPadDefH);
            addModule(input, kRtCanvasInputDefW, kRtCanvasInputDefH);
            // 手柄键区：外框 + ABXY 色点（原型 paintThumb 同源）。
            if (vpad != null && vpad.visible) {
              final fw = vpad.w ?? 0.36;
              final fh = vpad.h ?? 0.70;
              final vx = (vpad.x - fw / 2) * w;
              final vy = (vpad.y - fh / 2) * h;
              final vw = fw * w;
              final vh = fh * h;
              moduleBoxes.add(
                Positioned(
                  left: vx.clamp(0.0, w),
                  top: vy.clamp(0.0, h),
                  width: vw,
                  height: vh,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: moduleBorder, width: 1),
                    ),
                  ),
                ),
              );
              final d = math.min(vw * 0.18, vh * 0.15);
              final arm = d * 0.62;
              final spots = <Color, Offset>{
                const Color(0xFFE3B341): Offset(vx + vw / 2, vy + vh * 0.32),
                const Color(0xFF4C8DF6): Offset(
                  vx + vw / 2 - arm * 0.8,
                  vy + vh * 0.52,
                ),
                const Color(0xFFF0524D): Offset(
                  vx + vw / 2 + arm * 0.8,
                  vy + vh * 0.52,
                ),
                const Color(0xFF3FB950): Offset(vx + vw / 2, vy + vh * 0.72),
              };
              for (final e in spots.entries) {
                moduleBoxes.add(
                  Positioned(
                    left: e.value.dx - d / 2,
                    top: e.value.dy - d / 2,
                    width: d,
                    height: d,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: e.key,
                      ),
                    ),
                  ),
                );
              }
            }
            // 键盘模块：圆角矩形内画横线（键排意象），与触摸板矩形区分开。
            if (kb != null && kb.visible) {
              final fw = kb.w ?? 0.94;
              final fh = kb.h ?? 0.82;
              final kx = (kb.x - fw / 2).clamp(0.0, 1.0) * w;
              final ky = (kb.y - fh / 2).clamp(0.0, 1.0) * h;
              moduleBoxes.add(
                Positioned(
                  left: kx,
                  top: ky,
                  width: fw * w,
                  height: fh * h,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: moduleBorder, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < 5; i++)
                          Container(
                            height: 1.5,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }
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
                          // 圆形手柄键用主题色点，胶囊键用中性点——一眼分清。
                          shape: BoxShape.circle,
                          color: e.value.shape == RtCanvasButtonShape.circle
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 布局面板入口：按画布朝向装配外壳（效果对齐原型 rt-canvas-gamepad）。
///   · 竖屏 = 底部上滑（DraggableScrollableSheet + 顶部拖拽条）；
///   · 横屏 = 左侧抽屉（通高、右缘圆角、竖 grab 贴右缘、easeOutBack 弹簧
///     滑入、毛玻璃遮罩）。
/// 回调语义同 [RtCanvasLayoutsSheet]；关闭由各回调自行 Navigator.pop。
Future<void> showRtCanvasLayoutsPanel(
  BuildContext context, {
  required RtCanvasLayouts layouts,
  required String activeId,
  required String orientation,
  /// 面板内一切变更（切换 / 新建 / 删改名 / 恢复 / 排序）算完后整表回写。
  /// 单一事实源，避免面板 live 态与页面各算一遍导致脱节。
  required ValueChanged<RtCanvasLayouts> onLayoutsChanged,
  ValueChanged<String>? onEdit,
}) {
  // 面板内自持一份 live 布局：排序/改名/删除后立刻重绘，避免打开时
  // 快照在旋转或连续拖拽时与已落盘数据脱节。
  Widget livePanel({ScrollController? scrollController}) {
    var live = layouts;
    var liveActive = activeId;
    return StatefulBuilder(
      builder: (ctx, setModal) {
        final liveOrientation =
            MediaQuery.orientationOf(ctx) == Orientation.landscape
            ? kRtCanvasOrientLandscape
            : kRtCanvasOrientPortrait;
        void commit(RtCanvasLayouts next) {
          live = next;
          liveActive = next.activeFor(liveOrientation)?.id ?? liveActive;
          setModal(() {});
          onLayoutsChanged(next);
        }

        return RtCanvasLayoutsSheet(
          layouts: live,
          activeId: liveActive,
          orientation: liveOrientation,
          scrollController: scrollController,
          onSwitch: (id) => commit(live.withActiveFor(liveOrientation, id)),
          onCopy: (orient) {
            final next = rtLayoutsCopyToCustom(live, orient);
            final newId = next.list.last.id;
            commit(next.withActiveFor(orient, newId));
          },
          onDelete: (id) => commit(rtLayoutsDeleteCustom(live, id)),
          onRename: (id, name) => commit(rtLayoutsRename(live, id, name)),
          onResetBuiltin: (id) => commit(rtLayoutsResetBuiltin(live, id)),
          onReorder: (orient, oldIndex, newIndex) =>
              commit(rtLayoutsReorder(live, orient, oldIndex, newIndex)),
          onEdit: onEdit,
        );
      },
    );
  }

  if (orientation == kRtCanvasOrientPortrait) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, controller) {
            final cs = Theme.of(ctx).colorScheme;
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
                  Expanded(child: livePanel(scrollController: controller)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 横屏：左侧抽屉。barrier 用框架的 black38（点击关闭），页面内再叠一层
  // 忽略指针的 BackdropFilter 做毛玻璃（框架 barrier 不支持 blur）。
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭布局面板',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (ctx, anim, secondary) {
      final cs = Theme.of(ctx).colorScheme;
      final dw = math.min(400.0, MediaQuery.sizeOf(ctx).width * 0.8);
      return Stack(
        children: [
          // 毛玻璃（IgnorePointer：点击穿透给框架 barrier 走关闭）。
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: dw,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(26),
                ),
                border: Border(
                  right: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.20),
                    blurRadius: 40,
                    offset: const Offset(12, 0),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: SafeArea(child: livePanel())),
                  // 竖 grab 贴右缘（对齐原型抽屉态拖拽柄）。
                  Positioned(
                    top: 18,
                    right: 7,
                    child: Container(
                      width: 5,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      // easeOutBack 滑入：越过终点再回弹（对齐原型 slideL 弹簧）。
      final slide = Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack));
      return SlideTransition(position: slide, child: child);
    },
  );
}
