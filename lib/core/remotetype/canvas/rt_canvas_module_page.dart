// lib/core/remotetype/canvas/rt_canvas_module_page.dart
//
// 模块设置页（设置页样式）：分区列表，逐行 = 图标 + 名称 + 说明 + 开关。
//   · 模块   —— 登记表（rt_canvas_modules）逐行开关「加入 / 移出当前布局」；
//               点行进入「编排」子面板：九宫格位置 + 三档尺寸 + 复位 + 移出。
//   · 布局   —— 当前布局名 / 切换与新建（转交布局面板）。
//   · 其他   —— 触摸板灵敏度 / 编辑快捷键 / 返回打字。
// 纯展示 + 收集意图：模块的可见性与锚点读写由画布层回调接管（沿用
// onLayoutChanged 落盘链路），本件不直接触碰持久化。

import 'package:flutter/material.dart';

import 'rt_canvas_modules.dart'
    show
        Offset2D,
        RtCanvasModuleSpec,
        kRtCanvasModuleSpecs,
        kRtCanvasSizeSteps,
        rtCanvasGridAnchor,
        rtCanvasModuleDefaults,
        rtCanvasModuleRange,
        rtCanvasModuleSpec,
        rtCanvasSizeStep;
import '../data/rt_prefs.dart' show RtCanvasAnchor;

