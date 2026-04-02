import 'package:flutter/material.dart';

/// 周期可见性选择器
class CycleVisibilitySelector extends StatefulWidget {
  const CycleVisibilitySelector({
    super.key,
    required this.cycleCount,
    required this.selectedCycles,
    required this.onChanged,
  });

  final int cycleCount;
  final List<int> selectedCycles;
  final ValueChanged<List<int>> onChanged;

  @override
  State<CycleVisibilitySelector> createState() => _CycleVisibilitySelectorState();
}

class _CycleVisibilitySelectorState extends State<CycleVisibilitySelector> {
  bool _isAllMode = false;

  @override
  void initState() {
    super.initState();
    _isAllMode = widget.selectedCycles.isEmpty;
  }

  @override
  void didUpdateWidget(CycleVisibilitySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同步外部状态变化
    if (widget.selectedCycles.isEmpty != oldWidget.selectedCycles.isEmpty) {
      _isAllMode = widget.selectedCycles.isEmpty;
    }
  }

  void _selectAll() {
    setState(() => _isAllMode = true);
    widget.onChanged([]);
  }

  void _selectOddWeeks() {
    setState(() => _isAllMode = false);
    final oddCycles = List.generate(
      (widget.cycleCount / 2).ceil(),
      (i) => i * 2,
    ).where((c) => c < widget.cycleCount).toList();
    widget.onChanged(oddCycles);
  }

  void _selectEvenWeeks() {
    setState(() => _isAllMode = false);
    final evenCycles = List.generate(
      (widget.cycleCount / 2).floor(),
      (i) => i * 2 + 1,
    ).where((c) => c < widget.cycleCount).toList();
    widget.onChanged(evenCycles);
  }

  void _toggleCycle(int cycleIndex) {
    setState(() => _isAllMode = false);
    final newList = List<int>.from(widget.selectedCycles);
    if (newList.contains(cycleIndex)) {
      newList.remove(cycleIndex);
    } else {
      newList.add(cycleIndex);
      newList.sort();
    }
    widget.onChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Text(
              '显示周期',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // 四周边框强调状态标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.outline,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _isAllMode ? '全部周期' : '已选${widget.selectedCycles.length}个',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 快速操作按钮 - 四周边框
        Row(
          children: [
            Expanded(
              child: _QuickActionChip(
                label: '全部',
                isSelected: _isAllMode,
                onTap: _selectAll,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionChip(
                label: '单周',
                isSelected: !_isAllMode && _isOddCyclesOnly(),
                onTap: _selectOddWeeks,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionChip(
                label: '双周',
                isSelected: !_isAllMode && _isEvenCyclesOnly(),
                onTap: _selectEvenWeeks,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 周期选择网格 - 四周边框
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(widget.cycleCount, (index) {
              final cycleIndex = index;
              final isSelected = _isAllMode || widget.selectedCycles.contains(cycleIndex);
              return _CycleChip(
                label: '${cycleIndex + 1}',
                isSelected: isSelected,
                onTap: () => _toggleCycle(cycleIndex),
              );
            }),
          ),
        ),
      ],
    );
  }

  bool _isOddCyclesOnly() {
    if (widget.selectedCycles.isEmpty) return false;
    for (final cycle in widget.selectedCycles) {
      if (cycle % 2 == 0) return false;
    }
    return true;
  }

  bool _isEvenCyclesOnly() {
    if (widget.selectedCycles.isEmpty) return false;
    for (final cycle in widget.selectedCycles) {
      if (cycle % 2 == 1) return false;
    }
    return true;
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CycleChip extends StatelessWidget {
  const _CycleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
