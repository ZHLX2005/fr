import 'package:flutter/material.dart';

import '../../../../../core/theme/paper_palette.dart';
import '../../../../../core/theme/typography.dart';

/// 顶部视图切换 pill：0 弹层切换月/周/年/人/报表
class PillSegmented extends StatelessWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const PillSegmented({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PaperPalette.bgElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PaperPalette.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (i) {
          final active = i == selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? PaperPalette.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                items[i],
                style: AppText.caption().copyWith(
                  color: active ? PaperPalette.bg : PaperPalette.inkMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}