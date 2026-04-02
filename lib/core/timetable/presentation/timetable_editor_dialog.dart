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
    this.existingCourse,
    required this.onClose,
  });

  final int dayOfCycle;
  final int slotIndex;
  final int cycleIndex;
  final CourseItem? existingCourse;
  final VoidCallback onClose;

  @override
  ConsumerState<TimetableEditorDialog> createState() => _TimetableEditorDialogState();
}

class _TimetableEditorDialogState extends ConsumerState<TimetableEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _teacherController;
  late List<int> _selectedCycles;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingCourse?.title ?? '');
    _locationController = TextEditingController(text: widget.existingCourse?.location ?? '');
    _teacherController = TextEditingController(text: widget.existingCourse?.teacher ?? '');
    _selectedCycles = List<int>.from(widget.existingCourse?.visibleInCycles ?? []);
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

    final visibleInCycles = _selectedCycles.isEmpty ? null : _selectedCycles;

    final item = CourseItem(
      id: widget.existingCourse?.id ?? '${now}_${widget.dayOfCycle}_${widget.slotIndex}',
      dayOfCycle: widget.dayOfCycle,
      slotIndex: widget.slotIndex,
      title: _titleController.text.trim(),
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      teacher: _teacherController.text.trim().isEmpty ? null : _teacherController.text.trim(),
      colorSeed: widget.existingCourse?.colorSeed ?? now,
      version: (widget.existingCourse?.version ?? 0) + 1,
      visibleInCycles: visibleInCycles,
      createdAt: widget.existingCourse?.createdAt ?? now,
      updatedAt: now,
    );

    await store.upsertItem(item);
    widget.onClose();
  }

  Future<void> _delete() async {
    if (widget.existingCourse == null) return;

    final store = ref.read(TimetableStore.provider.notifier);
    await store.deleteItem(widget.existingCourse!.cellKey);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);
    final isEditing = widget.existingCourse != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Material(
        elevation: 8,
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surface,
          child: Container(
            width: 340,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: TimetableColors.border,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
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
                ),
                const Divider(height: 1),
                // Form
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel(label: '课程名称', required: true),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: '例如：高等数学',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                        textCapitalization: TextCapitalization.words,
                        autofocus: false,
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(label: '上课地点'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          hintText: '例如：教学楼A101',
                          prefixIcon: Icon(
                            Icons.location_on_outlined,
                            color: TimetableColors.accent,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(label: '授课教师'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _teacherController,
                        decoration: InputDecoration(
                          hintText: '例如：张老师',
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: TimetableColors.accent,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 24),
                      CycleVisibilitySelector(
                        cycleCount: config.cycleCount,
                        selectedCycles: _selectedCycles,
                        onChanged: (cycles) {
                          setState(() => _selectedCycles = cycles);
                        },
                      ),
                      const SizedBox(height: 24),
                      // 边框强调按钮
                      OutlinedButton(
                        onPressed: _submit,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: theme.colorScheme.outline,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
      );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    this.required = false,
  });

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
