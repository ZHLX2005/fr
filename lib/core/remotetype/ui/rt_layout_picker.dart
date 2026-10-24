// lib/core/remotetype/ui/rt_layout_picker.dart
//
// 布局切换抽屉：settings 钉选管理弹窗（pin_editor_sheet）同款浮卡抽屉，
// 主体从行列表换成方格网格。
//
// 竖屏页头与横屏左上角共用这一份：
//   · 主体 = 方格网格，按朝向分两段——竖屏布局在上、横屏布局在下。两组
//     都可点：当前朝向组点了就地切换，另一朝向组点了**只自动转屏过去**，
//     落点是那侧原本激活的布局——横竖两套布置互不覆盖；
//   · 右上角 = 「更多设置」入口——设置与配置相关的功能尽量收进那里
//     （布局改名/删除/新建、模块编排、发送换行、灵敏度、快捷键），
//     让抽屉只留「切布局」这一件事。
//
// 画布与写字页是同一张布局表的两种渲染形态（kind=canvas / kind=writer），
// 所以切换抽屉对两者通用。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/rt_prefs.dart';

// 视觉参数对齐 settings 钉选管理弹窗（screens/settings/const_settings.dart
// 的格子/弹窗两组常量）：两个抽屉一套观感。按模块自治各存一份，不跨模块引常量。
const double _kSheetRadius = 28.0;
const double _kSheetBarrierAlpha = 0.28;
const double _kSheetHeightFactor = 0.85;
const int _kCellCrossAxisCount = 4;
const double _kCellSpacing = 10.0;
const double _kCellAspectRatio = 1.0;
const double _kCellRadius = 16.0;
const double _kCellIconBoxSize = 36.0;
const double _kCellIconBoxRadius = 12.0;
const double _kCellIconSize = 18.0;
const double _kCellLabelSize = 10.0;

/// 打开布局切换抽屉。
///
/// [layouts] 当前布局集，[orientation] 当前朝向（该组格子高亮；另一组格子
/// 点击后由页面侧自动转屏过去），[activeId] 当前激活项（头部「当前」显示用），
/// [onPick] 选中回调（参数 = 布局 id 与所在分组朝向；抽屉先自行关闭），
/// [onOpenSettings] 右上角「更多设置」入口（可为 null → 不渲染该按钮）。
Future<void> showRtLayoutPicker(
  BuildContext context, {
  required RtCanvasLayouts layouts,
  required String orientation,
  required String activeId,
  required void Function(String id, String groupOrient) onPick,
  VoidCallback? onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: _kSheetBarrierAlpha),
    builder: (_) => _LayoutPickerSheet(
      layouts: layouts,
      orientation: orientation,
      activeId: activeId,
      onPick: onPick,
      onOpenSettings: onOpenSettings,
    ),
  );
}

class _LayoutPickerSheet extends StatelessWidget {
  const _LayoutPickerSheet({
    required this.layouts,
    required this.orientation,
    required this.activeId,
    required this.onPick,
    this.onOpenSettings,
  });

  final RtCanvasLayouts layouts;
  final String orientation;
  final String activeId;
  final void Function(String id, String groupOrient) onPick;
  final VoidCallback? onOpenSettings;

