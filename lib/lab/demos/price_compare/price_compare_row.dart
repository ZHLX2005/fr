// 比价计算器 —— 单行 UI 组件（可复用 border-emphasis 风格）
// 两行布局：第一行「资源/金额 → 单价」，第二行「备注 · 创建时间 · 删除」

import 'package:flutter/material.dart';
import '../../../widgets/context_colors.dart';
import 'package:flutter/services.dart';

import 'price_compare_models.dart';

class PriceCompareRow extends StatelessWidget {
  PriceCompareRow({
    super.key,
    required this.index,
    required this.unitPrice,
    required this.minPrice,
    required this.createdAt,
    required this.resourceController,
    required this.amountController,
    required this.noteController,
    required this.onResourceChanged,
    required this.onAmountChanged,
    required this.onNoteChanged,
    required this.onRemove,
  });

  final int index;
  final double? unitPrice;
  final double? minPrice;
  final DateTime createdAt;
  final TextEditingController resourceController;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final ValueChanged<String> onResourceChanged;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors.scheme;
    final isMin =
        unitPrice != null && minPrice != null && unitPrice == minPrice;
    // 单价色：最低=绿；有效但非最低=主题色；无效=灰
    final Color tagColor;
    if (unitPrice == null) {
      tagColor = scheme.outline;
    } else if (isMin) {
      tagColor = Theme.of(context).colorScheme.primary; // 主操作绿：这行是"该买的"
    } else {
      tagColor = scheme.primary;
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: tagColor.withValues(alpha: isMin ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tagColor.withValues(alpha: isMin ? 0.55 : 0.18),
            width: isMin ? 1.4 : 1,
          ),
        ),
        padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- 第一行：序号 · 资源 / 金额 · 单价 ----
            Row(
              children: [
                _seqBadge(tagColor),
                SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: _NumField(
                    controller: resourceController,
                    hint: '资源',
                    onChanged: onResourceChanged,
                  ),
                ),
                Text('/', style: TextStyle(color: scheme.outline)),
                Expanded(
                  flex: 3,
                  child: _NumField(
                    controller: amountController,
                    hint: '金额',
                    onChanged: onAmountChanged,
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      unitPrice == null
                          ? '—'
                          : '¥${formatUnitPrice(unitPrice!)}',
                      style: TextStyle(
                        color: tagColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            // ---- 第二行：备注 · 创建时间 · 删除 ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 备注 icon（视觉提示，不占太多宽度）
                Icon(
                  Icons.sell_outlined,
                  size: 14,
                  color: scheme.outline.withValues(alpha: 0.7),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: noteController,
                    onChanged: onNoteChanged,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '备注：品牌 / 规格 / 渠道',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: scheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // 创建时间
                Text(
                  formatCreatedAt(createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.outline.withValues(alpha: 0.8),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // 删除
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    tooltip: '删除本行',
                    icon: Icon(
                      Icons.close_rounded,
                      color: scheme.outline.withValues(alpha: 0.7),
                    ),
                    onPressed: onRemove,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seqBadge(Color color) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        hintText: hint,
      ),
    );
  }
}
