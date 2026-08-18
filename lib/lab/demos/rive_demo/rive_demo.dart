import 'package:flutter/material.dart';

import '../../lab_container.dart';
import 'const_rive.dart';
import 'rive_data_bind_view.dart';
import 'rive_lab_view.dart';
import 'rive_pendulum_view.dart';

/// Rive 演示统一 Demo
///
/// 集中展示 Rive 三种典型用法：
/// 1. 摆钟（纯播放）
/// 2. 数据绑定（ViewModel 布尔属性双向同步）
/// 3. 实验室（点击 + 拖拽交互）
///
/// 通过 Tab 切换子模块，保留 [RiveDemoTab] slug 别名
/// 以兼容历史 fr:// 链接（rive-pendulum / rive-data-bind / demo-lab）。
class RiveDemoPage extends StatefulWidget {
  const RiveDemoPage({super.key});

  @override
  State<RiveDemoPage> createState() => _RiveDemoPageState();
}

class _RiveDemoPageState extends State<RiveDemoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: RiveDemoTab.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = RiveDemoTab.values;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.08),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rive 演示',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '统一展示 Rive 摆钟、ViewModel 数据绑定与交互实验室三种用法',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTabBar(theme, tabs),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      RivePendulumView(),
                      RiveDataBindView(),
                      RiveLabView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme, List<RiveDemoTab> tabs) {
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge,
        tabs: [for (final t in tabs) Tab(text: t.label)],
      ),
    );
  }
}

/// fr:// 路由注册入口
///
/// 主 slug = rive-demo；旧 slug（rive-pendulum / rive-data-bind / demo-lab）
/// 注册到同一 DemoPage 实例，避免历史链接 404。
class RiveDemo extends DemoPage {
  RiveDemo();

  @override
  String get title => 'Rive 演示';

  @override
  String get slug => 'rive-demo';

  @override
  String get description =>
      'Rive 摆钟 / 数据绑定 / 实验室 三合一演示';

  @override
  Widget buildPage(BuildContext context) => const RiveDemoPage();
}

/// 注册主 demo + 三个历史 slug 别名
void registerRiveDemo() {
  final demo = RiveDemo();
  // 主 slug
  demoRegistry.register(demo, key: RiveDemoSlugs.main);
  // 别名（同一实例，避免历史链接 404）
  demoRegistry.register(demo, key: RiveDemoSlugs.legacyPendulum);
  demoRegistry.register(demo, key: RiveDemoSlugs.legacyDataBind);
  demoRegistry.register(demo, key: RiveDemoSlugs.legacyLab);
}