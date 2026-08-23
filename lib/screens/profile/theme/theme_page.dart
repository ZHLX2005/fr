import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';

/// 主题设置页面
///
/// v6.2 收敛后只剩茶禅主题，body 仅展示当前主题的静态预览卡片，
/// 保留 Scaffold + AppBar 骨架便于后续扩展新主题。
class ThemePage extends ConsumerWidget {
  const ThemePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeNotifierProvider);
    final themeData = AppTheme.getThemeData(currentMode);
    final scheme = themeData.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置'), centerTitle: true),
      body: Center(
        child: Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主题图标方块
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    AppTheme.getThemeIcon(currentMode),
                    color: scheme.onPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),

                // 主题名称
                Text(
                  AppTheme.getThemeDisplayName(currentMode),
                  style: themeData.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),

                // 主/环境/互补 3 色预览点
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ColorDot(scheme.primary),
                    const SizedBox(width: 8),
                    _ColorDot(scheme.secondary),
                    const SizedBox(width: 8),
                    _ColorDot(scheme.tertiary),
                  ],
                ),
              ],
            ),
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
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 1),
      ),
    );
  }
}
