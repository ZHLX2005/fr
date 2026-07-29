import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/focus_provider.dart';
import 'focus_timer_page.dart';
import 'focus_stats_page.dart';
import '../timetable/timetable.dart';
import 'time_tools/const_time_pages.dart';
import '../../lab/lab_container.dart';
import '../../screens/profile/lab/demo_detail_page.dart';

/// 工具列表项：registry demo（按 slug 走 DemoDetailPage）；内部页（带 onTap）。
/// onTap 只在内部页使用；registry 项 onTap 由父级 build 中按 slug 派生。
class _ToolItem {
  _ToolItem._({
    required this.label,
    required this.icon,
    required this.color,
    this.slug,
    this.onTap,
  });
  factory _ToolItem.registry(String slug) {
    final meta = timePageMetaOf(slug);
    return _ToolItem._(
      label: meta.label,
      icon: meta.icon,
      color: meta.color,
      slug: slug,
    );
  }
  factory _ToolItem.internal({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return _ToolItem._(label: label, icon: icon, color: color, onTap: onTap);
  }
  final String label;
  final IconData icon;
  final Color color;
  final String? slug;
  final VoidCallback? onTap;
}

class FocusHomePage extends StatelessWidget {
  const FocusHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<FocusProvider>(
          builder: (context, fp, _) {
            if (fp.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            // 工具列表：registry 中的 timePage demo + 内部页（统计、课表）。
            // onTap 在 build 中按 slug 是否为 null 区分：null → 内部页直接 onTap；
            // 非 null → 走 _openDemo(slug)。
            final registrySlugs = demoRegistry
                .getAll()
                .filterByTimePage()
                .map((e) => e.key)
                .where(kTimePageMeta.containsKey)
                .toList();
            final registryMetas = registrySlugs
                .map((s) => (slug: s, meta: kTimePageMeta[s]!))
                .toList();
            final featured = registryMetas
                .where((m) => m.meta.featured)
                .toList();
            final grid = <_ToolItem>[
              for (final m
                  in registryMetas.where((m) => !m.meta.featured))
                _ToolItem.registry(m.slug),
              _ToolItem.internal(
                label: '数据统计',
                icon: Icons.bar_chart_outlined,
                color: const Color(0xFF8B9DC3),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FocusStatsPage(),
                  ),
                ),
              ),
              _ToolItem.internal(
                label: '时间课表',
                icon: Icons.calendar_month_outlined,
                color: const Color(0xFF6B9DFC),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TimetablePage(),
                  ),
                ),
              ),
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreeting(context),
                  const SizedBox(height: 32),
                  _buildTodayCard(
                    context,
                    fp,
                    onTap: () => _navigateToTimer(context),
                  ),
                  const SizedBox(height: 24),
                  if (featured.isNotEmpty) ...[
                    _FeaturedToolCard(
                      slug: featured.first.slug,
                      onTap: () =>
                          _openDemo(context, featured.first.slug),
                    ),
                    const SizedBox(height: 24),
                  ],
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: grid.length,
                    itemBuilder: (_, i) {
                      final item = grid[i];
                      final onTap = item.slug != null
                          ? () => _openDemo(context, item.slug!)
                          : item.onTap!;
                      return _ToolCard(item: item, onTap: onTap);
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

  void _openDemo(BuildContext context, String slug) {
    final demo = demoRegistry.getBySlug(slug);
    if (demo == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DemoDetailPage(demo: demo)),
    );
  }

  // 问候语 + 今日专注卡（沿用 sage 渐变 + 小时/分钟渲染）。
  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
            ? '早上好'
            : hour < 18
                ? '下午好'
                : '晚上好';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting，',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w300,
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '欢迎使用小豆子 ^.^ ？',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w400),
        ),
      ],
    );
  }

  Widget _buildTodayCard(
    BuildContext context,
    FocusProvider focusProvider, {
    required VoidCallback onTap,
  }) {
    final todayMinutes = focusProvider.getTodayMinutes();
    final hours = todayMinutes ~/ 60;
    final minutes = todayMinutes % 60;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB5C9A3), Color(0xFFD4E4C4)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB5C9A3).withValues(alpha: 0.25),
              offset: const Offset(0, 8),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日专注',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hours > 0
                      ? hours.toString()
                      : minutes.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w200,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    hours > 0
                        ? ' 小时 ${minutes.toString().padLeft(2, '0')} 分钟'
                        : ' 分钟',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w300,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '点击开始专注 →',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToTimer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FocusTimerPage()),
    );
  }
}

/// 精选宽卡（横跨整行）— 与现有 subject 卡风格一致。
/// 永远只渲染 featured meta（当前=clock）。
class _FeaturedToolCard extends StatelessWidget {
  const _FeaturedToolCard({required this.slug, required this.onTap});
  final String slug;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final meta = timePageMetaOf(slug);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              meta.color,
              meta.color.withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: meta.color.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(meta.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击进入',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具网格卡 — 与旧的 _buildActionButton 视觉风格一致（白底、轻强调色）。
class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.item, required this.onTap});
  final _ToolItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, color: item.color, size: 24),
            const SizedBox(height: 8),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                color: item.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
