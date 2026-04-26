import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'timetable_cell.dart';
import 'timetable_editor_dialog.dart';
import 'timetable_colors.dart';
import '../service/config/timetable_settings_page.dart';
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
    // 默认定位到今天所在周期
    final config = ref.read(TimetableStore.configProvider);
    final todayIdx = config.todayCycleIndex;
    if (todayIdx != null) {
      _currentCycleIndex = todayIdx;
      // 让 PageView 一开始就显示该周期
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(todayIdx);
      });
    }
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
        await ref
            .read(TimetableStore.provider.notifier)
            .updateBackgroundImage(path);
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
                  await ref
                      .read(TimetableStore.provider.notifier)
                      .updateBackgroundImage(path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('移除背景图', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref
                    .read(TimetableStore.provider.notifier)
                    .updateBackgroundImage(null);
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
          '时间周期',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
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
                child: Stack(
                  children: [
                    PageView.builder(
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
                    // 右上角 - 回到今天按钮
                    if (config.todayCycleIndex != null &&
                        config.todayCycleIndex != _currentCycleIndex)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              config.todayCycleIndex!,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: TimetableColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: TimetableColors.accent.withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.today,
                                  size: 14,
                                  color: TimetableColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '今天',
                                  style: TextStyle(
                                    color: TimetableColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
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
                          TimetableMappers.formatDate(
                            config.startDateIso,
                            globalDayIndex,
                          ),
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
  Widget _buildTimetableGrid(
    ThemeData theme,
    TimetableConfig config,
    int cycleIndex,
  ) {
    // 使用 cycleGridProvider 获取课程（会根据 visibleInCycles 过滤）
    final cycleGrid = ref.watch(TimetableStore.cycleGridProvider(cycleIndex));

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
                  _SlotLabel(slotIndex: slotIndex, height: rowHeight),
                  // 课程网格列
                  ...List.generate(config.daysPerCycle, (dayOfCycle) {
                    final course = cycleGrid[dayOfCycle][slotIndex];
                    final cellKeyValue = '$cycleIndex-$dayOfCycle-$slotIndex';
                    final isSelected = _selectedCellKey == cellKeyValue;
                    final cellKey = 'd${dayOfCycle}_s$slotIndex';

                    return Expanded(
                      child: TimetableCell(
                        key: ValueKey(cellKeyValue),
                        state: isSelected
                            ? TimetableCellState.selected
                            : (course != null
                                  ? TimetableCellState.filled
                                  : TimetableCellState.empty),
                        course: course,
                        onTap: () => _handleCellTap(
                          cycleIndex,
                          dayOfCycle,
                          slotIndex,
                          course,
                        ),
                        onLongPress: () => _handleCellLongPress(
                          cycleIndex,
                          dayOfCycle,
                          slotIndex,
                          cellKey,
                        ),
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
  void _handleCellTap(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    CourseItem? course,
  ) {
    final cellKeyValue = _cellKey(cycleIndex, dayOfCycle, slotIndex);
    final cellKey = 'd${dayOfCycle}_s$slotIndex';
    final hasVisibleCourse = course != null;

    if (_selectedCellKey == cellKeyValue) {
      // 点击已选中的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, course);
      } else {
        // 空白 → 打开编辑器
        _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey);
      }
    } else {
      // 点击不同的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, course);
      } else {
        // 空白 → 选中当前单元格（进入+状态）
        setState(() => _selectedCellKey = cellKeyValue);
      }
    }
  }

  /// 显示课程预览抽屉
  void _showCoursePreview(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    CourseItem course,
  ) {
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
          final cellKey = 'd${dayOfCycle}_s$slotIndex';
          _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey, focusCourse: course);
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  /// 处理单元格长按
  void _handleCellLongPress(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    String cellKey,
  ) {
    // 长按直接打开编辑器
    _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey);
  }

  /// 打开编辑器（居中对话框）
  void _openEditor(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    String cellKey, {
    CourseItem? focusCourse,
  }) {
    // 从 store 获取该 cellKey 的所有课程
    final courses = ref.read(TimetableStore.cellProvider(cellKey));

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
        cellKey: cellKey,
        existingCourses: courses,
        focusCourse: focusCourse,
        onClose: () => Navigator.pop(context),
      ),
    );
  }
}

/// 左侧节数标签组件
class _SlotLabel extends StatelessWidget {
  const _SlotLabel({required this.slotIndex, required this.height});

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
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
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
                      Text(course.location!, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ],
                // 可见周期
                if (course.visibleInCycles != null &&
                    course.visibleInCycles!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: course.visibleInCycles!.map((cycle) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
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
                      side: BorderSide(
                        color: theme.colorScheme.outline,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.outline,
                    ),
                    label: Text(
                      '编辑',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
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
