import 'package:flutter/material.dart';
import '../../lab/lab_container.dart';
import '../../lab/providers/lab_card_provider.dart';

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
class _DemoCard extends StatefulWidget {
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DemoCard({
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  State<_DemoCard> createState() => _DemoCardState();
}

class _DemoCardState extends State<_DemoCard> {
  final _provider = LabCardProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundUrl = _provider.getBackground(widget.title);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () => _showBackgroundDialog(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图片
            if (backgroundUrl != null && backgroundUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  backgroundUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: theme.colorScheme.surfaceVariant,
                    );
                  },
                ),
              ),
            // 渐变遮罩（确保文字可读）
            if (backgroundUrl != null && backgroundUrl.isNotEmpty)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
              ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.widgets,
                    color: backgroundUrl != null
                        ? Colors.white
                        : theme.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: backgroundUrl != null ? Colors.white : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      widget.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: backgroundUrl != null
                            ? Colors.white70
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 长按提示角标
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.image,
                size: 16,
                color: (backgroundUrl != null
                        ? Colors.white
                        : theme.colorScheme.outline)
                    .withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示背景设置对话框
  void _showBackgroundDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BackgroundSettingSheet(
        currentUrl: _provider.getBackground(widget.title),
        onImageSelected: (url) async {
          await _provider.setBackground(widget.title, url);
          if (context.mounted) Navigator.pop(context);
        },
        onRemove: () async {
          await _provider.removeBackground(widget.title);
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

/// 背景图片设置底部面板
class _BackgroundSettingSheet extends StatefulWidget {
  final String? currentUrl;
  final Future<void> Function(String) onImageSelected;
  final VoidCallback onRemove;

  const _BackgroundSettingSheet({
    required this.currentUrl,
    required this.onImageSelected,
    required this.onRemove,
  });

  @override
  State<_BackgroundSettingSheet> createState() => _BackgroundSettingSheetState();
}

class _BackgroundSettingSheetState extends State<_BackgroundSettingSheet> {
  String _customUrl = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.7,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              const Icon(Icons.image, size: 24),
              const SizedBox(width: 8),
              Text(
                '设置背景图片',
                style: theme.textTheme.titleLarge,
              ),
              const Spacer(),
              if (widget.currentUrl != null)
                TextButton.icon(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除'),
                ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 16),

          // 自定义 URL 输入
          Text(
            '自定义图片 URL',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/image.jpg',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) => _customUrl = value,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _isLoading || _customUrl.isEmpty
                    ? null
                    : () => _selectImage(_customUrl),
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 预设图片
          Text(
            '预设图片',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              itemCount: LabCardProvider.presetImages.length,
              itemBuilder: (context, index) {
                final url = LabCardProvider.presetImages[index];
                final isSelected = widget.currentUrl == url;

                return GestureDetector(
                  onTap: () => _selectImage(url),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                                color: theme.colorScheme.surfaceVariant,
                                child: const Icon(Icons.broken_image),
                              ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectImage(String url) async {
    setState(() => _isLoading = true);
    try {
      await widget.onImageSelected(url);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
