import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';

/// 主题设置页面
///
/// 展示当前所有主题的预览卡片，点选切换 + SnackBar 反馈。
/// 当前 2 套：zen（茶禅）、purple（暮紫）。
/// 保留 Scaffold + AppBar 骨架，新增主题时按 AppThemeMode.values 顺序自动出现。
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置'), centerTitle: true),
      body: _ThemeList(
        currentMode: currentMode,
        onSelect: (mode) => ref
            .read(themeNotifierProvider.notifier)
            .setMode(mode),
      ),
    );
  }
}

/// 主题列表（垂直堆叠；2-3 套主题体验最佳，多于 4 套可改 GridView 双列）
class _ThemeList extends StatelessWidget {
  final AppThemeMode currentMode;
  final void Function(AppThemeMode) onSelect;

  const _ThemeList({required this.currentMode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final modes = AppThemeMode.values;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: modes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final mode = modes[index];
        return _ThemeCard(
          mode: mode,
          isSelected: currentMode == mode,
          onTap: () => _selectTheme(context, mode, onSelect),
        );
      },
    );
  }

  void _selectTheme(
    BuildContext context,
    AppThemeMode mode,
    void Function(AppThemeMode) onSelect,
  ) {
    onSelect(mode);

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

/// 主题预览卡片
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
    final scheme = themeData.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: isSelected ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isSelected
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 主题图标方块
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  AppTheme.getThemeIcon(mode),
                  color: scheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // 名称 + 主/环境/互补 3 色预览点
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppTheme.getThemeDisplayName(mode),
                      style: themeData.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? scheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ColorDot(scheme.primary),
                        const SizedBox(width: 6),
                        _ColorDot(scheme.secondary),
                        const SizedBox(width: 6),
                        _ColorDot(scheme.tertiary),
                      ],
                    ),
                  ],
                ),
              ),

              // 选中勾（仅当前主题显示）
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: scheme.primary, size: 24),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 颜色预览点
class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 1),
      ),
    );
  }
}
