import 'package:flutter/material.dart';
import '../../lab/lab_container.dart';

/// 实验室页面 - 开发者验证 Demo 入口
class LabPage extends StatelessWidget {
  const LabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final demos = demoRegistry.getAll();

    return Scaffold(
      appBar: AppBar(
        title: const Text('实验室'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showLabInfo(context),
          ),
        ],
      ),
      body: demos.isEmpty
          ? _buildEmptyState(theme)
          : _buildDemoGrid(context, demos, theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.science_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无可用 Demo',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请在 main.dart 中注册 Demo',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoGrid(
    BuildContext context,
    List<MapEntry<String, DemoPage>> demos,
    ThemeData theme,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: demos.length,
      itemBuilder: (context, index) {
        final demo = demos[index].value;
        return _DemoCard(
          title: demo.title,
          description: demo.description,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _DemoDetailPage(demo: demo),
              ),
            );
          },
        );
      },
    );
  }

  void _showLabInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [Icon(Icons.science), SizedBox(width: 8), Text('开发者实验室')],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这是一个用于验证和测试新功能的开发者工具。'),
            SizedBox(height: 12),
            Text('• 所有 Demo 页面独立运行'),
            Text('• 使用 IoC 容器管理'),
            Text('• 不会影响主应用'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// Demo 卡片组件
class _DemoCard extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DemoCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.widgets, color: theme.colorScheme.primary, size: 32),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo 详情页面
class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;

  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(demo.title)),
      body: demo.buildPage(context),
    );
  }
}
