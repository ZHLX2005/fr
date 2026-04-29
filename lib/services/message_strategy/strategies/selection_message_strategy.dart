import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/selection_message_data.dart';

/// Strategy for rendering Selection messages (multi-select options)
class SelectionMessageWidgetStrategy extends MessageWidgetStrategy<SelectionMessageData> {
  @override
  Widget build(BuildContext context, SelectionMessageData data) {
    return _SelectionMessageContent(data: data);
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

class _SelectionMessageContent extends StatefulWidget {
  final SelectionMessageData data;

  const _SelectionMessageContent({required this.data});

  @override
  State<_SelectionMessageContent> createState() => _SelectionMessageContentState();
}

class _SelectionMessageContentState extends State<_SelectionMessageContent> {
  final Set<String> _selectedIds = {};
  bool _isFixed = false;
  Set<String> _fixedIds = {};

  void _toggleSelection(String id) {
    if (_isFixed) return;

    if (widget.data.multiSelect) {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    } else {
      _selectedIds.clear();
      _selectedIds.add(id);
    }
    setState(() {});
  }

  void _handleConfirm() {
    if (_selectedIds.isNotEmpty) {
      setState(() {
        _fixedIds = Set.from(_selectedIds);
        _isFixed = true;
      });
    }
  }

  String _getSelectedLabels() {
    final labels = widget.data.options
        .where((o) => _fixedIds.contains(o.id))
        .map((o) => o.label)
        .toList();
    return labels.join('、');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Question text
          Text(
            widget.data.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),

          // Hint text
          Text(
            widget.data.multiSelect ? '可多选' : '单选',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),

          // Fixed display or options
          if (_isFixed)
            _buildFixedContent(theme)
          else
            _buildOptions(theme),

          if (!_isFixed) ...[
            const SizedBox(height: 12),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _selectedIds.clear(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _handleConfirm,
                  child: const Text('确认'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptions(ThemeData theme) {
    return Column(
      children: widget.data.options.map((option) {
        final isSelected = _selectedIds.contains(option.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _toggleSelection(option.id),
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
                    widget.data.multiSelect
                        ? (isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                        : (isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
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
      }).toList(),
    );
  }

  Widget _buildFixedContent(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getSelectedLabels(),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
