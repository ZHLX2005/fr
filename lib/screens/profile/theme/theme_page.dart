import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../core/color/theme/app_theme.dart';

/// 主题设置页面
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置'), centerTitle: true),
      body: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return _ThemeGrid(currentMode: themeProvider.themeMode);
        },
      ),
    );
  }
}

/// 双列主题网格
class _ThemeGrid extends StatelessWidget {
  final AppThemeMode currentMode;

  const _ThemeGrid({required this.currentMode});

  @override
  Widget build(BuildContext context) {
    final themes = AppThemeMode.values;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: themes.length,
      itemBuilder: (context, index) {
        final mode = themes[index];
        final isSelected = currentMode == mode;

        return _ThemeCard(
          mode: mode,
          isSelected: isSelected,
          onTap: () => _selectTheme(context, mode),
        );
      },
    );
  }

  void _selectTheme(BuildContext context, AppThemeMode mode) async {
    final provider = context.read<ThemeProvider>();
    await provider.setThemeMode(mode);

    if (context.mounted) {
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

/// 主题卡片
class _ThemeCard extends StatelessWidget {
  final AppThemeMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = AppTheme.getThemeData(mode);
    final colorScheme = themeData.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: isSelected ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isSelected
              ? BorderSide(color: colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 主题图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(AppTheme.getThemeIcon(mode), color: Colors.white),
              ),
              const SizedBox(height: 10),

              // 主题名称
              Text(
                AppTheme.getThemeDisplayName(mode),
                style: themeData.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? colorScheme.primary : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              // 颜色预览点
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
