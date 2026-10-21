// lib/core/remotetype/rt_canvas_layouts_sheet.dart
//
// 画布布局选择面板：横屏 / 竖屏两组（布局与朝向绑定，两组相互隔离），
// 均渲染**持久化版本**（用户改过的内置布局在列表里就是改过的样子，与画布
// 实际渲染同源——配置隔离的展示面）。
//   · 仅当前朝向的组可点按切换；另一组置灰展示（旋转设备后即可用），
//     每条带 16:9 迷你画布缩略图（模块矩形 + 按钮点）+ 朝向徽标。
//   · 内置长按 → 「恢复出厂摆放」（改坏的内置布局可一键还原，不影响其他布局）。
//   · 自定义长按 → 重命名 / 删除（删除有确认）。
//   · 底部「新建自定义布局」→ 先选朝向（横屏 / 竖屏）再创建空画布
//     （无模块、无快捷键），画布页立即切到它（选了另一朝向则记为该侧激活）。
//
// 画布 view 在 _openLayoutsSheet 里 showModalBottomSheet 调用本件；本件
// 只负责「展示 + 收集意图」，持久化与状态切换由页面的回调接管。

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'rt_prefs.dart'
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
    this.scrollController,
  });

  final RtCanvasLayouts layouts;

  /// 当前朝向的激活布局 id（高亮用；另一侧激活不参与本面板）。
  final String activeId;

  /// 画布当前朝向（kRtCanvasOrient*）：决定哪一组可交互。
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

    // 纯内容：标题 + 分组列表 + 底部复制钮。外壳（底部上滑 / 左侧抽屉）
    // 由 [showRtCanvasLayoutsPanel] 按朝向装配。
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
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final p in entries)
                    _LayoutTile(
                      entry: p,
                      isActive: groupOrient == orientation && p.id == activeId,
                      interactive: groupOrient == orientation,
                      onTap: groupOrient == orientation
                          ? () => onSwitch(p.id)
                          : null,
                      onLongPress: p.builtIn
                          ? () => _confirmReset(context, p)
                          : () => _customActions(context, p),
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
                onPressed: () => _pickCopyOrientation(context),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('新建自定义布局'),
              ),
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

  // ---- 内置：长按恢复出厂 ----

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

  // ---- 自定义：长按 → 重命名 / 删除 ----

  Future<void> _customActions(
    BuildContext context,
    RtCanvasNamedLayout p,
  ) async {
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
    required this.entry,
    required this.isActive,
    required this.interactive,
    required this.onTap,
    required this.onLongPress,
  });

  final RtCanvasNamedLayout entry;
  final bool isActive;

  /// false = 另一朝向的组：置灰展示，点按不响应（旋转后可用）。
  final bool interactive;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final portrait = entry.orientation == kRtCanvasOrientPortrait;
    return Opacity(
      opacity: interactive ? 1.0 : 0.45,
      child: InkWell(
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
              SizedBox(width: 96, child: _LayoutThumb(data: entry.data)),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
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
              ),
              if (entry.builtIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
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

            // 轮盘缩略 = 圆形（画布端恒正方形渲染，取两轴较小者）。
            if (dpad != null && dpad.visible) {
              final fw = dpad.w ?? 0.22;
              final fh = dpad.h ?? 0.52;
              final side = math.min(fw * w, fh * h);
              moduleBoxes.add(
                Positioned(
                  left: (dpad.x * w - side / 2).clamp(0.0, w - side),
                  top: (dpad.y * h - side / 2).clamp(0.0, h - side),
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
  required ValueChanged<String> onSwitch,
  required ValueChanged<String> onCopy,
  required ValueChanged<String> onDelete,
  required void Function(String id, String name) onRename,
  required ValueChanged<String> onResetBuiltin,
}) {
  Widget content({ScrollController? scrollController}) => Builder(
    builder: (ctx) {
      // 面板开着时设备旋转：分组交互侧跟实时朝向走（画布朝向 = 设备
      // 朝向），不用打开时刻的快照。
      final liveOrientation =
          MediaQuery.orientationOf(ctx) == Orientation.landscape
          ? kRtCanvasOrientLandscape
          : kRtCanvasOrientPortrait;
      return RtCanvasLayoutsSheet(
        layouts: layouts,
        activeId: activeId,
        orientation: liveOrientation,
        scrollController: scrollController,
        onSwitch: onSwitch,
        onCopy: onCopy,
        onDelete: onDelete,
        onRename: onRename,
        onResetBuiltin: onResetBuiltin,
      );
    },
  );

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
                  Expanded(child: content(scrollController: controller)),
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
                  Positioned.fill(child: SafeArea(child: content())),
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
