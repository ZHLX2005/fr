import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data.dart';
import '../domain/models.dart';
import 'timetable_store.dart';

/// 简洁日历风格课表页面
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  late PageController _pageController;
  int _currentCycleIndex = 0;

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
          // 周期切换指示器
          _buildCycleIndicator(theme, config),
          const Divider(height: 1),
          // 星期标题行
          _buildWeekdayHeader(theme, config),
          // 课表网格（可左右滑动）
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentCycleIndex = index);
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

  /// 周期切换指示器
  Widget _buildCycleIndicator(ThemeData theme, TimetableConfig config) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentCycleIndex > 0
                ? () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    )
                : null,
          ),
          GestureDetector(
            onTap: () => _showCyclePicker(context, config),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                TimetableMappers.getCycleTitle(_currentCycleIndex, config.daysPerCycle),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentCycleIndex < config.cycleCount - 1
                ? () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  /// 星期标题行
  Widget _buildWeekdayHeader(ThemeData theme, TimetableConfig config) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 时间列占位
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Text(
              '时间',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          // 天数列
          Expanded(
            child: Row(
              children: List.generate(config.daysPerCycle, (dayOfCycle) {
                final dayIndex = TimetableMappers.cycleToDayIndex(
                  _currentCycleIndex,
                  dayOfCycle,
                  config.daysPerCycle,
                );
                return Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      TimetableMappers.formatDate(config.startDateIso, dayIndex),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
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

  /// 课表网格
  Widget _buildTimetableGrid(ThemeData theme, TimetableConfig config, int cycleIndex) {
    final grid = ref.watch(TimetableStore.cycleGridProvider(cycleIndex));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: config.slotsPerDay,
      itemBuilder: (context, slotIndex) {
        return Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Row(
            children: [
              // 时间列
              Container(
                width: 50,
                alignment: Alignment.center,
                child: Text(
                  '第${slotIndex + 1}节',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              // 课程网格列
              Expanded(
                child: Row(
                  children: List.generate(config.daysPerCycle, (dayOfCycle) {
                    final course = grid[dayOfCycle][slotIndex];
                    final dayIndex = TimetableMappers.cycleToDayIndex(
                      cycleIndex,
                      dayOfCycle,
                      config.daysPerCycle,
                    );

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _showEditor(context, dayIndex, slotIndex, course),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: course != null
                                ? const Color(0xFF6366F1)
                                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: course == null
                                ? Border.all(
                                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                                  )
                                : null,
                          ),
                          child: course != null
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        course.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (course.location != null && course.location!.isNotEmpty)
                                        Text(
                                          course.location!,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                )
                              : Icon(
                                  Icons.add,
                                  size: 16,
                                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                                ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示课程编辑器
  Future<void> _showEditor(
    BuildContext context,
    int dayIndex,
    int slotIndex,
    CourseItem? existingCourse,
  ) async {
    final result = await TimetableEditorSheet.show(
      context,
      ref,
      dayIndex: dayIndex,
      slotIndex: slotIndex,
      existingCourse: existingCourse,
    );
  }

  /// 显示周期选择器
  void _showCyclePicker(BuildContext context, TimetableConfig config) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择周期',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(config.cycleCount, (index) {
                return ActionChip(
                  label: Text(TimetableMappers.getCycleTitle(index, config.daysPerCycle)),
                  onPressed: () {
                    Navigator.pop(context);
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 课程编辑器底部弹窗
class TimetableEditorSheet {
  static Future<CourseItem?> show(
    BuildContext context,
    WidgetRef ref, {
    required int dayIndex,
    required int slotIndex,
    CourseItem? existingCourse,
  }) {
    final config = ref.read(TimetableStore.provider).config;

    return showModalBottomSheet<CourseItem?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditorContent(
        dayIndex: dayIndex,
        slotIndex: slotIndex,
        existingCourse: existingCourse,
        config: config,
      ),
    );
  }
}

class _EditorContent extends ConsumerStatefulWidget {
  const _EditorContent({
    required this.dayIndex,
    required this.slotIndex,
    this.existingCourse,
    required this.config,
  });

  final int dayIndex;
  final int slotIndex;
  final CourseItem? existingCourse;
  final TimetableConfig config;

  @override
  ConsumerState<_EditorContent> createState() => _EditorContentState();
}

class _EditorContentState extends ConsumerState<_EditorContent> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _teacherController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingCourse?.title ?? '');
    _locationController = TextEditingController(text: widget.existingCourse?.location ?? '');
    _teacherController = TextEditingController(text: widget.existingCourse?.teacher ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课程名称')),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final store = ref.read(TimetableStore.provider.notifier);

    final item = CourseItem(
      id: widget.existingCourse?.id ?? '${now}_${widget.dayIndex}_${widget.slotIndex}',
      dayIndex: widget.dayIndex,
      slotIndex: widget.slotIndex,
      title: _titleController.text.trim(),
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      teacher: _teacherController.text.trim().isEmpty ? null : _teacherController.text.trim(),
      colorSeed: widget.existingCourse?.colorSeed ?? now,
      version: (widget.existingCourse?.version ?? 0) + 1,
      createdAt: widget.existingCourse?.createdAt ?? now,
      updatedAt: now,
    );

    await store.upsertItem(item);
    if (context.mounted) {
      Navigator.pop(context, item);
    }
  }

  Future<void> _delete() async {
    if (widget.existingCourse == null) return;

    final store = ref.read(TimetableStore.provider.notifier);
    await store.deleteItem(widget.existingCourse!.cellKey);

    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayIndex = widget.dayIndex;
    final slotIndex = widget.slotIndex;

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  widget.existingCourse == null ? '添加课程' : '编辑课程',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  '${TimetableMappers.formatDate(widget.config.startDateIso, dayIndex)} 第${slotIndex + 1}节',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                if (widget.existingCourse != null)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: _delete,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '课程名称 *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: '上课地点',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _teacherController,
                  decoration: const InputDecoration(
                    labelText: '授课教师',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.existingCourse == null ? '添加' : '保存'),
                ),
              ],
            ),
          ),
        ],
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
