import 'package:flutter/material.dart';

import '../../../../../core/theme/component/calendar/paper_palette.dart';
import '../../../../../core/theme/typography.dart';

/// 纸张风格副操作按钮（边框强调版）
///
/// 卡片白底 + 茶色边框 + 茶色文字，用于次要操作。
class PaperSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool dense;

  const PaperSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    final child = icon == null
        ? Text(label, style: AppText.body().copyWith(
              color: pp.accent,
              fontWeight: FontWeight.w600,
            ))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: pp.accent),
              const SizedBox(width: 6),
              Text(label, style: AppText.body().copyWith(
                color: pp.accent,
                fontWeight: FontWeight.w600,
              )),
            ],
          );
    return Material(
      color: pp.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: pp.accent, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: dense ? 40 : 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    );
  }
}

/// 纸张风格主操作按钮（边框强调式：浅tint底 + 茶色描边 + 茶色文字）
///
/// 取代纯色填充，遵循 border-emphasis 风格：浅色调底 + 彩色描边 + 彩色文字。
/// 不依赖 Material 3 primary，因此永远不会出现"纯色看不清"的情况。
class PaperPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool dense;

  const PaperPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    final accent = pp.accent;
    final child = icon == null
        ? Text(label, style: AppText.body().copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(label, style: AppText.body().copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              )),
            ],
          );
    return Material(
      color: pp.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: dense ? 40 : 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    );
  }
}