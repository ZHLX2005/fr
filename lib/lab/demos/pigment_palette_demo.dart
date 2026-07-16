import 'package:flutter/material.dart';

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

class PigmentPaletteDemoPage extends StatefulWidget {
  const PigmentPaletteDemoPage({super.key});

  @override
  State<PigmentPaletteDemoPage> createState() => _PigmentPaletteDemoPageState();
}

class _PigmentPaletteDemoPageState extends State<PigmentPaletteDemoPage>
    with WidgetsBindingObserver {
  static const _pageBackground = Color(0xFFF7F7F4);
  static const _surfaceColor = Colors.white;
  static const _softTextColor = Color(0xFF6B6B6B);
  static const _primaryTextColor = Color(0xFF111111);
  static const _accentColor = Color(0xFF1F7AFF);

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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Pigment 画板',
          style: TextStyle(
            color: _primaryTextColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: _accentColor,
          backgroundColor: _surfaceColor,
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
                    _HeroPanel(
                      hasPermission: _hasPermission,
                      isActive: _isActive,
                      isRefreshing: _isRefreshing,
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
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
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: '画板控制',
                      subtitle: '保留纯白控制面板，只在当前页面承载入口和运行反馈。',
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
                    const SizedBox(height: 14),
                    const _GroupedListCard(
                      title: '原生能力',
                      items: [
                        '56dp 悬浮气泡，支持拖拽和边缘吸附。',
                        '点击气泡后展开原生控制面板。',
                        '调色画板支持绘制、撤销、重做和清空。',
                        '取色模式可进入全屏采样覆盖层。',
                        '取色完成后会同步当前颜色和色板状态。',
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _GroupedListCard(
                      title: '实现说明',
                      items: [
                        'Flutter 页面只负责状态展示、权限入口和启动控制。',
                        '悬浮窗、WindowManager overlay 和 MediaProjection 逻辑都在 Kotlin 原生服务层。',
                        '后续如果继续增强画板能力，建议仍沿用当前原生链路扩展。',
                      ],
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        '下拉可刷新状态',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _softTextColor,
                          letterSpacing: 0.2,
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

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.hasPermission,
    required this.isActive,
    required this.isRefreshing,
  });

  final bool hasPermission;
  final bool isActive;
  final bool isRefreshing;

  static const _surfaceColor = Colors.white;
  static const _lineColor = Color(0xFFE7E7E3);
  static const _softTextColor = Color(0xFF6B6B6B);
  static const _primaryTextColor = Color(0xFF111111);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _lineColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '纯白控制区',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _primaryTextColor,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '保留现在的白色基调，用更轻的边界、清晰的分组和更克制的操作层级来贴近 iOS 风格。',
            style: TextStyle(fontSize: 14, height: 1.55, color: _softTextColor),
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
              ),
              _MetricChip(
                icon: isActive
                    ? Icons.water_drop_rounded
                    : Icons.water_drop_outlined,
                label: isActive ? '画板运行中' : '画板未启动',
              ),
              _MetricChip(
                icon: isRefreshing
                    ? Icons.sync_rounded
                    : Icons.check_circle_outline_rounded,
                label: isRefreshing ? '状态同步中' : '状态已同步',
              ),
            ],
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E7E3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111111),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFF6B6B6B),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E7E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111111),
                letterSpacing: -0.3,
              ),
            ),
          ),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFF0F0ED),
                indent: 18,
                endIndent: 18,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFCACAC5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      items[index],
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: Color(0xFF303030),
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

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE9E9E5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF303030)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF303030),
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

  Color get _tint {
    switch (tone) {
      case _StatusTone.success:
        return const Color(0xFF24A148);
      case _StatusTone.danger:
        return const Color(0xFFD93025);
      case _StatusTone.accent:
        return const Color(0xFF1F7AFF);
      case _StatusTone.neutral:
        return const Color(0xFF7A7A7A);
    }
  }

  Color get _softBackground {
    switch (tone) {
      case _StatusTone.success:
        return const Color(0xFFEFF9F1);
      case _StatusTone.danger:
        return const Color(0xFFFDEEEE);
      case _StatusTone.accent:
        return const Color(0xFFEEF5FF);
      case _StatusTone.neutral:
        return const Color(0xFFF3F3F1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDEDE8)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _softBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _tint, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 13,
                    color: _tint,
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

    return SizedBox(
      height: 52,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: isPrimary
              ? const Color(0xFF111111)
              : const Color(0xFFF3F3F1),
          foregroundColor: isPrimary ? Colors.white : const Color(0xFF111111),
          disabledBackgroundColor: const Color(0xFFE8E8E5),
          disabledForegroundColor: const Color(0xFF9A9A96),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