  // 两组都列出来、都可点：当前朝向组点了就地切换；另一朝向组点了只自动
  // 转屏过去，仍用那侧原本激活的布局（不改激活记录，页面侧 _switchLayout
  // 分流）。
  List<(String, List<RtCanvasNamedLayout>)> get _groups => [
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    // 高度公式同 pin_editor：目标占屏比 + 底部 inset 兜底（本抽屉无输入框，
    // 但写字页 composer 可能正拉着键盘，防极端横屏时被顶出屏幕）。
    final height = math.max(
      0.0,
      math.min(
        mq.size.height * _kSheetHeightFactor,
        mq.size.height - mq.viewInsets.bottom - 120,
      ),
    );
    // 空组不渲染段头（两组全空 → 居中空态）。
    final sections = [
      for (final (groupOrient, entries) in _groups)
        if (entries.isNotEmpty) (groupOrient, entries),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(_kSheetRadius),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 40,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
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
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: Row(
                      children: [
                        Text(
                          '切换布局',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (onOpenSettings != null)
                          _MoreSettingsPill(
                            // 选中即关抽屉再进设置页（与格子选中同一时序）。
                            onTap: () {
                              Navigator.of(context).pop();
                              onOpenSettings!();
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '当前：${_nameOf(layouts, orientation, activeId) ?? '—'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: sections.isEmpty
                        ? Center(
                            child: Text(
                              '暂无布局',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              for (final (groupOrient, entries) in sections) ...[
                                _GroupHeader(
                                  groupOrient: groupOrient,
                                  isCurrent: groupOrient == orientation,
                                ),
                                _GroupGrid(
                                  groupOrient: groupOrient,
                                  entries: entries,
                                  layouts: layouts,
                                  onPick: onPick,
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 段头：朝向标签；非当前朝向附「选择后自动转屏」提示。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.groupOrient, required this.isCurrent});

  final String groupOrient;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            groupOrient == kRtCanvasOrientPortrait ? '竖屏布局' : '横屏布局',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!isCurrent) ...[
            const SizedBox(width: 8),
            Text(
              '选择后自动转屏',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一段朝向的布局网格。
class _GroupGrid extends StatelessWidget {
  const _GroupGrid({
    required this.groupOrient,
    required this.entries,
    required this.layouts,
    required this.onPick,
  });

  final String groupOrient;
  final List<RtCanvasNamedLayout> entries;
  final RtCanvasLayouts layouts;
  final void Function(String id, String groupOrient) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _kCellCrossAxisCount,
        mainAxisSpacing: _kCellSpacing,
        crossAxisSpacing: _kCellSpacing,
        childAspectRatio: _kCellAspectRatio,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final p = entries[i];
        return _LayoutCell(
          key: ValueKey(p.id),
          entry: p,
          // 打勾 = 该朝向当前激活的布局（两组各标各的；另一组打勾的那格
          // 就是转屏过去会落到的布局）。
          isActive: p.id == (layouts.activeFor(groupOrient)?.id ?? ''),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop();
            onPick(p.id, groupOrient);
          },
        );
      },
    );
  }
}

/// 抽屉里的布局格子：图标 + 名字；激活 = 主题色描边 + 淡色底 + 右上角勾
/// （钉选管理弹窗格子的同一套约定）。图标按渲染形态区分：写字页键盘 /
/// 画布模块面板。
class _LayoutCell extends StatelessWidget {
  const _LayoutCell({
    super.key,
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  final RtCanvasNamedLayout entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isActive
          ? cs.primary.withValues(alpha: 0.10)
          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kCellRadius),
        side: BorderSide(
          color: isActive
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.4),
          width: isActive ? 1.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kCellRadius),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _kCellIconBoxSize,
                      height: _kCellIconBoxSize,
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(
                          _kCellIconBoxRadius,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          entry.kind == RtLayoutKind.writer
                              ? Icons.keyboard_alt_outlined
                              : Icons.dashboard_customize_outlined,
                          size: _kCellIconSize,
                          // 激活格子图标走 primary 强调（设置抽屉同款约定）。
                          color: isActive ? cs.primary : cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _kCellLabelSize,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isActive)
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: cs.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 右上角「更多设置」入口：布局编排/回车行为/快捷键都收在 RT 设置页。
class _MoreSettingsPill extends StatelessWidget {
  const _MoreSettingsPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(980),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '更多设置',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前激活布局的名字（查不到回 null）。
String? _nameOf(RtCanvasLayouts layouts, String orientation, String activeId) {
  for (final p in layouts.list) {
    if (p.id == activeId && rtCanvasLayoutUsableIn(orientation, p)) {
      return p.name;
    }
  }
  return null;
}
