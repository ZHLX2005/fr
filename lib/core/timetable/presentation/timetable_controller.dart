import '../data/timetable_repository.dart';
import '../domain/models.dart';

/// 课表状态
class TimetableState {
  const TimetableState({
    required this.config,
    required this.coursesByCell,
    this.isLoading = false,
    this.errorMessage,
  });

  final TimetableConfig config;
  final Map<String, Course> coursesByCell;
  final bool isLoading;
  final String? errorMessage;

  TimetableState copyWith({
    TimetableConfig? config,
    Map<String, Course>? coursesByCell,
    bool? isLoading,
    String? errorMessage,
  }) {
    return TimetableState(
      config: config ?? this.config,
      coursesByCell: coursesByCell ?? this.coursesByCell,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// 课表控制器
class TimetableController {
  TimetableController(this._repo);

  final TimetableRepository _repo;

  TimetableState _state = TimetableState(
    config: TimetableConfig.defaultConfig,
    coursesByCell: const {},
  );

  TimetableState get state => _state;

  /// 初始化加载数据
  Future<void> init() async {
    _state = _state.copyWith(isLoading: true);

    try {
      final config = await _repo.loadConfig();
      final courses = await _repo.listCourses();

      _state = TimetableState(
        config: config,
        coursesByCell: {for (final c in courses) c.cellKey: c},
        isLoading: false,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '加载失败: $e',
      );
    }
  }

  /// 验证草稿
  Result<void> validateDraft(CourseDraft draft) {
    if (draft.title.trim().isEmpty) {
      return Result.err(const ValidationError('课程名不能为空'));
    }
    if (draft.weekStart < 1) {
      return Result.err(const ValidationError('起始周不能小于1'));
    }
    if (draft.weekEnd < draft.weekStart) {
      return Result.err(const ValidationError('结束周不能小于起始周'));
    }
    if (draft.weekEnd > 20) {
      return Result.err(const ValidationError('结束周不能大于20'));
    }
    return Result.ok(null);
  }

  /// 保存课程草稿
  Future<Result<void>> saveDraft(CourseDraft draft) async {
    final v = validateDraft(draft);
    if (!v.isOk) {
      return Result.err(v.error!);
    }

    try {
      final existing = _state.coursesByCell[draft.cellKey];
      final now = DateTime.now().millisecondsSinceEpoch;

      final course = (existing == null)
          ? Course(
              id: _uuid(),
              cellKey: draft.cellKey,
              title: draft.title,
              weekStart: draft.weekStart,
              weekEnd: draft.weekEnd,
              colorSeed: draft.colorSeed ?? now,
              location: draft.location,
              teacher: draft.teacher,
              oddEven: draft.oddEven,
              version: 1,
              createdAt: now,
              updatedAt: now,
            )
          : existing.copyWith(
              title: draft.title,
              weekStart: draft.weekStart,
              weekEnd: draft.weekEnd,
              location: draft.location,
              teacher: draft.teacher,
              oddEven: draft.oddEven,
              version: existing.version + 1,
              updatedAt: now,
            );

      await _repo.upsertCourse(course);

      final newCoursesByCell = Map<String, Course>.from(_state.coursesByCell);
      newCoursesByCell[course.cellKey] = course;

      _state = _state.copyWith(coursesByCell: newCoursesByCell);
      return Result.ok(null);
    } catch (e) {
      return Result.err(StorageError('保存失败: $e'));
    }
  }

  /// 删除课程
  Future<Result<void>> deleteCourse(String cellKey) async {
    try {
      await _repo.deleteCourseByCell(cellKey);

      final newCoursesByCell = Map<String, Course>.from(_state.coursesByCell);
      newCoursesByCell.remove(cellKey);

      _state = _state.copyWith(coursesByCell: newCoursesByCell);
      return Result.ok(null);
    } catch (e) {
      return Result.err(StorageError('删除失败: $e'));
    }
  }

  /// 获取格子中的课程
  Course? getCourseAt(String cellKey) {
    return _state.coursesByCell[cellKey];
  }

  /// 更新配置
  Future<Result<void>> updateConfig(int rows, int cols) async {
    try {
      final config = _state.config.copyWith(rows: rows, cols: cols);
      await _repo.saveConfig(config);

      // 删除越界课程
      final deletedCount = await _repo.deleteOutOfBoundsCourses(rows: rows, cols: cols);

      // 重新加载课程
      final courses = await _repo.listCourses();
      final newCoursesByCell = {for (final c in courses) c.cellKey: c};

      _state = _state.copyWith(
        config: config,
        coursesByCell: newCoursesByCell,
      );

      if (deletedCount > 0) {
        return Result.err(ValidationError('已删除 $deletedCount 个越界课程'));
      }
      return Result.ok(null);
    } catch (e) {
      return Result.err(StorageError('设置保存失败: $e'));
    }
  }

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toString();
}
