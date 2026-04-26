import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'cycle_visibility_selector.dart';
import 'timetable_colors.dart';

/// 居中课程编辑对话框
class TimetableEditorDialog extends ConsumerStatefulWidget {
  const TimetableEditorDialog({
    super.key,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.cycleIndex,
    required this.cellKey,
    required this.existingCourses,
    required this.onClose,
  });

  final int dayOfCycle;
  final int slotIndex;
  final int cycleIndex;
  final String cellKey;
  final List<CourseItem> existingCourses;
  final VoidCallback onClose;

  @override
  ConsumerState<TimetableEditorDialog> createState() =>
      _TimetableEditorDialogState();
}

class _TimetableEditorDialogState extends ConsumerState<TimetableEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _teacherController;
  late List<int> _selectedCycles;
  int _selectedCourseIndex = 0;

  CourseItem? get _currentCourse =>
      widget.existingCourses.isNotEmpty
          ? widget.existingCourses[_selectedCourseIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final course = _currentCourse;
    _titleController = TextEditingController(text: course?.title ?? '');
    _locationController = TextEditingController(text: course?.location ?? '');
    _teacherController = TextEditingController(text: course?.teacher ?? '');
    _selectedCycles = List<int>.from(course?.visibleInCycles ?? []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _switchToCourse(int index) {
    setState(() {
      _selectedCourseIndex = index;
      _initControllers();
    });
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入课程名称')));
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final store = ref.read(TimetableStore.provider.notifier);

    final visibleInCycles = _selectedCycles.isEmpty ? null : _selectedCycles;

    final item = CourseItem(
      id: _currentCourse?.id ?? '${now}_${widget.dayOfCycle}_${widget.slotIndex}',
      dayOfCycle: widget.dayOfCycle,
      slotIndex: widget.slotIndex,
      title: _titleController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      teacher: _teacherController.text.trim().isEmpty
          ? null
          : _teacherController.text.trim(),
      colorSeed: _currentCourse?.colorSeed ?? now,
      version: (_currentCourse?.version ?? 0) + 1,
      visibleInCycles: visibleInCycles,
      createdAt: _currentCourse?.createdAt ?? now,
      updatedAt: now,
    );

    // 获取当前列表并更新
    final currentList = List<CourseItem>.from(widget.existingCourses);
    final existingIndex = currentList.indexWhere((c) => c.id == item.id);
    if (existingIndex >= 0) {
      currentList[existingIndex] = item;
    } else {
      currentList.add(item);
    }

    await store.upsertItem(item);
    widget.onClose();
  }

  Future<void> _delete() async {
    if (_currentCourse == null) return;

    final store = ref.read(TimetableStore.provider.notifier);
    await store.deleteItem(widget.cellKey, itemId: _currentCourse!.id);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);
    final isEditing = _currentCourse != null;
    final hasMultipleCourses = widget.existingCourses.length > 1;

    return Stack(
      children: [
        // 半透明遮罩
        GestureDetector(
          onTap: widget.onClose,
          child: Container(color: Colors.black26),
        ),
        // 居中的对话框
        Center(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: Container(
              width: 340,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TimetableColors.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 边框强调标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outline,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isEditing ? '编辑课程' : '添加课程',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: TimetableColors.textPrimary,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // 边框强调 - 时间标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outline,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '第${widget.dayOfCycle + 1}天 · 第${widget.slotIndex + 1}节',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: TimetableColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isEditing)
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: theme.colorScheme.error,
                                  size: 22,
                                ),
                                onPressed: _delete,
                                tooltip: '删除课程',
                              ),
                          ],
                        ),
                        // 课程切换标签（当有多个课程时显示）
                        if (hasMultipleCourses) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 32,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.existingCourses.length,
                              itemBuilder: (context, index) {
                                final course = widget.existingCourses[index];
                                final isSelected = index == _selectedCourseIndex;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(
                                      course.title,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSelected
                                            ? Colors.white
                                            : TimetableColors.textPrimary,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (_) => _switchToCourse(index),
                                    selectedColor: theme.colorScheme.primary,
                                    backgroundColor:
                                        theme.colorScheme.surfaceContainerHighest,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Form
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: '课程名称 *',
                            hintText: '例如：高等数学',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          textCapitalization: TextCapitalization.words,
                          autofocus: false,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _locationController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: '地点',
                            hintText: '例如：教学楼A101',
                            prefixIcon: const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _teacherController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: '老师',
                            hintText: 'xx',
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        CycleVisibilitySelector(
                          cycleCount: config.cycleCount,
                          selectedCycles: _selectedCycles,
                          onChanged: (cycles) {
                            setState(() => _selectedCycles = cycles);
                          },
                        ),
                        const SizedBox(height: 16),
                        // 边框强调按钮
                        OutlinedButton(
                          onPressed: _submit,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                              color: theme.colorScheme.outline,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            isEditing ? '保存修改' : '添加课程',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
