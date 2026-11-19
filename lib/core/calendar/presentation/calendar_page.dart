import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/sqlite/sqlite.dart';
import '../domain/calendar_date_utils.dart';
import '../domain/calendar_task.dart';
import 'calendar_grid.dart';
import 'calendar_palette.dart';
import 'calendar_task_list.dart';
import 'calendar_task_sheet.dart';

enum CalendarViewMode {
  list('列表'),
  month('月'),
  week('周'),
  day('日');

  const CalendarViewMode(this.label);
  final String label;
}

const _kMonthNames = [
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '七',
  '八',
  '九',
  '十',
  '十一',
  '十二',
];

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
  DateTime _visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  bool _expanded = true;
  CalendarViewMode _viewMode = CalendarViewMode.list;
  bool _showCompleted = true;
  bool _mondayFirst = true;

  bool _loading = true;
  List<CalendarTask> _tasks = const [];
  Set<String> _markedDates = const {};

  SqliteCalendarRepository? _repo;
  SqliteSettingsRepository? _settings;

  int _loadToken = 0;
  double _dragAccum = 0;

  CalendarPalette get _palette => CalendarPalette.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindStorage());
  }

  Future<void> _bindStorage() async {
    final repo = ref.read(sqliteCalendarRepositoryProvider);
    final settings = ref.read(sqliteSettingsRepositoryProvider);
    if (!mounted) return;

    _repo = repo;
    _settings = settings;
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

    final gridStart = calendarMonthGridStart(
      _visibleMonth,
      mondayFirst: _mondayFirst,
    );
    final gridEnd = gridStart.add(const Duration(days: 42));

    try {
      final tasks = await repo.tasksOnDay(
        _selectedDate,
        includeCompleted: _showCompleted,
      );
      final marked = await repo.taskDateKeysBetween(
        gridStart,
        gridEnd,
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
      });
    }
  }

  void _selectDate(DateTime date) {
    final day = calendarDateOnly(date);
    if (calendarDateKey(day) == calendarDateKey(_selectedDate)) return;
    setState(() {
      _selectedDate = day;
      _visibleMonth = DateTime(day.year, day.month, 1);
    });
    unawaited(_reload());
  }

  void _goToday() {
    _selectDate(_today);
    if (_viewMode == CalendarViewMode.list) {
      setState(() => _expanded = true);
    }
  }

  void _toggleExpanded() {
    if (_viewMode != CalendarViewMode.list) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_viewMode != CalendarViewMode.list) return;
    _dragAccum += details.delta.dy;
    if (_dragAccum > 18 && !_expanded) {
      HapticFeedback.selectionClick();
      setState(() {
        _expanded = true;
        _dragAccum = 0;
      });
    } else if (_dragAccum < -18 && _expanded) {
      HapticFeedback.selectionClick();
      setState(() {
        _expanded = false;
        _dragAccum = 0;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragAccum = 0;
  }

  Future<void> _addTask() async {
    final repo = _repo;
    if (repo == null) {
      _showMessage('当前平台未启用 SQLite，无法创建任务');
      return;
    }

    final draft = await showCalendarTaskSheet(
      context,
      palette: _palette,
      initialDate: _selectedDate,
    );
    if (draft == null) return;

    try {
      await repo.create(draft);
      await _reload();
    } catch (error) {
      _showMessage('添加任务失败: $error');
    }
  }

  Future<void> _toggleTask(CalendarTask task) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.toggleCompleted(task);
      await _reload();
    } catch (error) {
      _showMessage('更新任务失败: $error');
    }
  }

  Future<void> _deleteTask(CalendarTask task) async {
    final repo = _repo;
    if (repo == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${task.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repo.delete(task.id);
      await _reload();
    } catch (error) {
      _showMessage('删除任务失败: $error');
    }
  }

  Future<void> _persist(String key, String value) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.write(key, value);
  }

  Future<void> _showSettings() async {
    final palette = _palette;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(
                        '日历设置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      child: Text(
                        '视图',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final mode in CalendarViewMode.values)
                          ChoiceChip(
                            label: Text(mode.label),
                            selected: _viewMode == mode,
                            selectedColor: palette.accentSoft,
                            labelStyle: TextStyle(
                              color: _viewMode == mode
                                  ? palette.accent
                                  : palette.textPrimary,
                              fontWeight: _viewMode == mode
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            side: BorderSide(
                              color: _viewMode == mode
                                  ? palette.accent.withValues(alpha: 0.5)
                                  : palette.divider,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _viewMode = mode;
                                if (mode == CalendarViewMode.month) {
                                  _expanded = true;
                                } else if (mode == CalendarViewMode.week) {
                                  _expanded = false;
                                }
                              });
                              setSheetState(() {});
                              unawaited(_persist(_viewModeKey, mode.name));
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '显示已完成任务',
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      value: _showCompleted,
                      activeThumbColor: palette.accent,
                      onChanged: (value) {
                        setState(() => _showCompleted = value);
                        setSheetState(() {});
                        unawaited(
                          _persist(_showCompletedKey, value.toString()),
                        );
                        unawaited(_reload());
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '周一作为一周开始',
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      value: _mondayFirst,
                      activeThumbColor: palette.accent,
                      onChanged: (value) {
                        setState(() => _mondayFirst = value);
                        setSheetState(() {});
                        unawaited(_persist(_mondayFirstKey, value.toString()));
                        unawaited(_reload());
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.today_outlined,
                        color: palette.accent,
                      ),
                      title: Text(
                        '回到今天',
                        style: TextStyle(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: palette.textSecondary,
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _goToday();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _monthTitle(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year) {
      return '${_kMonthNames[date.month - 1]}月';
    }
    return '${date.year}年${date.month}月';
  }

  String _selectedDateLabel(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 · ${weekdays[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final title = _monthTitle(_selectedDate);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(palette, title),
            if (_viewMode == CalendarViewMode.list)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? _buildMonthGrid(palette)
                      : _buildWeekStrip(palette),
                ),
              )
            else if (_viewMode == CalendarViewMode.month)
              _buildMonthGrid(palette)
            else if (_viewMode == CalendarViewMode.week)
              _buildWeekStrip(palette)
            else
              _buildDayHeader(palette),
            const SizedBox(height: 4),
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
                onToggle: _toggleTask,
                onDelete: _deleteTask,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _buildHeader(CalendarPalette palette, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: palette.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: '视图与设置',
            onPressed: _showSettings,
            icon: Icon(
              _viewMode == CalendarViewMode.week
                  ? Icons.view_week_outlined
                  : _viewMode == CalendarViewMode.day
                  ? Icons.view_day_outlined
                  : Icons.view_agenda_outlined,
              color: palette.textPrimary,
            ),
          ),
          IconButton(
            tooltip: '更多设置',
            onPressed: _showSettings,
            icon: Icon(Icons.more_horiz, color: palette.textPrimary),
          ),
          if (_viewMode == CalendarViewMode.list)
            IconButton(
              tooltip: _expanded ? '收起为周' : '展开为月',
              onPressed: _toggleExpanded,
              icon: Icon(
                _expanded ? Icons.unfold_less : Icons.unfold_more,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(CalendarPalette palette) {
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
  }

  Widget _buildWeekStrip(CalendarPalette palette) {
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
  }

  Widget _buildDayHeader(CalendarPalette palette) {
    final weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${_selectedDate.day}',
            style: TextStyle(
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${_selectedDate.month}月 · ${weekday[_selectedDate.weekday - 1]}',
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
