import 'package:flutter/material.dart';
import '../data/local_timetable_repository.dart';
import '../domain/models.dart';
import 'timetable_cell.dart';
import 'timetable_controller.dart';
import 'course_editor_sheet.dart';
import 'timetable_settings_sheet.dart';

/// 课表页面
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late TimetableController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = TimetableController(LocalTimetableRepository());
    _init();
  }

  Future<void> _init() async {
    await _controller.init();
    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  String _cellKey(int col, int row) => 'c${col}_r$row';

  Future<void> _onCellTap(int col, int row) async {
    final cellKey = _cellKey(col, row);
    final existingCourse = _controller.getCourseAt(cellKey);

    final draft = await CourseEditorBottomSheet.show(
      context,
      cellKey: cellKey,
      existingCourse: existingCourse,
    );

    if (draft == null) return;

    // 检查是否是删除操作
    if (draft.title == '__DELETE__') {
      final result = await _controller.deleteCourse(cellKey);
      if (result.isOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('课程已删除')));
      }
      return;
    }

    // 保存课程
    final result = await _controller.saveDraft(draft);
    if (!result.isOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result.error as ValidationError).message)),
      );
    }
  }

  Future<void> _openSettings() async {
    final newConfig = await TimetableSettingsBottomSheet.show(
      context,
      currentConfig: _controller.state.config,
    );

    if (newConfig == null) return;

    final result = await _controller.updateConfig(newConfig.rows, newConfig.cols);
    if (mounted) {
      if (result.isOk) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存')));
      } else if (result.error is ValidationError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((result.error as ValidationError).message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final state = _controller.state;
    final config = state.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: '设置',
          ),
        ],
      ),
      body: Column(
        children: [
          // 表头（天数）
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const SizedBox(width: 40), // 角落留空
                ...List.generate(config.cols, (col) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        _getDayLabel(col),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 课表网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: config.cols,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.2,
              ),
              itemCount: config.cols * config.rows,
              itemBuilder: (context, index) {
                final col = index % config.cols;
                final row = index ~/ config.cols;
                final cellKey = _cellKey(col, row);
                final course = state.coursesByCell[cellKey];

                return TimetableCell(
                  cellKey: cellKey,
                  course: course,
                  onTap: () => _onCellTap(col, row),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getDayLabel(int col) {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日', '八', '九', '十', '十一', '十二', '十三', '十四'];
    return col < days.length ? days[col] : '第${col + 1}天';
  }
}
