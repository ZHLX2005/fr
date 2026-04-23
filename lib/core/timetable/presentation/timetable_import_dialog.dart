import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'timetable_store.dart';
import '../service/timetable_dsl_parser.dart';
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

    return Stack(
      children: [
        // 半透明遮罩
        GestureDetector(
          onTap: () => Navigator.pop(context),
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
                    child: Row(
                      children: [
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.upload_file,
                                size: 16,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '批量导入',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: TimetableColors.textPrimary,
                                ),
                              ),
                            ],
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
                  // 输入区
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // DSL 语法提示
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: TimetableColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: TimetableColors.border),
                          ),
                          child: Text(
                            '课程名 @ 星期(1-7) 节次 [w周次] [位置] [教师]\n'
                            '例: 高等数学 @ 1 1-2 w1,3,5 教学楼A101',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: TimetableColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 输入框
                        TextField(
                          controller: _controller,
                          maxLines: 5,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            hintText: '粘贴 DSL 格式的课程数据...',
                            hintStyle: TextStyle(
                              color: TimetableColors.textTertiary,
                              fontSize: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 预览
                        if (_showPreview && _preview != null) ...[
                          SizedBox(
                            height: 100,
                            child: _buildPreview(theme),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // 错误
                        if (_preview != null && _preview!.errors.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              _preview!.errors.join('\n'),
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        // 按钮行
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _doPreview,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  side: BorderSide(color: TimetableColors.accent),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('预览'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton(
                                onPressed: (_preview != null && _preview!.courses.isNotEmpty)
                                    ? _doImport
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  side: BorderSide(
                                    color: _preview != null && _preview!.courses.isNotEmpty
                                        ? TimetableColors.accent
                                        : TimetableColors.border,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _preview != null && _preview!.courses.isNotEmpty
                                      ? '导入 ${_preview!.courses.length} 门'
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

  Widget _buildPreview(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: TimetableColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TimetableColors.border),
      ),
      child: ListView.builder(
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
                  height: 18,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${weekdayNames[course.dayOfCycle]}${course.slotIndex + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: TimetableColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
