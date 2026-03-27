import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';

/// 主题设置页面
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        centerTitle: true,
      ),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 当前主题提示
              _buildCurrentThemeCard(context, themeProvider),
              const SizedBox(height: 24),

              // 主题选择标题
              Text(
                '选择主题',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),

              // 主题选项卡片（自动布局）
              _buildThemeCards(context, themeProvider),
            ],
          );
        },
      ),
    );
  }

  /// 构建当前主题显示卡片
  Widget _buildCurrentThemeCard(BuildContext context, ThemeProvider provider) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                AppTheme.getThemeIcon(provider.themeMode),
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前主题',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppTheme.getThemeDisplayName(provider.themeMode),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
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

  /// 构建主题选择卡片（自动平衡布局）
  Widget _buildThemeCards(BuildContext context, ThemeProvider provider) {
    final themes = AppThemeMode.values;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据屏幕宽度和主题数量决定列数，实现自动平衡
        final themeCount = themes.length;
        int crossAxisCount;
        double childAspectRatio;

        if (constraints.maxWidth > 600) {
          // 大屏幕：4个主题显示为2x2布局
          crossAxisCount = 2;
          childAspectRatio = 1.2;
        } else {
          // 小屏幕：单列布局
          crossAxisCount = 1;
          childAspectRatio = 2.5;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: themeCount,
          itemBuilder: (context, index) {
            final mode = themes[index];
            final isSelected = provider.themeMode == mode;

            return _ThemePreviewCard(
              mode: mode,
              isSelected: isSelected,
              onTap: () => _selectTheme(context, provider, mode),
            );
          },
        );
      },
    );
  }

  /// 选择主题
  void _selectTheme(
    BuildContext context,
    ThemeProvider provider,
    AppThemeMode mode,
  ) async {
    await provider.setThemeMode(mode);

    if (context.mounted) {
      // 显示选择成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到${AppTheme.getThemeDisplayName(mode)}'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 主题预览卡片
class _ThemePreviewCard extends StatelessWidget {
  final AppThemeMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final previewTheme = AppTheme.getThemeData(mode);
    final colorScheme = previewTheme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: isSelected ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isSelected
              ? BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 主题图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  AppTheme.getThemeIcon(mode),
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // 主题名称
              Text(
                AppTheme.getThemeDisplayName(mode),
                style: previewTheme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),

              // 颜色预览点
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildColorDot(colorScheme.primary),
                  const SizedBox(width: 4),
                  _buildColorDot(colorScheme.secondary),
                  const SizedBox(width: 4),
                  _buildColorDot(colorScheme.tertiary),
                ],
              ),

              // 选中标记
              if (isSelected) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '当前使用',
                    style: previewTheme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 1),
      ),
    );
  }
}
