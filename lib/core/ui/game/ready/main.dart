// lib/core/ui/game/ready/main.dart
// docs/prototypes/game-surfaces-palettes.html。
//
// 约束：
//   · 色全部走 ColorScheme（五主题自动跟）
//   · 无硬描边；双层软阴影分层
//   · CTA 胶囊化；主按钮用 primary / onPrimary（禁止写死 sage/clay）

import 'package:flutter/material.dart';

/// 房间就绪浮卡外壳（无边框）。
class GameReadyFloatCard extends StatelessWidget {
  const GameReadyFloatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 28, 24, 24),
    this.maxWidth = 440,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  /// 与 LobbyForm / 设置浮卡一致的双层阴影。
  static List<BoxShadow> floatShadows(ColorScheme scheme) => [
        BoxShadow(
          color: scheme.onSurface.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: scheme.onSurface.withValues(alpha: 0.07),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  static BoxDecoration decoration(ColorScheme scheme) => BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: floatShadows(scheme),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: decoration(scheme),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 房间号胶囊（primaryContainer，无描边）。
class GameReadyRoomCodeChip extends StatelessWidget {
  const GameReadyRoomCodeChip({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
          color: scheme.onPrimaryContainer,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 标题下的短分割条。
class GameReadyTitleRule extends StatelessWidget {
  const GameReadyTitleRule({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 2,
      decoration: BoxDecoration(
        color: scheme.outline.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 就绪态玩家行头像。
class GameReadyAvatar extends StatelessWidget {
  const GameReadyAvatar({
    super.key,
    required this.label,
    required this.isReady,
  });

  /// 未准备时显示的首字；已准备显示勾。
  final String label;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isReady
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        border: Border.all(
          color: isReady
              ? scheme.primary
              : scheme.outline.withValues(alpha: 0.45),
          width: isReady ? 2.2 : 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: isReady
          ? Icon(Icons.check_rounded, size: 22, color: scheme.primary)
          : Text(
              label.isNotEmpty ? label[0].toUpperCase() : '?',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// 已准备 / 未准备小徽章。
class GameReadyStatusBadge extends StatelessWidget {
  const GameReadyStatusBadge({super.key, required this.isReady});

  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isReady
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isReady ? '已准备 ✓' : '未准备',
        style: TextStyle(
          color: isReady
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 房间就绪底部 CTA 统一样式（胶囊）。
abstract final class GameReadyCtaStyle {
  static ButtonStyle filled(ColorScheme scheme) => FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        shape: const StadiumBorder(),
      );

  static ButtonStyle outlined(ColorScheme scheme) => OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        foregroundColor: scheme.primary,
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
        shape: const StadiumBorder(),
      );
}
