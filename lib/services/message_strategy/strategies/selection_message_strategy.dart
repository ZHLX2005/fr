import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/selection_message_data.dart';

/// Strategy for rendering Selection messages (multi-select options)
class SelectionMessageWidgetStrategy extends MessageWidgetStrategy<SelectionMessageData> {
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    // No resources to dispose
  }

  void _toggleSelection(String id, bool multiSelect) {
    if (multiSelect) {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    } else {
      _selectedIds.clear();
      _selectedIds.add(id);
    }
  }

  @override
  Widget build(BuildContext context, SelectionMessageData data) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Question text
          Text(
            data.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),

          // Hint text
          Text(
            data.multiSelect ? '可多选' : '单选',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),

          // Options
          ...data.options.map((option) {
            final isSelected = _selectedIds.contains(option.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _toggleSelection(option.id, data.multiSelect),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        data.multiSelect
                            ? (isSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank)
                            : (isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked),
                        size: 20,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          option.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isSelected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _selectedIds.clear();
                  // TODO: handle cancel
                },
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (_selectedIds.isNotEmpty) {
                    // TODO: handle confirm with selectedIds
                  }
                },
                child: const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  SelectionMessageData createMockData() => SelectionMessageData(
    question: '请选择您的选项：',
    options: const [
      SelectionOption(id: '1', label: '选项一'),
      SelectionOption(id: '2', label: '选项二'),
      SelectionOption(id: '3', label: '选项三'),
      SelectionOption(id: '4', label: '选项四'),
      SelectionOption(id: '5', label: '选项五'),
    ],
    multiSelect: true,
  );
}
