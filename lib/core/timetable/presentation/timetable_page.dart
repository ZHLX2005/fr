import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/data.dart';
import '../domain/models.dart';
import 'timetable_store.dart';

/// 周期管理主页面 - 多页切换框架
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  final PageController _pageController = PageController(viewportFraction: 1.0);
  int _currentIndex = 0;

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
        title: Text(
          '周期管理',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TimetableSettingsPage(),
              ),
            ),
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: [
          // 页面指示器
          _buildPageIndicator(theme),
          const Divider(height: 1),
          // 多页内容
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemCount: 4, // Overview, Cycles, Days, Settings
              itemBuilder: (context, index) {
                switch (index) {
                  case 0:
                    return const _OverviewPage();
                  case 1:
                    return _CyclesPage();
                  case 2:
                    return const _DaysPage();
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(ThemeData theme) {
    final titles = ['总览', '周期', '天', '设置'];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          final isActive = index == _currentIndex;
          return GestureDetector(
            onTap: () => _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primaryContainer
                    : null,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                titles[index],
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isActive
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 总览页面
class _OverviewPage extends ConsumerWidget {
  const _OverviewPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summaries = ref.watch(TimetableStore.overviewProvider(0));
    final config = ref.watch(TimetableStore.configProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        itemCount: summaries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final summary = summaries[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${summary.cycleIndex + 1}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              title: Text(summary.title),
              trailing: Text(
                '${summary.courseCount} 门',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 周期列表页
class _CyclesPage extends ConsumerWidget {
  const _CyclesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(TimetableStore.configProvider);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: config.cycleCount,
      itemBuilder: (context, index) {
        return _CycleCard(cycleIndex: index);
      },
    );
  }
}

/// 周期卡片
class _CycleCard extends ConsumerWidget {
  const _CycleCard({required this.cycleIndex});

  final int cycleIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CycleDetailPage(cycleIndex: cycleIndex),
        ),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${cycleIndex + 1} 周期',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                TimetableMappers.getCycleTitle(cycleIndex, config.daysPerCycle),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${config.daysPerCycle}天 × ${config.slotsPerDay}节',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 周期详情页
class CycleDetailPage extends ConsumerWidget {
  const CycleDetailPage({required this.cycleIndex});

  final int cycleIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grid = ref.watch(TimetableStore.cycleGridProvider(cycleIndex));
    final config = ref.watch(TimetableStore.configProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${cycleIndex + 1} 周期'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: config.daysPerCycle,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.9,
          ),
          itemCount: config.daysPerCycle * config.slotsPerDay,
          itemBuilder: (context, index) {
            final dayOfCycle = index ~/ config.slotsPerDay;
            final slot = index % config.slotsPerDay;
            final course = grid[dayOfCycle][slot];
            final dayIndex = TimetableMappers.cycleToDayIndex(cycleIndex, dayOfCycle, config.daysPerCycle);

            return _CourseCell(
              dayIndex: dayIndex,
              slotIndex: slot,
              course: course,
              onTap: () => _showEditor(context, ref, dayIndex, slot, course),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, int dayIndex, int slot, CourseItem? course) async {
    await TimetableEditorSheet.show(
      context,
      ref,
      dayIndex: dayIndex,
      slotIndex: slot,
      existingCourse: course,
    );
  }
}

/// 天页面
class _DaysPage extends ConsumerWidget {
  const _DaysPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(TimetableStore.configProvider);
    final totalDays = config.totalDays;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: totalDays,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DayDetailPage(dayIndex: index),
            ),
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${index + 1} 天',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    TimetableMappers.formatDate(config.startDateIso, index),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '周 ${TimetableMappers.dayIndexToWeek(index)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 天详情页
class DayDetailPage extends ConsumerWidget {
  const DayDetailPage({required this.dayIndex});

  final int dayIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);
    final slots = ref.watch(TimetableStore.daySlotsProvider(dayIndex));

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${dayIndex + 1} 天'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: config.slotsPerDay,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return SizedBox(
            height: 80,
            child: _CourseCell(
              dayIndex: dayIndex,
              slotIndex: index,
              course: slots[index],
              onTap: () => _showEditor(context, ref, dayIndex, index, slots[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, WidgetRef ref, int dayIndex, int slot, CourseItem? course) async {
    await TimetableEditorSheet.show(
      context,
      ref,
      dayIndex: dayIndex,
      slotIndex: slot,
      existingCourse: course,
    );
  }
}

/// 课程单元格
class _CourseCell extends StatelessWidget {
  const _CourseCell({
    required this.dayIndex,
    required this.slotIndex,
    required this.course,
    required this.onTap,
  });

  final int dayIndex;
  final int slotIndex;
  final CourseItem? course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courseItem = course; // Local copy for null promotion

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: courseItem != null
              ? Color(0xFF6366F1)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: courseItem != null
                ? Colors.transparent
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: courseItem != null
            ? Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      courseItem.title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (courseItem.location != null && courseItem.location!.isNotEmpty)
                    const SizedBox(height: 2),
                  if (courseItem.location != null && courseItem.location!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 10, color: Colors.white70),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            courseItem.location!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            )
            : Center(
              child: Icon(
                Icons.add,
                size: 20,
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  widget.existingCourse == null ? '添加课程' : '编辑课程',
                  style: theme.textTheme.titleLarge,
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
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: '地点',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _teacherController,
                  decoration: const InputDecoration(
                    labelText: '教师',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                ],
            ),
          ),
          // Submit button
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _submit,
              child: Text(widget.existingCourse == null ? '添加' : '保存'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 起始日期
          ListTile(
            title: const Text('起始日期'),
            subtitle: Text(_startDateController.text),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(_startDateController.text),
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
          const Divider(),
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
            label: '每周期天数',
            value: _daysPerCycle.toDouble(),
            min: TimetableConfig.minDaysPerCycle.toDouble(),
            max: TimetableConfig.maxDaysPerCycle.toDouble(),
            divisions: TimetableConfig.maxDaysPerCycle - TimetableConfig.minDaysPerCycle,
            onChanged: (v) => setState(() => _daysPerCycle = v.round()),
          ),
          // 每天节数
          _ConfigSlider(
            label: '每天节数',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.round().toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
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
