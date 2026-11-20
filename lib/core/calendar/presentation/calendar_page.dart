import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/calendar_store.dart';
import '../../storage/hive/hive_calendar_store.dart';
import '../../storage/sqlite/sqlite.dart';
import '../domain/calendar_date_utils.dart';
import '../domain/calendar_task.dart';
import 'calendar_collapsible.dart';
import 'calendar_controls.dart';
import 'calendar_dialogs.dart';
import 'calendar_grid.dart';
import 'calendar_palette.dart';
import 'calendar_pickers.dart';
import 'calendar_settings_sheet.dart';
import 'calendar_task_list.dart';
import 'calendar_task_panel.dart';
import 'calendar_task_sheet.dart';
import 'calendar_view_menu.dart';
import 'calendar_view_mode.dart';
import 'calendar_year_view.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  static const _viewModeKey = 'calendar.viewMode';
  static const _showCompletedKey = 'calendar.showCompleted';
  static const _mondayFirstKey = 'calendar.mondayFirst';

  final DateTime _today = calendarDateOnly(DateTime.now());

  DateTime _selectedDate = calendarDateOnly(DateTime.now());
  DateTime _visibleMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  bool _expanded = true;
  CalendarViewMode _viewMode = CalendarViewMode.list;
  bool _showCompleted = true;
  bool _mondayFirst = true;

  /// 列表视图：任务面板高度进度（0 收起 / 1 展开）。**默认展开**——
  /// 进来主内容是当天任务，日历缩为后景。
  final ValueNotifier<double> _panelProgress = ValueNotifier<double>(1.0);

  bool _loading = true;
  List<CalendarTask> _tasks = const [];
  Set<String> _markedDates = const {};

  CalendarTaskRepository? _repo;
  KeyValueRepository? _settings;
  String? _storageError;

  int _loadToken = 0;

  CalendarPalette get _palette => CalendarPalette.of(context);

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindStorage());
  }

  @override
  void dispose() {
    _panelProgress.dispose();
    super.dispose();
  }

  Future<void> _bindStorage() async {
    final overrideRepo = ref.read(sqliteCalendarRepositoryProvider);
    if (overrideRepo != null) {
      _repo = overrideRepo;
      _settings = ref.read(sqliteSettingsRepositoryProvider);
    } else {
      await _openOwnedStorage();
    }

    await _loadPreferences();
    await _reload();
  }

  Future<void> _openOwnedStorage() async {
    if (_isMobilePlatform) {
      try {
        final storage = await SqliteStorage.open();
        _repo = storage.calendar;
        _settings = storage.settings;
        _storageError = null;
      } catch (error, stack) {
        debugPrint('[calendar] SQLite 打开失败: $error');
        debugPrint('$stack');
        // 手机端 SQLite 插件/数据库异常时，退回同一套领域契约的 Hive 缓存，
        // 至少保证日历可读写；错误保留用于诊断，不让整页停在“未启用”。
        try {
          final storage = await HiveCalendarStore.open();
          _repo = storage.calendar;
          _settings = storage.settings;
          _storageError = null;
          debugPrint('[calendar] 已切换到 Hive 本地缓存');
        } catch (fallbackError, fallbackStack) {
          _repo = null;
          _settings = null;
          _storageError = '$error';
          debugPrint('[calendar] Hive 兜底也失败: $fallbackError');
          debugPrint('$fallbackStack');
        }
      }
      return;
    }

    // Web / Windows / Linux 没有 sqflite 实现，走同一套领域契约的 Hive 缓存。
    try {
      final storage = await HiveCalendarStore.open();
      _repo = storage.calendar;
      _settings = storage.settings;
      _storageError = null;
    } catch (error, stack) {
      _repo = null;
      _settings = null;
      _storageError = '$error';
      debugPrint('[calendar] 本地缓存打开失败: $error');
      debugPrint('$stack');
    }
  }

  Future<void> _retryStorage() async {
    setState(() => _loading = true);
    await _openOwnedStorage();
    await _loadPreferences();
    await _reload();
  }

  Future<void> _loadPreferences() async {
    final settings = _settings;
    if (settings == null) return;

    final view = await settings.read(_viewModeKey);
    final showCompleted = await settings.read(_showCompletedKey);
    final mondayFirst = await settings.read(_mondayFirstKey);
    if (!mounted) return;

    var mode = CalendarViewMode.list;
    if (view != null) {
      for (final candidate in CalendarViewMode.values) {
        if (candidate.name == view) {
          mode = candidate;
          break;
        }
      }
    }

    setState(() {
      _viewMode = mode;
      _showCompleted = showCompleted == null ? true : showCompleted == 'true';
      _mondayFirst = mondayFirst == null ? true : mondayFirst == 'true';
    });
  }

  Future<void> _reload() async {
    final repo = _repo;
    if (!mounted) return;

    if (repo == null) {
      setState(() {
        _tasks = const [];
        _markedDates = const {};
        _loading = false;
      });
      return;
    }

    final token = ++_loadToken;
    setState(() => _loading = true);

    final range = _markedRange();
    try {
      final tasks = await repo.tasksOnDay(
        _selectedDate,
        includeCompleted: _showCompleted,
      );
      final marked = await repo.taskDateKeysBetween(
        range.$1,
        range.$2,
        includeCompleted: _showCompleted,
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _tasks = tasks;
        _markedDates = marked;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('[calendar] 加载任务失败: $error');
      debugPrint('$stack');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _tasks = const [];
        _markedDates = const {};
        _loading = false;
        _storageError = '$error';
      });
    }
  }

  (DateTime, DateTime) _markedRange() {
    switch (_viewMode) {
      case CalendarViewMode.year:
        return (
          DateTime(_selectedDate.year, 1, 1),
          DateTime(_selectedDate.year + 1, 1, 1),
        );
      case CalendarViewMode.month:
      case CalendarViewMode.list:
        final start = calendarMonthGridStart(
          _visibleMonth,
          mondayFirst: _mondayFirst,
        );
        return (start, start.add(const Duration(days: 42)));
      case CalendarViewMode.week:
        final start = calendarWeekStart(
          _selectedDate,
          mondayFirst: _mondayFirst,
        );
        return (start, start.add(const Duration(days: 7)));
      case CalendarViewMode.threeDay:
        final start = _selectedDate.subtract(const Duration(days: 1));
        return (start, start.add(const Duration(days: 3)));
      case CalendarViewMode.day:
        return (_selectedDate, _selectedDate.add(const Duration(days: 1)));
    }
  }

  void _selectDate(DateTime date) {
    final day = calendarDateOnly(date);
    setState(() {
      _selectedDate = day;
      _visibleMonth = DateTime(day.year, day.month, 1);
    });
    unawaited(_reload());
  }

  Future<void> _pickDate() async {
    final picked = await showCalendarDatePicker(
      context,
      palette: _palette,
      initialDate: _selectedDate,
    );
    if (picked != null) {
      _selectDate(picked);
    }
  }

  void _goToday() {
    _selectDate(_today);
    if (_viewMode == CalendarViewMode.list) {
      setState(() => _expanded = true);
    }
  }

  void _setViewMode(CalendarViewMode mode) {
    if (mode == _viewMode) return;
    setState(() {
      _viewMode = mode;
      if (mode == CalendarViewMode.list) {
        _expanded = true;
      }
      if (mode == CalendarViewMode.year) {
        _visibleMonth = DateTime(_selectedDate.year, 1, 1);
      }
    });
    unawaited(_persist(_viewModeKey, mode.name));
    unawaited(_reload());
  }

  void _onExpandedChanged(bool expanded) {
    if (!mounted) return;
    setState(() => _expanded = expanded);
  }

  void _onCalendarSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 80) return;
    HapticFeedback.selectionClick();

    final forward = velocity < 0;
    switch (_viewMode) {
      case CalendarViewMode.list:
      case CalendarViewMode.month:
        final targetMonth = DateTime(
          _visibleMonth.year,
          _visibleMonth.month + (forward ? 1 : -1),
          1,
        );
        final day = mathMin(
          _selectedDate.day,
          calendarDaysInMonth(targetMonth.year, targetMonth.month),
        );
        _selectDate(DateTime(targetMonth.year, targetMonth.month, day));
      case CalendarViewMode.week:
        _selectDate(
          _selectedDate.add(Duration(days: forward ? 7 : -7)),
        );
      case CalendarViewMode.threeDay:
        _selectDate(
          _selectedDate.add(Duration(days: forward ? 3 : -3)),
        );
      case CalendarViewMode.day:
        _selectDate(
          _selectedDate.add(Duration(days: forward ? 1 : -1)),
        );
      case CalendarViewMode.year:
        break;
    }
  }

  void _toggleExpanded() {
    if (_viewMode != CalendarViewMode.list) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  Future<void> _showViewMenu() async {
    final mode = await showCalendarViewMenu(
      context,
      current: _viewMode,
      palette: _palette,
    );
    if (mode != null) {
      _setViewMode(mode);
    }
  }

  Future<void> _showSettings() async {
    await showCalendarSettingsSheet(
      context,
      palette: _palette,
      viewMode: _viewMode,
      showCompleted: _showCompleted,
      mondayFirst: _mondayFirst,
      onViewModeChanged: _setViewMode,
      onShowCompletedChanged: (value) {
        setState(() => _showCompleted = value);
        unawaited(_persist(_showCompletedKey, value.toString()));
        unawaited(_reload());
      },
      onMondayFirstChanged: (value) {
        setState(() => _mondayFirst = value);
        unawaited(_persist(_mondayFirstKey, value.toString()));
        unawaited(_reload());
      },
      onGoToday: _goToday,
    );
  }

  Future<void> _addTask() async {
    if (_repo == null) {
      CalendarToast.show(
        context,
        _storageError ?? '本地数据库未就绪，请先重试',
        _palette,
      );
      return;
    }

    final draft = await showCalendarTaskSheet(
      context,
      palette: _palette,
      initialDate: _selectedDate,
    );
    if (draft == null) return;
    if (!mounted) return;

    try {
      await _repo!.create(draft);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      CalendarToast.show(context, '添加任务失败: $error', _palette);
    }
  }

  Future<void> _toggleTask(CalendarTask task) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.toggleCompleted(task);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      CalendarToast.show(context, '更新任务失败: $error', _palette);
    }
  }

  Future<void> _deleteTask(CalendarTask task) async {
    final repo = _repo;
    if (repo == null) return;

    final confirmed = await showCalendarConfirm(
      context,
      palette: _palette,
      title: '删除任务',
      message: '确定删除「${task.title}」吗？',
    );
    if (!confirmed || !mounted) return;

    try {
      await repo.delete(task.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      CalendarToast.show(context, '删除任务失败: $error', _palette);
    }
  }

  Future<void> _persist(String key, String value) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.write(key, value);
  }

  String _headerTitle() {
    final date = _selectedDate;
    final now = DateTime.now();
    switch (_viewMode) {
      case CalendarViewMode.year:
        return '${date.year}年';
      case CalendarViewMode.threeDay:
        return '${date.month}月${date.day}日';
      case CalendarViewMode.day:
        return date.year == now.year
            ? '${date.month}月'
            : '${date.year}年${date.month}月';
      case CalendarViewMode.list:
      case CalendarViewMode.month:
      case CalendarViewMode.week:
        return date.year == now.year
            ? '${date.month}月'
            : '${date.year}年${date.month}月';
    }
  }

  String _selectedDateLabel(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 · ${weekdays[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(palette),
            if (_viewMode == CalendarViewMode.year)
              Expanded(
                child: CalendarYearView(
                  year: _selectedDate.year,
                  selectedDate: _selectedDate,
                  markedDates: _markedDates,
                  mondayFirst: _mondayFirst,
                  palette: palette,
                  onDateSelected: (date) {
                    setState(() {
                      _selectedDate = calendarDateOnly(date);
                      _visibleMonth = DateTime(date.year, date.month, 1);
                      _viewMode = CalendarViewMode.month;
                    });
                    unawaited(_persist(_viewModeKey, _viewMode.name));
                    unawaited(_reload());
                  },
                  onYearChanged: (year) {
                    final days = calendarDaysInMonth(
                      year,
                      _selectedDate.month,
                    );
                    final next = DateTime(
                      year,
                      _selectedDate.month,
                      mathMin(_selectedDate.day, days),
                    );
                    setState(() {
                      _selectedDate = next;
                      _visibleMonth = DateTime(year, next.month, 1);
                    });
                    unawaited(_reload());
                  },
                ),
              )
            else ...[
              // 列表视图：日历在下层、任务面板覆盖在上（参考 Lab 容器下拉面板
              // 的层级关系）——面板浮起带圆角顶与把手，日历随之被轻推下沉，
              // 两个面板的主次一眼可读，而不是上下并列两半屏。
              if (_viewMode == CalendarViewMode.list)
                Expanded(
                  child: _buildListView(palette),
                )
              else ...[
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: _onCalendarSwipe,
                  child: _buildCalendarHeader(palette),
                ),
                if (_viewMode != CalendarViewMode.day)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _selectedDateLabel(_selectedDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: CalendarTaskList(
                    tasks: _tasks,
                    loading: _loading,
                    palette: palette,
                    storageAvailable: _repo != null,
                    storageMessage: _storageError,
                    onRetry: _retryStorage,
                    onToggle: _toggleTask,
                    onDelete: _deleteTask,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: _viewMode == CalendarViewMode.year
          ? null
          : ValueListenableBuilder<double>(
              valueListenable: _panelProgress,
              builder: (context, progress, _) {
                // 面板展开（前景主导）时加号按钮收起，不压任务内容。
                if (_viewMode == CalendarViewMode.list && progress > 0.5) {
                  return const SizedBox.shrink();
                }
                return GestureDetector(
                  onTap: _addTask,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.32),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child:
                        const Icon(Icons.add, size: 30, color: Colors.white),
                  ),
                );
              },
            ),
    );
  }

  /// 列表视图：日历在后景、任务面板浮在前景（覆盖关系，见 CalendarTaskPanel）。
  ///
  /// 面板**默认展开**——进来主内容就是当天任务，日历缩为后景（缩放 + 上移 +
  /// 压暗，随拖拽进度联动）；下拉把手才露出完整日历。与 Lab 容器下拉面板
  /// 同构的层级：面板在上、主内容在后、进度驱动两态。
  Widget _buildListView(CalendarPalette palette) {
    return Stack(
      children: [
        // 日历后景层：随面板进度缩小 + 上移 + 压暗（iOS sheet 的背景语义）。
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _panelProgress,
            builder: (context, progress, child) {
              final scale = 1.0 - 0.07 * progress;
              return Opacity(
                opacity: 1.0 - 0.35 * progress,
                child: Transform.translate(
                  offset: Offset(0, -14 * progress),
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _onCalendarSwipe,
              child: _buildCalendarHeader(palette),
            ),
          ),
        ),
        // 任务前景面板：浮在日历之上，默认展开。
        Positioned.fill(
          child: CalendarTaskPanel(
            palette: palette,
            progress: _panelProgress,
            headerLabel: _selectedDateLabel(_selectedDate),
            headerTrailing: Text(
              _tasks.isEmpty ? '暂无任务' : '${_tasks.length} 项',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
            child: CalendarTaskList(
              tasks: _tasks,
              loading: _loading,
              palette: palette,
              storageAvailable: _repo != null,
              storageMessage: _storageError,
              onRetry: _retryStorage,
              onToggle: _toggleTask,
              onDelete: _deleteTask,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(CalendarPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickDate,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _headerTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.6,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: palette.textSecondary.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
          CalendarIconButton(
            icon: calendarViewModeIcon(_viewMode),
            palette: palette,
            tooltip: '视图',
            onTap: _showViewMenu,
          ),
          CalendarIconButton(
            icon: Icons.more_horiz,
            palette: palette,
            tooltip: '日历设置',
            onTap: _showSettings,
          ),
          if (_viewMode == CalendarViewMode.list)
            CalendarIconButton(
              icon: _expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              palette: palette,
              tooltip: _expanded ? '收起为周' : '展开为月',
              onTap: _toggleExpanded,
            ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader(CalendarPalette palette) {
    switch (_viewMode) {
      case CalendarViewMode.list:
        return CalendarCollapsibleMonth(
          month: _visibleMonth,
          selectedDate: _selectedDate,
          markedDates: _markedDates,
          mondayFirst: _mondayFirst,
          palette: palette,
          expanded: _expanded,
          onExpandedChanged: _onExpandedChanged,
          onSelected: _selectDate,
        );
      case CalendarViewMode.month:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: CalendarMonthGrid(
            month: _visibleMonth,
            selectedDate: _selectedDate,
            markedDates: _markedDates,
            mondayFirst: _mondayFirst,
            palette: palette,
            onSelected: _selectDate,
          ),
        );
      case CalendarViewMode.week:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: CalendarWeekStrip(
            selectedDate: _selectedDate,
            markedDates: _markedDates,
            mondayFirst: _mondayFirst,
            palette: palette,
            onSelected: _selectDate,
          ),
        );
      case CalendarViewMode.threeDay:
        return CalendarThreeDayStrip(
          selectedDate: _selectedDate,
          markedDates: _markedDates,
          palette: palette,
          onSelected: _selectDate,
        );
      case CalendarViewMode.day:
        return _DayHeader(
          date: _selectedDate,
          palette: palette,
          onPrevious: () =>
              _selectDate(_selectedDate.subtract(const Duration(days: 1))),
          onNext: () => _selectDate(_selectedDate.add(const Duration(days: 1))),
        );
      case CalendarViewMode.year:
        return const SizedBox.shrink();
    }
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.palette,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime date;
  final CalendarPalette palette;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 46,
              height: 1,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.month}月',
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  weekdays[date.weekday - 1],
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          CalendarIconButton(
            icon: Icons.chevron_left,
            palette: palette,
            onTap: onPrevious,
          ),
          CalendarIconButton(
            icon: Icons.chevron_right,
            palette: palette,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

int mathMin(int a, int b) => a < b ? a : b;
