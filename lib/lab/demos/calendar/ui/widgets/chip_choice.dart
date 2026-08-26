import 'package:flutter/material.dart';

import '../../../../../core/theme/paper_palette.dart';
import '../../../../../core/theme/typography.dart';

/// 通用 chip 选项组（平铺多选/单选）
///
/// 去塑料感：哑光奶白底 + 1px 边框 + 选中态边框强调（茶色），无 Elevation 阴影。
/// 中文 label 友好（自动处理 name.toUpperCase → 不强转大写）
class ChipChoice<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final T? selected;
  final ValueChanged<T> onChanged;
  final String Function(T) displayName;

  const ChipChoice({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(label, style: AppText.caption(color: pp.inkMuted)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((v) {
              final active = v == selected;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    // §0.1：表单选择 chip 选中态走 bgCard 浅主题色。
                    color: active ? pp.bgCard : pp.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? pp.accent : pp.line,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    displayName(v),
                    style: AppText.caption().copyWith(
                      fontSize: 12,
                      color: active ? pp.ink : pp.inkMuted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}