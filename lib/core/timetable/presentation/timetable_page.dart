import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'timetable_cell.dart';
import 'timetable_editor_dialog.dart';
import 'timetable_colors.dart';
import '../../../widgets/image_picker_widget.dart';

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

  /// 选择背景图
  Future<void> _pickBackgroundImage() async {
    final config = ref.read(TimetableStore.provider).config;
    if (config.backgroundImagePath != null) {
      // 已有背景图，显示菜单
      _showBackgroundImageMenu();
    } else {
      // 无背景图，直接选择
      final path = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(),
        title: '选择背景图',
      );
      if (path != null) {
        await ref.read(TimetableStore.provider.notifier).updateBackgroundImage(path);
      }
    }
  }

  /// 显示背景图菜单
  void _showBackgroundImageMenu() {
    final pageContext = context;
    showModalBottomSheet(
      context: pageContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('更换背景图'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final path = await ImagePickerPage.navigate(
                  pageContext,
                  config: const ImagePickerConfig(),
                  title: '选择背景图',
                );
                if (path != null) {
                  await ref.read(TimetableStore.provider.notifier).updateBackgroundImage(path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('移除背景图', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(TimetableStore.provider.notifier).updateBackgroundImage(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: false,
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
            icon: const Icon(Icons.image_outlined),
            onPressed: _pickBackgroundImage,
            tooltip: '设置背景图',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimetableSettingsPage()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 背景图（固定不动）
          if (config.backgroundImagePath != null)
            Positioned.fill(
              child: Image.file(
                File(config.backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          // 课表内容层
          Column(
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
            width: 64,
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                '第${_currentCycleIndex + 1}周期',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: TimetableColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
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
                            color: TimetableColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          TimetableMappers.formatDate(config.startDateIso, globalDayIndex),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: TimetableColors.textTertiary,
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
    final hasVisibleCourse = originalCourse != null && originalCourse.isVisibleInCycle(cycleIndex);

    if (_selectedCellKey == cellKeyValue) {
      // 点击已选中的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, originalCourse);
      } else {
        // 空白 → 打开编辑器
        _openEditor(cycleIndex, dayOfCycle, slotIndex, originalCourse);
      }
    } else {
      // 点击不同的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, originalCourse);
      } else {
        // 空白 → 选中当前单元格（进入+状态）
        setState(() => _selectedCellKey = cellKeyValue);
      }
    }
  }

  /// 显示课程预览抽屉
  void _showCoursePreview(int cycleIndex, int dayOfCycle, int slotIndex, CourseItem course) {
    // 清除选中状态
    setState(() => _selectedCellKey = null);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _CoursePreviewSheet(
        course: course,
        cycleIndex: cycleIndex,
        dayOfCycle: dayOfCycle,
        slotIndex: slotIndex,
        onEdit: () {
          Navigator.pop(context); // 关闭抽屉
          _openEditor(cycleIndex, dayOfCycle, slotIndex, course);
        },
        onClose: () => Navigator.pop(context),
      ),
    );
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表设置'),
        backgroundColor: TimetableColors.surface,
        foregroundColor: TimetableColors.textPrimary,
      ),
      backgroundColor: TimetableColors.surfaceVariant,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 起始日期
          TextField(
            controller: _startDateController,
            style: const TextStyle(color: TimetableColors.textPrimary),
            decoration: InputDecoration(
              labelText: '起始日期',
              labelStyle: const TextStyle(color: TimetableColors.textSecondary),
              prefixIcon: const Icon(Icons.calendar_today, color: TimetableColors.accent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
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
          OutlinedButton.icon(
            onPressed: _save,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(
                color: TimetableColors.accent,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.save, color: TimetableColors.accent),
            label: const Text(
              '保存设置',
              style: TextStyle(
                color: TimetableColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
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
            Text(
              label,
              style: const TextStyle(
                color: TimetableColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: const Border(
                  left: BorderSide(
                    color: TimetableColors.textPrimary,
                    width: 3,
                  ),
                ),
                color: TimetableColors.selectedBg,
              ),
              child: Text(
                value.round().toString(),
                style: const TextStyle(
                  color: TimetableColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: TimetableColors.accent,
            inactiveTrackColor: TimetableColors.border,
            thumbColor: TimetableColors.accent,
            overlayColor: TimetableColors.accent.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
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

    return Container(
      width: 64,
      height: height - 8,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          '${slotIndex + 1}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: TimetableColors.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// 课程预览底部抽屉
class _CoursePreviewSheet extends StatelessWidget {
  const _CoursePreviewSheet({
    required this.course,
    required this.cycleIndex,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.onEdit,
    required this.onClose,
  });

  final CourseItem course;
  final int cycleIndex;
  final int dayOfCycle;
  final int slotIndex;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = TimetableColors.getCourseColor(course.colorSeed ?? 0);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: TimetableColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 内容区
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题和颜色标签
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '第${dayOfCycle + 1}天 · 第${slotIndex + 1}节',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: TimetableColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 地点
                if (course.location != null && course.location!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: TimetableColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        course.location!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
                // 可见周期
                if (course.visibleInCycles != null && course.visibleInCycles!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: course.visibleInCycles!.map((cycle) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: const Border(
                            left: BorderSide(
                              color: TimetableColors.textPrimary,
                              width: 2,
                            ),
                          ),
                          color: TimetableColors.selectedBg,
                        ),
                        child: Text(
                          '周期${cycle + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: TimetableColors.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // 编辑按钮
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.outline, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(Icons.edit_outlined, color: theme.colorScheme.outline),
                    label: Text('编辑课程', style: TextStyle(color: theme.colorScheme.outline)),
                  ),
                ),
              ],
            ),
          ),
          // 底部安全区
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
