// 比价计算器 —— 顶部主题 header 与底部汇总 footer
// 从 price_compare_demo.dart 抽出，让主文件保持在 400 行以下

import 'package:flutter/material.dart';

import 'price_compare_models.dart';

/// 顶部：图标 + 主题输入框 + 创建时间副标题 + 切换按钮
class PriceCompareHeader extends StatelessWidget {
  const PriceCompareHeader({
    super.key,
    required this.titleController,
    required this.createdAt,
    required this.onTitleChanged,
    required this.onSwitchTopic,
  });

  final TextEditingController titleController;
  final DateTime createdAt;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onSwitchTopic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(color: primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  onChanged: onTitleChanged,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '输入主题名称',
                    hintStyle: TextStyle(
                      color: primary.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '创建于 ${formatFullDate(createdAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: primary.withValues(alpha: 0.6),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '切换/管理主题',
            icon: Icon(Icons.swap_horiz_rounded, color: primary),
            onPressed: onSwitchTopic,
          ),
        ],
      ),
    );
  }
}

/// 底部：汇总提示 + border-emphasis 风格的"新增一行"按钮
class PriceCompareFooter extends StatelessWidget {
  const PriceCompareFooter({
    super.key,
    required this.validCount,
    required this.minPrice,
    required this.onAddRow,
  });

  final int validCount;
  final double? minPrice;
  final VoidCallback onAddRow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final String hint;
    if (validCount == 0 || minPrice == null) {
      hint = '输入至少一行「资源/金额」';
    } else {
      hint = '共 $validCount 行有效 · 最低单价 ¥${formatUnitPrice(minPrice!)}';
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: primary.withValues(alpha: 0.12)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.4)),
              ),
              child: TextButton.icon(
                onPressed: onAddRow,
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('新增一行'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
