import 'package:flutter/material.dart';

import '../../widgets/emphasis_button.dart';
import '../../native/overlay/pigment_overlay_service.dart';
import '../lab_container.dart';

class PigmentPaletteDemo extends DemoPage {
  @override
  String get title => '调色板';

  @override
  String get slug => 'pigment-palette';

  @override
  String get description => 'Flutter 只负责控制区，悬浮窗、取色和调色画板由 Kotlin 原生服务实现。';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const PigmentPaletteDemoPage();
  }
}

void registerPigmentPaletteDemo() {
  demoRegistry.register(PigmentPaletteDemo());
}

// 视觉基调：跟随全局主题（surface 底 / hairline outlineVariant 边 / 圆角卡片
// 无阴影），取色全部走 colorScheme，7 套主题 + 暗黑下自动成立。
// 动效：入场 scale+fade 与按压回弹都用 Curves.easeOutBack（过冲 ~10%），
// 与 main_screen 的「iOS q 弹感」同源；滚动沿用 BouncingScrollPhysics。

class PigmentPaletteDemoPage extends StatefulWidget {
  const PigmentPaletteDemoPage({super.key});

  @override
  State<PigmentPaletteDemoPage> createState() => _PigmentPaletteDemoPageState();
}

class _PigmentPaletteDemoPageState extends State<PigmentPaletteDemoPage>
    with WidgetsBindingObserver {
  final PigmentOverlayService _service = PigmentOverlayService();

  bool _hasPermission = false;
  bool _isActive = false;
  bool _isRefreshing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _init() async {
    await _service.init();
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _isRefreshing = true;
    });
    final hasPermission = await _service.checkOverlayPermission();
    final isActive = await _service.isShowing();
    if (!mounted) return;
    setState(() {
      _hasPermission = hasPermission;
      _isActive = isActive;
      _isRefreshing = false;
    });
  }

  Future<void> _requestPermission() async {
    await _service.requestOverlayPermission();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshStatus();
  }

  Future<void> _start() async {
    final success = await _service.start();
    await _refreshStatus();
    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动失败，请先确认悬浮窗权限已开启')));
    }
  }

  Future<void> _stop() async {
    await _service.stop();
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('调色板')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          onRefresh: _refreshStatus,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _SpringyEntrance(
                      delay: Duration.zero,
                      child: _HeroPanel(
                        hasPermission: _hasPermission,
                        isActive: _isActive,
                        isRefreshing: _isRefreshing,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SpringyEntrance(
                      delay: const Duration(milliseconds: 70),
                      child: _SectionCard(
                        title: '权限状态',
                        subtitle: '启动前只需要确认悬浮窗授权，页面返回前会自动刷新状态。',
                        child: Column(
                          children: [
                            _StatusRow(
                              icon: _hasPermission
                                  ? Icons.verified_rounded
                                  : Icons.shield_outlined,
                              title: '悬浮窗权限',
                              detail: _hasPermission ? '已授权' : '未授权',
                              tone: _hasPermission
                                  ? _StatusTone.success
                                  : _StatusTone.danger,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    label: '前往授权',
                                    icon: Icons.arrow_outward_rounded,
                                    onPressed: _requestPermission,
                                    prominence: _ButtonProminence.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ActionButton(
                                    label: '刷新状态',
                                    icon: Icons.refresh_rounded,
                                    onPressed: _refreshStatus,
                                    prominence: _ButtonProminence.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SpringyEntrance(
                      delay: const Duration(milliseconds: 140),
                      child: _SectionCard(
                        title: '画板控制',
                        subtitle: '悬浮层运行状态与启停入口都集中在这里。',
                        child: Column(
                          children: [
                            _StatusRow(
                              icon: _isActive
                                  ? Icons.water_drop_rounded
                                  : Icons.water_drop_outlined,
                              title: 'Pigment 悬浮层',
                              detail: _isActive ? '运行中' : '未启动',
                              tone: _isActive
                                  ? _StatusTone.accent
                                  : _StatusTone.neutral,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    label: '启动画板',
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: _hasPermission ? _start : null,
                                    prominence: _ButtonProminence.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ActionButton(
                                    label: '停止服务',
                                    icon: Icons.stop_rounded,
                                    onPressed: _isActive ? _stop : null,
                                    prominence: _ButtonProminence.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SpringyEntrance(
                      delay: const Duration(milliseconds: 210),
                      child: const _GroupedListCard(
                        title: '原生能力',
                        items: [
                          '56dp 悬浮气泡，支持拖拽和边缘吸附。',
                          '点击气泡后展开原生控制面板。',
                          '调色画板支持绘制、撤销、重做和清空。',
                          '取色模式可进入全屏采样覆盖层。',
                          '取色完成后会同步当前颜色和色板状态。',
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SpringyEntrance(
                      delay: const Duration(milliseconds: 280),
                      child: const _GroupedListCard(
                        title: '实现说明',
                        items: [
                          'Flutter 页面只负责状态展示、权限入口和启动控制。',
                          '悬浮窗、WindowManager overlay 和 MediaProjection 逻辑都在 Kotlin 原生服务层。',
                          '后续如果继续增强画板能力，建议仍沿用当前原生链路扩展。',
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SpringyEntrance(
                      delay: const Duration(milliseconds: 330),
                      child: Center(
                        child: Text(
                          '下拉可刷新状态',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════ 动效 ════════════════════════════════

/// 入场 q 弹：延迟后 scale(0.94→1) + fade，easeOutBack 过冲回弹。
/// scale 吃原始曲线值（保留过冲），opacity 单独 clamp。
class _SpringyEntrance extends StatefulWidget {
  const _SpringyEntrance({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_SpringyEntrance> createState() => _SpringyEntranceState();
}

class _SpringyEntranceState extends State<_SpringyEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutBack,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// 按压 q 弹：按下缩到 0.97，松手 easeOutBack 回弹。
/// 用 Listener 而不是 GestureDetector，不抢子级按钮的手势。
class _SpringyPress extends StatefulWidget {
  const _SpringyPress({required this.child});

  final Widget child;

  @override
  State<_SpringyPress> createState() => _SpringyPressState();
}

class _SpringyPressState extends State<_SpringyPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: Duration(milliseconds: _pressed ? 110 : 320),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// ════════════════════════════════ 卡片 ════════════════════════════════

/// 无阴影圆角卡片：surfaceContainerHighest 底 + hairline outlineVariant 边。
/// 与 AppCardDecorations.flat 同配方，[radius] 由调用方定（hero 24 / 区块 16）。
Container _flatCard(BuildContext context, double radius, Widget child,
    {EdgeInsets padding = const EdgeInsets.all(16)}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.hasPermission,
    required this.isActive,
    required this.isRefreshing,
  });

  final bool hasPermission;
  final bool isActive;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return _flatCard(
      context,
      24,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '调色板控制台',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '悬浮气泡、取色与画板都跑在原生层，这里集中管理权限与启停。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: hasPermission
                    ? Icons.verified_rounded
                    : Icons.shield_outlined,
                label: hasPermission ? '权限已开启' : '等待授权',
                tint: hasPermission
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.error,
              ),
              _MetricChip(
                icon: isActive
                    ? Icons.water_drop_rounded
                    : Icons.water_drop_outlined,
                label: isActive ? '画板运行中' : '画板未启动',
                tint: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              _MetricChip(
                icon: isRefreshing
                    ? Icons.sync_rounded
                    : Icons.check_circle_outline_rounded,
                label: isRefreshing ? '状态同步中' : '状态已同步',
                tint: isRefreshing
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.tertiary,
              ),
            ],
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _flatCard(
      context,
      16,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _GroupedListCard extends StatelessWidget {
  const _GroupedListCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return _flatCard(
      context,
      16,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
                indent: 16,
                endIndent: 16,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      items[index],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════ 状态行 / 徽章 ═══════════════════════════

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

enum _StatusTone { success, danger, accent, neutral }

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final _StatusTone tone;

  Color _tint(BuildContext context) {
    switch (tone) {
      case _StatusTone.success:
        return Theme.of(context).colorScheme.tertiary;
      case _StatusTone.danger:
        return Theme.of(context).colorScheme.error;
      case _StatusTone.accent:
        return Theme.of(context).colorScheme.primary;
      case _StatusTone.neutral:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint(context);
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // 图标底 = tint 低饱和；暗色提 alpha 保可见（与 EmphasisButton 同款分档）
        color: tint.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tint,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ 按钮 ═══════════════════════════════

enum _ButtonProminence { primary, secondary }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.prominence,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _ButtonProminence prominence;

  @override
  Widget build(BuildContext context) {
    final isPrimary = prominence == _ButtonProminence.primary;

    return _SpringyPress(
      child: SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          // 应用统一「边框强调」风格：主操作 primary 色、次操作中性色，
          // 浅色调底 + 彩色描边 + 彩色文字（暗色自动提 alpha）。
          style: EmphasisButton.borderEmphasis(
            context,
            color: isPrimary
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
