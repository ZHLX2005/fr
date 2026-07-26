// 比价计算器 —— 单行 UI 组件（可复用 border-emphasis 风格）
// 从 price_compare_demo.dart 抽出，规避主文件 400+ 行的分文件门槛。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'price_compare_models.dart';

class PriceCompareRow extends StatelessWidget {
  const PriceCompareRow({
    super.key,
    required this.index,
    required this.unitPrice,
    required this.minPrice,
    required this.resourceController,
    required this.amountController,
    required this.onResourceChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final int index;
  final double? unitPrice;
  final double? minPrice;
  final TextEditingController resourceController;
  final TextEditingController amountController;
  final ValueChanged<String> onResourceChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMin =
        unitPrice != null && minPrice != null && unitPrice == minPrice;
    // 单价色：最低=绿；有效但非最低=主题色；无效=灰
    final Color tagColor;
    if (unitPrice == null) {
      tagColor = scheme.outline;
    } else if (isMin) {
      tagColor = const Color(0xFF16A34A); // 主操作绿：这行是"该买的"
    } else {
      tagColor = scheme.primary;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: tagColor.withValues(alpha: isMin ? 0.08 : 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tagColor.withValues(alpha: isMin ? 0.55 : 0.18),
            width: isMin ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            _seqBadge(tagColor),
            const SizedBox(width: 10),
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
            const SizedBox(width: 6),
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
            IconButton(
              iconSize: 20,
              tooltip: '删除本行',
              icon: Icon(
                Icons.close_rounded,
                color: scheme.outline.withValues(alpha: 0.7),
              ),
              onPressed: onRemove,
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
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        hintText: hint,
      ),
    );
  }
}
