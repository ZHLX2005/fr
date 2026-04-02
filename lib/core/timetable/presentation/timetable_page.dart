import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'timetable_cell.dart';
import 'timetable_editor_dialog.dart';

/// 简洁日历风格课表页面
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  late PageController _pageController;
  int _currentCycleIndex = 0;
  // 选中的单元格 key: 'c${cycleIndex}_d${dayOfCycle}_s${slotIndex}'
  String? _selectedCellKey;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1.0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 生成单元格唯一键
  String _cellKey(int cycleIndex, int dayOfCycle, int slotIndex) {
    return '$cycleIndex-$dayOfCycle-$slotIndex';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '时间课表',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimetableSettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 天数标题行
          _buildWeekdayHeader(theme, config),
          const Divider(height: 1),
          // 课表网格（可左右滑动）
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentCycleIndex = index;
                  _selectedCellKey = null; // 切换周期时清除选中
                });
              },
              itemCount: config.cycleCount,
              itemBuilder: (context, cycleIndex) {
                return _buildTimetableGrid(theme, config, cycleIndex);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 天数标题行 - 显示"第1天、第2天..."
  Widget _buildWeekdayHeader(ThemeData theme, TimetableConfig config) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 左上角 - 显示当前周期
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Text(
              '第${_currentCycleIndex + 1}周期',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
          // 天数列 - 只显示 daysPerCycle 列
          Expanded(
            child: Row(
              children: List.generate(config.daysPerCycle, (dayOfCycle) {
                final globalDayIndex = TimetableMappers.cycleToDayIndex(
                  _currentCycleIndex,
                  dayOfCycle,
                  config.daysPerCycle,
                );
                return Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '第${dayOfCycle + 1}天',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          TimetableMappers.formatDate(config.startDateIso, globalDayIndex),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 课表网格 - 使用 cycleGridProvider 获取课程（按周期过滤）
  Widget _buildTimetableGrid(ThemeData theme, TimetableConfig config, int cycleIndex) {
    // 使用 cycleGridProvider 获取课程（会根据 visibleInCycles 过滤）
    final cycleGrid = ref.watch(TimetableStore.cycleGridProvider(cycleIndex));
    // 获取原始课程数据（用于编辑）
    final allSlots = ref.watch(TimetableStore.allDaySlotsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每行高度：总高度平均分配
        final totalHeight = constraints.maxHeight;
        final rowHeight = totalHeight / config.slotsPerDay;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: config.slotsPerDay,
          itemBuilder: (context, slotIndex) {
            return SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  // 时间列
                  _SlotLabel(
                    slotIndex: slotIndex,
                    height: rowHeight,
                  ),
                  // 课程网格列
                  ...List.generate(config.daysPerCycle, (dayOfCycle) {
                    final course = cycleGrid[dayOfCycle][slotIndex];
                    final cellKeyValue = '$cycleIndex-$dayOfCycle-$slotIndex';
                    final isSelected = _selectedCellKey == cellKeyValue;
                    final originalCourse = allSlots[dayOfCycle]?[slotIndex];

                    return Expanded(
                      child: TimetableCell(
                        key: ValueKey(cellKeyValue),
                        state: isSelected
                            ? TimetableCellState.selected
                            : (course != null
                                ? TimetableCellState.filled
                                : TimetableCellState.empty),
                        course: course,
                        onTap: () => _handleCellTap(cycleIndex, dayOfCycle, slotIndex, originalCourse),
                        onLongPress: () => _handleCellLongPress(cycleIndex, dayOfCycle, slotIndex, originalCourse),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 处理单元格点击
  void _handleCellTap(int cycleIndex, int dayOfCycle, int slotIndex, CourseItem? originalCourse) {
    final cellKeyValue = _cellKey(cycleIndex, dayOfCycle, slotIndex);

    if (_selectedCellKey == cellKeyValue) {
      // 再次点击已选中的单元格 → 打开编辑器
      _openEditor(cycleIndex, dayOfCycle, slotIndex, originalCourse);
    } else if (_selectedCellKey == null) {
      // 检查是否有课程且在当前周期可见
      if (originalCourse != null && originalCourse.isVisibleInCycle(cycleIndex)) {
        // 有课程 → 直接打开编辑器
        _openEditor(cycleIndex, dayOfCycle, slotIndex, originalCourse);
      } else {
        // 空单元格 → 选中当前单元格
        setState(() => _selectedCellKey = cellKeyValue);
      }
    } else {
      // 有其他单元格选中 → 切换选中
      setState(() => _selectedCellKey = cellKeyValue);
    }
  }

  /// 处理单元格长按
  void _handleCellLongPress(int cycleIndex, int dayOfCycle, int slotIndex, CourseItem? originalCourse) {
    // 长按直接打开编辑器
    _openEditor(cycleIndex, dayOfCycle, slotIndex, originalCourse);
  }

  /// 打开编辑器（居中对话框）
  void _openEditor(int cycleIndex, int dayOfCycle, int slotIndex, CourseItem? originalCourse) {
    // 检查课程是否在指定周期可见
    final visibleCourse = originalCourse != null && originalCourse.isVisibleInCycle(cycleIndex)
        ? originalCourse
        : null;

    // 清除选中状态
    setState(() => _selectedCellKey = null);

    // 显示居中的对话框
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => TimetableEditorDialog(
        dayOfCycle: dayOfCycle,
        slotIndex: slotIndex,
        cycleIndex: cycleIndex,
        existingCourse: visibleCourse,
        onClose: () => Navigator.pop(context),
      ),
    );
  }
}

/// 设置页面
class TimetableSettingsPage extends ConsumerStatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  ConsumerState<TimetableSettingsPage> createState() => _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends ConsumerState<TimetableSettingsPage> {
  late final TextEditingController _startDateController;
  late int _cycleCount;
  late int _daysPerCycle;
  late int _slotsPerDay;

  @override
  void initState() {
    super.initState();
    final config = ref.read(TimetableStore.provider).config;
    _startDateController = TextEditingController(text: config.startDateIso);
    _cycleCount = config.cycleCount;
    _daysPerCycle = config.daysPerCycle;
    _slotsPerDay = config.slotsPerDay;
  }

  @override
  void dispose() {
    _startDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(TimetableStore.provider.notifier);
    final error = await store.updateConfig(
      startDateIso: _startDateController.text.trim(),
      cycleCount: _cycleCount,
      daysPerCycle: _daysPerCycle,
      slotsPerDay: _slotsPerDay,
    );

    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 起始日期
          TextField(
            controller: _startDateController,
            decoration: const InputDecoration(
              labelText: '起始日期',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_today),
            ),
            readOnly: true,
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_startDateController.text) ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
              );
              if (date != null) {
                setState(() {
                  _startDateController.text = date.toIso8601String().split('T')[0];
                });
              }
            },
          ),
          const SizedBox(height: 24),
          // 周期数
          _ConfigSlider(
            label: '周期数',
            value: _cycleCount.toDouble(),
            min: TimetableConfig.minCycles.toDouble(),
            max: TimetableConfig.maxCycles.toDouble(),
            divisions: TimetableConfig.maxCycles - TimetableConfig.minCycles,
            onChanged: (v) => setState(() => _cycleCount = v.round()),
          ),
          // 每周期天数
          _ConfigSlider(
            label: '每周期天数 (1-7)',
            value: _daysPerCycle.toDouble(),
            min: TimetableConfig.minDaysPerCycle.toDouble(),
            max: TimetableConfig.maxDaysPerCycle.toDouble(),
            divisions: TimetableConfig.maxDaysPerCycle - TimetableConfig.minDaysPerCycle,
            onChanged: (v) => setState(() => _daysPerCycle = v.round()),
          ),
          // 每天节数
          _ConfigSlider(
            label: '每天节数 (1-6)',
            value: _slotsPerDay.toDouble(),
            min: TimetableConfig.minSlotsPerDay.toDouble(),
            max: TimetableConfig.maxSlotsPerDay.toDouble(),
            divisions: TimetableConfig.maxSlotsPerDay - TimetableConfig.minSlotsPerDay,
            onChanged: (v) => setState(() => _slotsPerDay = v.round()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存设置'),
          ),
        ],
      ),
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              value.round().toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// 左侧节数标签组件
class _SlotLabel extends StatelessWidget {
  const _SlotLabel({
    required this.slotIndex,
    required this.height,
  });

  final int slotIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 数字
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${slotIndex + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 小圆点指示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => Container(
              width: 3,
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: i == slotIndex % 3
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
            )),
          ),
        ],
      ),
    );
  }
}
