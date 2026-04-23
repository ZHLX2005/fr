import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timetable_store.dart';
import 'timetable_dsl_parser.dart';
import 'timetable_colors.dart';

/// 课程批量导入对话框
class TimetableImportDialog extends ConsumerStatefulWidget {
  const TimetableImportDialog({super.key});

  @override
  ConsumerState<TimetableImportDialog> createState() =>
      _TimetableImportDialogState();
}

class _TimetableImportDialogState extends ConsumerState<TimetableImportDialog> {
  final _controller = TextEditingController();
  DslParseResult? _preview;
  bool _showPreview = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _doPreview() {
    final config = ref.read(TimetableStore.configProvider);
    setState(() {
      _preview = parseDsl(_controller.text, defaultSlotCount: config.slotsPerDay);
      _showPreview = true;
    });
  }

  Future<void> _doImport() async {
    if (_preview == null || _preview!.courses.isEmpty) return;

    final store = ref.read(TimetableStore.provider.notifier);
    for (final course in _preview!.courses) {
      await store.upsertItem(course);
    }

    if (mounted) {
      Navigator.pop(context, _preview!.courses.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.upload_file, color: TimetableColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '课程批量导入',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // DSL 语法提示
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TimetableColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TimetableColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DSL 语法',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TimetableColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '课程名 @ 星期(1-7) 节次 [w周次] [位置] [教师]\n'
                    '例: 高等数学 @ 1 1-2 w1,3,5 教学楼A101 张老师\n'
                    '节次: 单节 "3" 或范围 "1-4"\n'
                    '周次: w1,3,5 = 第1、3、5周显示（不写=全部）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: TimetableColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            // 输入框
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _controller,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '粘贴 DSL 格式的课程数据...\n例:\n高等数学 @ 1 1-2 教学楼A101',
                    hintStyle: TextStyle(
                      color: TimetableColors.textTertiary.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            // 预览
            if (_showPreview && _preview != null) ...[
              Flexible(
                child: _buildPreview(theme),
              ),
            ],
            // 错误提示
            if (_preview != null && _preview!.errors.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _preview!.errors
                      .map((e) => Text(
                            e,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ))
                      .toList(),
                ),
              ),
            // 按钮
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _doPreview,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: TimetableColors.accent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('预览'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed:
                          (_preview != null && _preview!.courses.isNotEmpty)
                              ? _doImport
                              : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(
                          color: _preview != null && _preview!.courses.isNotEmpty
                              ? TimetableColors.accent
                              : TimetableColors.border,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _preview != null && _preview!.courses.isNotEmpty
                            ? '导入 ${_preview!.courses.length} 门课程'
                            : '导入',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _preview != null && _preview!.courses.isNotEmpty
                              ? TimetableColors.accent
                              : TimetableColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Flexible(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: const BoxConstraints(maxHeight: 160),
        decoration: BoxDecoration(
          color: TimetableColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TimetableColors.border),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(8),
          itemCount: _preview!.courses.length,
          itemBuilder: (context, index) {
            final course = _preview!.courses[index];
            final weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 20,
                    decoration: BoxDecoration(
                      color: TimetableColors.getCourseColor(course.colorSeed ?? 0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      course.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${weekdayNames[course.dayOfCycle]} 第${course.slotIndex + 1}节',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: TimetableColors.textSecondary,
                    ),
                  ),
                  if (course.visibleInCycles != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      'w${course.visibleInCycles!.map((i) => i + 1).join(",")}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: TimetableColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
