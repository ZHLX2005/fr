import 'package:flutter/material.dart';
import '../domain/models.dart';

/// 课程编辑底部弹窗
class CourseEditorBottomSheet extends StatefulWidget {
  const CourseEditorBottomSheet({
    super.key,
    required this.cellKey,
    this.existingCourse,
  });

  final String cellKey;
  final Course? existingCourse;

  static Future<CourseDraft?> show(
    BuildContext context, {
    required String cellKey,
    Course? existingCourse,
  }) {
    return showModalBottomSheet<CourseDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => CourseEditorBottomSheet(
        cellKey: cellKey,
        existingCourse: existingCourse,
      ),
    );
  }

  @override
  State<CourseEditorBottomSheet> createState() => _CourseEditorBottomSheetState();
}

class _CourseEditorBottomSheetState extends State<CourseEditorBottomSheet> {
  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _teacherController;
  late int _weekStart;
  late int _weekEnd;
  late WeekOddEven _oddEven;

  bool get _isEditing => widget.existingCourse != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingCourse?.title ?? '');
    _locationController = TextEditingController(text: widget.existingCourse?.location ?? '');
    _teacherController = TextEditingController(text: widget.existingCourse?.teacher ?? '');
    _weekStart = widget.existingCourse?.weekStart ?? 1;
    _weekEnd = widget.existingCourse?.weekEnd ?? 16;
    _oddEven = widget.existingCourse?.oddEven ?? WeekOddEven.all;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课程名称')),
      );
      return;
    }
    if (_weekEnd < _weekStart) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束周不能小于起始周')),
      );
      return;
    }

    final draft = CourseDraft(
      cellKey: widget.cellKey,
      title: _titleController.text.trim(),
      weekStart: _weekStart,
      weekEnd: _weekEnd,
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      teacher: _teacherController.text.trim().isEmpty ? null : _teacherController.text.trim(),
      colorSeed: widget.existingCourse?.colorSeed,
      oddEven: _oddEven,
    );

    Navigator.pop(context, draft);
  }

  void _delete() {
    Navigator.pop(context, CourseDraft.empty(widget.cellKey)..title = '__DELETE__');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏
              Row(
                children: [
                  Text(
                    _isEditing ? '编辑课程' : '添加课程',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 课程名称
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '课程名称 *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                autofocus: true,
              ),
              const SizedBox(height: 12),

              // 地点
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '上课地点',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // 教师
              TextField(
                controller: _teacherController,
                decoration: const InputDecoration(
                  labelText: '授课教师',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              // 周数配置
              Text('周数配置', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _WeekSelector(
                      label: '起始周',
                      value: _weekStart,
                      min: 1,
                      max: 20,
                      onChanged: (v) => setState(() => _weekStart = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _WeekSelector(
                      label: '结束周',
                      value: _weekEnd,
                      min: _weekStart,
                      max: 20,
                      onChanged: (v) => setState(() => _weekEnd = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 单双周
              SegmentedButton<WeekOddEven>(
                segments: WeekOddEven.values.map((e) => ButtonSegment(
                  value: e,
                  label: Text(e.label),
                )).toList(),
                selected: {_oddEven},
                onSelectionChanged: (v) => setState(() => _oddEven = v.first),
              ),
              const SizedBox(height: 24),

              // 保存按钮
              FilledButton(
                onPressed: _submit,
                child: Text(_isEditing ? '保存' : '添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: List.generate(max - min + 1, (i) => min + i)
                .map((v) => DropdownMenuItem(value: v, child: Text('第$v周')))
                .toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      ],
    );
  }
}
