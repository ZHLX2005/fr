// 应用设置：钉选快捷区（OS 通知栏快捷开关式编排）。
//
// 主页面只显示当前已钉的入口格子：点按打开、长按拖动排序，拖起时底部浮现
// 垃圾桶，拖入直接删除（拖拽手感对齐 ⋯ 溢出面板的 q 弹配置，见
// const_settings）。网格与垃圾桶交互见 pinned_grid.dart。
// 全量清单（tag 分组 + 搜索 + 点选钉/拔）收进右上「管理」拉起的圆角弹窗，
// 见 pin_editor_sheet.dart。通用项（主题 / 底栏容量）保留为底部一组卡片。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/remotetype/settings/rt_settings_page.dart';
import '../../core/theme/state/theme_provider.dart';
import '../../core/ui/shell/quick_nav_bottom_bar.dart';
import '../profile/theme/theme_page.dart';
import 'const_settings.dart';
import 'pin_editor_sheet.dart';
import 'pinned_grid.dart';

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  /// 有钉选格子正在被拖动（仅用于显隐屏幕底部垃圾桶 FAB）。
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pins = ref.watch(navPinsProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final entries = pins.pinIds
        .map(navEntryById)
        .whereType<NavEntry>()
        .toList();

    // 底部垃圾桶用页面级 Stack 浮层（不能走 Scaffold FAB 槽——
    // QuickNavBottomBar 是 MainScreen 层浮层，会盖在 FAB 之上）。
    // 位置：底栏 reserve 之上、右下角；横向宽扁投放条（几何见
    // const_settings），命中区比旧 48px 圆钮大数倍，拖到角落松手即删。
    return Stack(
      children: [
        Scaffold(
          // 页底 highest，卡面 surface —— 靠明度分层，不用投影。
          backgroundColor: cs.surfaceContainerHighest,
          // 底栏浮层：勿 SafeArea(bottom)，否则留白露出 Scaffold 色条。
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + QuickNavBottomBar.bodyBottomReserve(context),
              ),
              children: [
                _Header(onManage: () => showPinEditorSheet(context)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
                  child: Text(
                    '点按打开 · 长按拖动排序 · 拖到右下垃圾桶删除',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                PinnedGrid(
                  entries: entries,
                  visibleSlotCount: pins.visibleSlotCount,
                  onDraggingChanged: (v) {
                    if (_dragging == v) return;
                    setState(() => _dragging = v);
                  },
                ),
                _GeneralCard(
                  themeLabel: AppTheme.getThemeDisplayName(themeMode),
                  capacity: pins.capacity,
                  onCapacity: (c) =>
                      ref.read(navPinsProvider.notifier).setCapacity(c),
                ),
              ],
            ),
          ),
        ),
        if (_dragging)
          Positioned(
            right: 16,
            bottom: QuickNavBottomBar.bodyBottomReserve(context) + 12,
            child: _TrashFab(
              onAccept: (id) {
                HapticFeedback.heavyImpact();
                ref.read(navPinsProvider.notifier).removePin(id);
              },
            ),
          ),
      ],
    );
  }
}

/// 拖动中出现的删除投放条：横向宽扁矩形（图标 + 文案），比旧 48px 圆钮
/// 命中区大数倍，拖到右下角即可松手删除；候选悬停时染错色 + 微放大。
class _TrashFab extends StatelessWidget {
  const _TrashFab({required this.onAccept});

  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 投放条是页面级 Stack 浮层（在 Scaffold 之外），没有 Material 兜底的
    // DefaultTextStyle → 文案会落到 Flutter 的 fallback 样式（monospace +
    // 下划线），中文渲染成豆腐块。包一层透明 Material 拿回主题字体。
    return Material(
      type: MaterialType.transparency,
      child: DragTarget<String>(
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          final fg = hovering ? cs.onErrorContainer : cs.onSurfaceVariant;
          return AnimatedContainer(
            key: kSettingsTrashBarKey,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: kSettingsTrashBarWidth,
            height: kSettingsTrashBarHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: hovering ? cs.errorContainer : cs.surface,
              borderRadius: BorderRadius.circular(kSettingsTrashBarRadius),
              border: Border.all(
                color: hovering ? cs.error : cs.outlineVariant,
                width: hovering ? 1.5 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: AnimatedScale(
              scale: hovering ? kSettingsTrashBarHoverScale : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: kSettingsTrashBarIconSize,
                    color: fg,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '拖到这里删除',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: kSettingsTrashBarLabelSize,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '设置',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
          ),
          onPressed: onManage,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16),
              SizedBox(width: 6),
              Text('管理', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 通用项（非钉选目录内的系统设置）。
class _GeneralCard extends StatelessWidget {
  const _GeneralCard({
    required this.themeLabel,
    required this.capacity,
    required this.onCapacity,
  });

  final String themeLabel;
  final int capacity;
  final ValueChanged<int> onCapacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: cs.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('主题'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    themeLabel,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ThemePage()));
              },
            ),
            ListTile(
              title: const Text('底栏容量（含 ⋯）'),
              trailing: SegmentedButton<int>(
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return cs.onPrimary;
                    }
                    return cs.onSurfaceVariant;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return cs.primary;
                    }
                    return cs.surfaceContainerHighest;
                  }),
                ),
                segments: const [
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {capacity},
                onSelectionChanged: (s) => onCapacity(s.first),
              ),
            ),
            // 远程输入的设置落点：布局编排 / 发送换行 / 灵敏度 / 快捷键。
            // 不进常用功能列表——它是模块级设置，挂在设置里更合适。
            ListTile(
              leading: const Icon(Icons.keyboard_alt_outlined),
              title: const Text('远程输入'),
              subtitle: const Text('布局编排 · 回车行为 · 快捷键'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showRtSettingsPage(context),
            ),
          ],
        ),
      ),
    );
  }
}