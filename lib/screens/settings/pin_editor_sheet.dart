// 钉选管理弹窗：全量入口 · 按 tag 分组 · 搜索 · 点选即钉/拔。
//
// OS 通知栏快捷开关编辑器的编排：设置主页面只留已钉格子，
// 全量清单收进这个圆角弹窗。弹窗内只管钉与拔，排序在主页面长按拖动。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/ui/global/nav/main.dart';
import 'const_settings.dart';

/// 打开钉选管理弹窗（圆角 · 分组 · 搜索 · 点选钉/拔）。
Future<void> showPinEditorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: kSettingsSheetBarrierAlpha),
    builder: (_) => const _PinEditorSheet(),
  );
}

/// groupLabel 在 NavEntry 上，这里给分组单独一份（chips / 区头用）。
String _groupLabel(NavGroup g) => switch (g) {
  NavGroup.core => '核心',
  NavGroup.lab => '实验室',
  NavGroup.game => '游戏',
};

class _PinEditorSheet extends ConsumerStatefulWidget {
  const _PinEditorSheet();

  @override
  ConsumerState<_PinEditorSheet> createState() => _PinEditorSheetState();
}

class _PinEditorSheetState extends ConsumerState<_PinEditorSheet> {
  /// null = 全部分组。
  NavGroup? _filter;
  String _query = '';

  bool _match(NavEntry e) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.id.toLowerCase().contains(q) ||
        (e.subtitle?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final pins = ref.watch(navPinsProvider);
    // 键盘弹出时收窄弹窗高度，避免整体被顶出屏幕顶端；
    // 横屏 + 键盘时差值可能为负，clamp 到 0 防 BoxConstraints assert。
    final height = math.max(
      0.0,
      math.min(
        mq.size.height * kSettingsSheetHeightFactor,
        mq.size.height - mq.viewInsets.bottom - 120,
      ),
    );
    final groups = _filter == null ? NavGroup.values : [_filter!];

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(kSettingsSheetRadius),
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
                          '管理钉选',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          '已钉 ${pins.pinIds.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: Text(
                      '点选格子钉上 / 拔下；排序请在设置页长按拖动',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: '搜索入口',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(980),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        _FilterPill(
                          label: '全部',
                          selected: _filter == null,
                          onTap: () => setState(() => _filter = null),
                        ),
                        for (final g in NavGroup.values)
                          _FilterPill(
                            label: _groupLabel(g),
                            selected: _filter == g,
                            onTap: () => setState(() => _filter = g),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final sections = <Widget>[];
                        for (final g in groups) {
                          final entries = navEntriesInGroup(
                            g,
                          ).where(_match).toList(growable: false);
                          if (entries.isEmpty) continue;
                          sections
                            ..add(
                              _SectionHeader(group: g, total: entries.length),
                            )
                            ..add(
                              _SectionGrid(
                                entries: entries,
                                pinnedIds: pins.pinIds,
                              ),
                            );
                        }
                        if (sections.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 36,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '无匹配项',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: sections,
                        );
                      },
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

class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({required this.group, required this.total});

  final NavGroup group;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(navPinsProvider);
    final pinnedCount = navEntriesInGroup(
      group,
    ).where((e) => pins.pinIds.contains(e.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            _groupLabel(group),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(
            '已钉 $pinnedCount / $total',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionGrid extends ConsumerWidget {
  const _SectionGrid({required this.entries, required this.pinnedIds});

  final List<NavEntry> entries;
  final List<String> pinnedIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kSettingsCellCrossAxisCount,
        mainAxisSpacing: kSettingsCellSpacing,
        crossAxisSpacing: kSettingsCellSpacing,
        childAspectRatio: kSettingsCellAspectRatio,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return _EditorCell(
          key: ValueKey(e.id),
          entry: e,
          pinned: pinnedIds.contains(e.id),
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(navPinsProvider.notifier).togglePin(e.id);
          },
        );
      },
    );
  }
}

/// 弹窗里的全量入口格子：点选切换钉选态；已钉 = 主题色描边 + 角标。
class _EditorCell extends StatelessWidget {
  const _EditorCell({
    super.key,
    required this.entry,
    required this.pinned,
    required this.onTap,
  });

  final NavEntry entry;
  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: pinned
          ? cs.primary.withValues(alpha: 0.10)
          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSettingsCellRadius),
        side: BorderSide(
          color: pinned ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
          width: pinned ? 1.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kSettingsCellRadius),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: kSettingsCellIconBoxSize,
                      height: kSettingsCellIconBoxSize,
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(
                          kSettingsCellIconBoxRadius,
                        ),
                      ),
                      child: Center(
                        child: NavEntryIcon(
                          entry: entry,
                          size: kSettingsCellIconSize,
                          // 已钉格子图标走 primary 强调钉选态（⋯ 面板同款约定）
                          tint: pinned ? cs.primary : cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: kSettingsCellLabelSize,
                        fontWeight: pinned ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (pinned)
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? cs.onSurface
                : cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(980),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? cs.surface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