/// 打开模块设置页（全屏路由，设置页观感）。
Future<void> showRtCanvasModulePage(
  BuildContext context, {
  required String layoutName,
  required bool connected,
  required bool Function(String id) visibleOf,
  required RtCanvasAnchor Function(String id) anchorOf,
  required void Function(String id, bool on) onToggleModule,
  required void Function(String id, RtCanvasAnchor anchor) onSetAnchor,
  required VoidCallback onOpenLayouts,
  required VoidCallback onSensitivity,
  required VoidCallback onEditShortcuts,
  required VoidCallback onExit,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      // 独立路由不随画布 setState 重绘：StatefulBuilder 让开关/位置改动
      // 即时回显（回调先落画布态——赋值是同步的——再 setPageState 重读）。
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPageState) {
          void afterChange(VoidCallback apply) {
            apply();
            setPageState(() {});
          }

          return Scaffold(
            appBar: AppBar(title: const Text('模块与布局'), centerTitle: false),
            body: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _SectionHeader('模块'),
                for (final spec in kRtCanvasModuleSpecs)
                  _ModuleTile(
                    spec: spec,
                    visible: visibleOf(spec.id),
                    anchorOf: anchorOf,
                    onToggle: (on) =>
                        afterChange(() => onToggleModule(spec.id, on)),
                    onArrange: () => _openArrangeSheet(
                      ctx,
                      specId: spec.id,
                      anchorOf: anchorOf,
                      onSetAnchor: (id, anchor) =>
                          afterChange(() => onSetAnchor(id, anchor)),
                      onRemove: () =>
                          afterChange(() => onToggleModule(spec.id, false)),
                    ),
                  ),
                _SectionHeader('布局'),
                ListTile(
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('切换布局'),
                  subtitle: Text('当前：$layoutName'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onOpenLayouts();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: const Text('新建自定义布局'),
                  subtitle: const Text('空画布起步，再回来逐项加模块'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onOpenLayouts();
                  },
                ),
                _SectionHeader('其他'),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('触摸板灵敏度'),
                  enabled: connected,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSensitivity();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text('编辑快捷键'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onEditShortcuts();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: const Text('返回打字'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onExit();
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.primary,
        ),
      ),
    );
  }
}

/// 一行模块：图标 + 名称/说明 + 编排入口 + 加入开关。
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.spec,
    required this.visible,
    required this.anchorOf,
    required this.onToggle,
    required this.onArrange,
  });

  final RtCanvasModuleSpec spec;
  final bool visible;
  final RtCanvasAnchor Function(String id) anchorOf;
  final ValueChanged<bool> onToggle;
  final VoidCallback onArrange;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        spec.icon,
        color: visible ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(spec.name),
      subtitle: Text(
        visible ? spec.desc : '${spec.desc} · 未加入',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onArrange,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chevron_right,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          Switch(value: visible, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// 编排子面板：九宫格位置 + 三档尺寸 + 复位 + 移出。
/// 锚点写入由画布层回调落盘（本件只算新锚点值）。
Future<void> _openArrangeSheet(
  BuildContext context, {
  required String specId,
  required RtCanvasAnchor Function(String id) anchorOf,
  required void Function(String id, RtCanvasAnchor anchor) onSetAnchor,
  required VoidCallback onRemove,
}) async {
  final spec = rtCanvasModuleSpec(specId);
  final name = spec?.name ?? specId;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final anchor = anchorOf(specId);
          final (wMin, wMax, hMin, hMax) = rtCanvasModuleRange(specId);
          final canResize = !(wMin == wMax && hMin == hMax);
          // 当前尺寸落在哪一档（用于高亮；都不接近则无高亮）。
          final (dw, dh) = rtCanvasModuleDefaults(specId);
          var currentStep = -1;
          for (var i = 0; i < kRtCanvasSizeSteps.length; i++) {
            final (sw, sh) = rtCanvasSizeStep(specId, i);
            final aw = anchor.w ?? dw;
            final ah = anchor.h ?? dh;
            if ((aw - sw).abs() < 0.02 && (ah - sh).abs() < 0.02) {
              currentStep = i;
              break;
            }
          }
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        spec?.icon ?? Icons.widgets_outlined,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (spec?.locksLandscape ?? false)
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
                            '仅横屏',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spec?.desc ?? '',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('位置', style: _labelStyle(cs)),
                  const SizedBox(height: 8),
                  _GridPicker(
                    anchor: anchor,
                    onPick: (pos) {
                      onSetAnchor(
                        specId,
                        RtCanvasAnchor(
                          visible: true,
                          x: pos.x,
                          y: pos.y,
                          w: anchor.w,
                          h: anchor.h,
                        ),
                      );
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  Text('尺寸', style: _labelStyle(cs)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < kRtCanvasSizeSteps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(const ['小', '标准', '大'][i]),
                          selected: i == currentStep,
                          onSelected: canResize
                              ? (_) {
                                  final (w, h) = rtCanvasSizeStep(specId, i);
                                  onSetAnchor(
                                    specId,
                                    RtCanvasAnchor(
                                      visible: true,
                                      x: anchor.x,
                                      y: anchor.y,
                                      w: w,
                                      h: h,
                                    ),
                                  );
                                  setSheetState(() {});
                                }
                              : null,
                        ),
                      ],
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _resetAnchor(specId, anchorOf, onSetAnchor),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('复位'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (anchor.visible)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              onRemove();
                              Navigator.of(ctx).pop();
                            },
                            icon: const Icon(
                              Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            label: const Text('移出当前布局'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

TextStyle _labelStyle(ColorScheme cs) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.5,
  color: cs.onSurfaceVariant,
);

/// 复位：回到该模块的缺省规格 + 九宫格中心位。
VoidCallback _resetAnchor(
  String specId,
  RtCanvasAnchor Function(String id) anchorOf,
  void Function(String id, RtCanvasAnchor anchor) onSetAnchor,
) {
  return () {
    final (w, h) = rtCanvasModuleDefaults(specId);
    onSetAnchor(
      specId,
      RtCanvasAnchor(visible: true, x: 0.5, y: 0.5, w: w, h: h),
    );
  };
}

/// 九宫格位置选择器：3×3 圆点按钮，当前位高亮。
class _GridPicker extends StatelessWidget {
  const _GridPicker({required this.anchor, required this.onPick});

  final RtCanvasAnchor anchor;
  final ValueChanged<Offset2D> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 当前锚点最接近哪一格（容差 0.12）。
    int hitCol = -1, hitRow = -1;
    for (var col = 0; col < 3; col++) {
      for (var row = 0; row < 3; row++) {
        final g = rtCanvasGridAnchor(col, row);
        if ((anchor.x - g.x).abs() < 0.12 && (anchor.y - g.y).abs() < 0.12) {
          hitCol = col;
          hitRow = row;
        }
      }
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: 2.4,
        child: Column(
          children: [
            for (var row = 0; row < 3; row++)
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < 3; col++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: InkWell(
                            onTap: () => onPick(rtCanvasGridAnchor(col, row)),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: (col == hitCol && row == hitRow)
                                    ? cs.primary
                                    : cs.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
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
