import 'package:flutter/material.dart';

import '../../../../../core/theme/paper_palette.dart';
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
    final child = icon == null
        ? Text(label, style: AppText.body().copyWith(
              color: PaperPalette.accent,
              fontWeight: FontWeight.w600,
            ))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: PaperPalette.accent),
              const SizedBox(width: 6),
              Text(label, style: AppText.body().copyWith(
                color: PaperPalette.accent,
                fontWeight: FontWeight.w600,
              )),
            ],
          );
    return Material(
      color: PaperPalette.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PaperPalette.accent, width: 1.5),
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

/// 纸张风格主操作按钮
///
/// 边框强调 + 茶色填充 + 卡片白文字，确保对比度足够。
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
    final child = icon == null
        ? Text(label, style: AppText.body().copyWith(
              color: PaperPalette.bg,
              fontWeight: FontWeight.w600,
            ))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: PaperPalette.bg),
              const SizedBox(width: 6),
              Text(label, style: AppText.body().copyWith(
                color: PaperPalette.bg,
                fontWeight: FontWeight.w600,
              )),
            ],
          );
    return Material(
      color: PaperPalette.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PaperPalette.accent, width: 1.5),
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