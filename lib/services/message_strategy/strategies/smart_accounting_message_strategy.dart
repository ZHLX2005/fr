import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/smart_accounting_message_data.dart';

/// Strategy for rendering Smart Accounting messages (AI-recognized expense with confirm/modify/ignore)
class SmartAccountingMessageWidgetStrategy
    extends MessageWidgetStrategy<SmartAccountingMessageData> {
  @override
  Widget build(BuildContext context, SmartAccountingMessageData data) {
    return _SmartAccountingContent(data: data);
  }

  @override
  SmartAccountingMessageData createMockData() => SmartAccountingMessageData(
        recognizedTime: '10:30',
        category: AccountingCategory.defaults[0],
        description: '午餐费用',
        amount: 35.5,
      );
}

class _SmartAccountingContent extends StatefulWidget {
  final SmartAccountingMessageData data;

  const _SmartAccountingContent({
    required this.data,
  });

  @override
  State<_SmartAccountingContent> createState() =>
      _SmartAccountingContentState();
}

class _SmartAccountingContentState extends State<_SmartAccountingContent> {
  bool _isConfirmed = false;
  late AccountingCategory _selectedCategory;
  late TextEditingController _descController;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.data.category;
    _descController = TextEditingController(text: widget.data.description);
    _amountController =
        TextEditingController(text: widget.data.amount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _showEditBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _EditBottomSheet(
          initialCategory: _selectedCategory,
          initialDesc: _descController.text,
          initialAmount: double.tryParse(_amountController.text) ?? 0,
          onSave: (category, desc, amount) {
            setState(() {
              _selectedCategory = category;
              _descController.text = desc;
              _amountController.text = amount.toStringAsFixed(2);
            });
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _handleConfirm() {
    setState(() => _isConfirmed = true);
  }

  void _handleIgnore() {
    // TODO: Remove from parent message list
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 元信息行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.data.aiTag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    Text(
                      widget.data.recognizedTime,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 核心信息行
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧：分类图标+名称 + 备注
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _selectedCategory.icon,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedCategory.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _descController.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // 右侧：金额
                    Text(
                      '¥ ${double.tryParse(_amountController.text)?.toStringAsFixed(2) ?? '0.00'}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 分割线
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),

          // 操作行
          Padding(
            padding: const EdgeInsets.all(12),
            child: _isConfirmed
                ? _buildConfirmedContent(theme)
                : _buildActionButtons(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedContent(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '已记账',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _handleConfirm,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            child: const Text('确认记账'),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _showEditBottomSheet,
          child: const Text('修改'),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: _handleIgnore,
          child: const Text('忽略'),
        ),
      ],
    );
  }
}

/// 编辑弹窗
class _EditBottomSheet extends StatefulWidget {
  final AccountingCategory initialCategory;
  final String initialDesc;
  final double initialAmount;
  final void Function(
      AccountingCategory category, String desc, double amount) onSave;

  const _EditBottomSheet({
    required this.initialCategory,
    required this.initialDesc,
    required this.initialAmount,
    required this.onSave,
  });

  @override
  State<_EditBottomSheet> createState() => _EditBottomSheetState();
}

class _EditBottomSheetState extends State<_EditBottomSheet> {
  late AccountingCategory _selectedCategory;
  late TextEditingController _descController;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _descController = TextEditingController(text: widget.initialDesc);
    _amountController =
        TextEditingController(text: widget.initialAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '修改记账信息',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // 分类选择
          Text(
            '分类',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AccountingCategory.defaults.map((cat) {
              final isSelected = cat.id == _selectedCategory.id;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cat.icon),
                    const SizedBox(width: 4),
                    Text(cat.name),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedCategory = cat);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // 金额输入
          Text(
            '金额',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '¥ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 备注输入
          Text(
            '备注',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descController,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final amount =
                        double.tryParse(_amountController.text) ?? 0;
                    widget.onSave(
                        _selectedCategory, _descController.text, amount);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}
