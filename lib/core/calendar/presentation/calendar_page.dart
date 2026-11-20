import 'dart:async';
import 'dart:math' as math;

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
import 'calendar_capsule_nav.dart';
import 'calendar_controls.dart';
import 'calendar_dialogs.dart';
import 'calendar_motion.dart';
import 'calendar_month_pane.dart';
import 'calendar_palette.dart';
import 'calendar_schedule_panes.dart';
import 'calendar_settings_sheet.dart';
import 'calendar_task_sheet.dart';
import 'calendar_year_pane.dart';

/// 胶囊日历页（原型 docs/prototypes/calendar-capsule-nav.html 的 Flutter 落地）。
///
/// 五页签：年 / 月 / 周 / 日 / 日程。页签间为深度层叠转场（滑动 × 视差 ×
/// 缩放 × 淡入淡出，纯 transform/opacity 合成器路径）；年 ⇄ 月为容器变换
/// （卡片放大成月历 / 月历缩回卡片 + 全年卡片汇聚）。
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, this.initialTab = 1});

  /// 初始页签（0 年 / 1 月 / 2 周 / 3 日 / 4 日程）。
  final int initialTab;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage>
    with TickerProviderStateMixin {
  static const _showCompletedKey = 'calendar.showCompleted';
  static const _mondayFirstKey = 'calendar.mondayFirst';

  final DateTime _today = calendarDateOnly(DateTime.now());

  int _tab = 1; // 0 年 1 月 2 周 3 日 4 日程
  final ValueNotifier<double> _tabT = ValueNotifier<double>(1);
  late final CalendarSpring _tabSpring;

  final ValueNotifier<double> _collapse = ValueNotifier<double>(1);
  late final CalendarSpring _collapseSpring;

  DateTime _selectedDate = calendarDateOnly(DateTime.now());
  DateTime _visibleMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _year = DateTime.now().year;

  bool _showCompleted = true;
  bool _mondayFirst = true;

  bool _loading = true;
  List<CalendarTask> _selectedDayTasks = const [];
  Set<String> _markedDates = const {};
  List<List<CalendarTask>> _weekTasks = const [];
  List<MapEntry<DateTime, List<CalendarTask>>> _agendaGroups = const [];

  CalendarTaskRepository? _repo;
  KeyValueRepository? _settings;
  String? _storageError;
  int _loadToken = 0;

  /// 容器变换进行中：月/年页内容隐藏，由 ghost 覆盖。
  bool _morphing = false;
  OverlayEntry? _morphEntry;
  AnimationController? _morphController;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 4);
    _tabSpring = CalendarSpring(
      vsync: this,
      description: kCalendarTabSpring,
      onUpdate: () => _tabT.value = _tabSpring.value,
    );
    _tabSpring.jump(_tab.toDouble());
    _collapseSpring = CalendarSpring(
      vsync: this,
      description: kCalendarCollapseSpring,
      onUpdate: () => _collapse.value = _collapseSpring.value,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindStorage());
  }

  @override
  void dispose() {
    _morphController?.dispose();
    _morphEntry?.remove();
    _tabSpring.dispose();
    _collapseSpring.dispose();
    _tabT.dispose();
    _collapse.dispose();
    super.dispose();
  }

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _reduceMotion =>
      MediaQuery.of(context).disableAnimations;

  /* ═══════════ 存储绑定（与旧版一致的分层策略） ═══════════ */

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
    final showCompleted = await settings.read(_showCompletedKey);
    final mondayFirst = await settings.read(_mondayFirstKey);
    if (!mounted) return;
    setState(() {
      _showCompleted = showCompleted == null || showCompleted == 'true';
      _mondayFirst = mondayFirst == null || mondayFirst == 'true';
    });
  }

  Future<void> _persist(String key, String value) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.write(key, value);
  }

  /* ═══════════ 数据加载 ═══════════ */

  Future<void> _reload() async {
    final repo = _repo;
    if (!mounted) return;
    if (repo == null) {
      setState(() {
        _selectedDayTasks = const [];
        _markedDates = const {};
        _weekTasks = const [];
        _agendaGroups = const [];
        _loading = false;
      });
      return;
    }
    final token = ++_loadToken;
    setState(() => _loading = true);
    try {
      final monthStart = calendarMonthGridStart(
        _visibleMonth,
        mondayFirst: _mondayFirst,
      );
      final weekStart =
          calendarWeekStart(_selectedDate, mondayFirst: _mondayFirst);

      final selected = await repo.tasksOnDay(
        _selectedDate,
        includeCompleted: _showCompleted,
      );
      final marked = await repo.taskDateKeysBetween(
        monthStart,
        monthStart.add(const Duration(days: 42)),
        includeCompleted: _showCompleted,
      );
      final week = <List<CalendarTask>>[];
      for (var i = 0; i < 7; i++) {
        week.add(await repo.tasksOnDay(
          weekStart.add(Duration(days: i)),
          includeCompleted: _showCompleted,
        ));
      }
      final agenda = <MapEntry<DateTime, List<CalendarTask>>>[];
      for (var i = -1; i <= 14; i++) {
        final day = _today.add(Duration(days: i));
        final tasks = await repo.tasksOnDay(
          day,
          includeCompleted: _showCompleted,
        );
        if (tasks.isNotEmpty) agenda.add(MapEntry(day, tasks));
      }
      if (!mounted || token != _loadToken) return;
      setState(() {
        _selectedDayTasks = selected;
        _markedDates = marked;
        _weekTasks = week;
        _agendaGroups = agenda;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('[calendar] 加载任务失败: $error');
      debugPrint('$stack');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _selectedDayTasks = const [];
        _markedDates = const {};
        _weekTasks = const [];
        _agendaGroups = const [];
        _loading = false;
        _storageError = '$error';
      });
    }
  }

  /* ═══════════ 页签切换 + 深度转场 ═══════════ */

  void _setTab(int index) {
    if (index == _tab) return;
    setState(() => _tabSpring.to(index.toDouble()));
    unawaited(_reload());
  }

  void _handleTabTap(int index) {
    if (_morphing) return;
    if (index == _tab) return;
    HapticFeedback.selectionClick();
    // 容器变换：月 ⇄ 年（减少动态效果时退化为普通深度转场）。
    if (!_reduceMotion && _tab == 1 && index == 0) {
      _morphToYear();
      return;
    }
    if (!_reduceMotion && _tab == 0 && index == 1) {
      _morphToMonthFromCapsule();
      return;
    }
    _setTab(index);
  }

  /* ═══════════ 容器变换（ghost FLIP） ═══════════ */

  /// 年卡片 → 月：ghost 从卡片矩形放大成月历矩形。
  void _morphToMonth(BuildContext cardContext, DateTime monthFirst) {
    if (_morphing) return;
    final cardBox = cardContext.findRenderObject();
    if (cardBox is! RenderBox || !cardBox.hasSize) {
      _setTab(1);
      return;
    }
    final cardRect = cardBox.localToGlobal(Offset.zero) & cardBox.size;

    final days = calendarDaysInMonth(monthFirst.year, monthFirst.month);
    setState(() {
      _selectedDate = DateTime(
        monthFirst.year,
        monthFirst.month,
        math.min(_selectedDate.day, days),
      );
      _visibleMonth = monthFirst;
      _tab = 1;
      _tabSpring.to(1);
      _morphing = true;
    });
    unawaited(_reload());

    // 月历区终态矩形：等本帧布局完成后测量。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_morphing) return;
      final box = _monthGridAreaKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        setState(() => _morphing = false);
        return;
      }
      final monthRect = box.localToGlobal(Offset.zero) & box.size;
      final palette = CalendarPalette.of(context);
      _startMorphGhost(
        finalRect: monthRect,
        startRect: cardRect,
        expand: true,
        monthContent: _ghostMonthContent(palette),
        startContent: CalendarMiniMonthCard(
          month: monthFirst,
          today: _today,
          markedDates: _markedDates,
          mondayFirst: _mondayFirst,
          palette: palette,
          isCurrentMonth:
              monthFirst.year == _today.year &&
                  monthFirst.month == _today.month,
        ),
      );
    });
  }

  /// 胶囊点「月」时的年→月 morph：以当前可视月的卡片为起点。
  void _morphToMonthFromCapsule() {
    final key = _yearCardKeys[_visibleMonth.month - 1];
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      _setTab(1);
      return;
    }
    _morphToMonth(key!.currentContext!, _visibleMonth);
  }

  /// 月 → 年：ghost 月历缩回目标卡片位，年页随之汇聚浮现。
  void _morphToYear() {
    if (_morphing) return;
    setState(() {
      _tab = 0;
      _tabSpring.to(0);
      _morphing = true;
    });
    unawaited(_reload());
    if (_year != _visibleMonth.year) {
      setState(() => _year = _visibleMonth.year);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_morphing) return;
      final monthBox = _monthGridAreaKey.currentContext?.findRenderObject();
      final cardKey = _yearCardKeys[_visibleMonth.month - 1];
      final cardBox = cardKey?.currentContext?.findRenderObject();
      if (monthBox is! RenderBox ||
          !monthBox.hasSize ||
          cardBox is! RenderBox ||
          !cardBox.hasSize) {
        setState(() => _morphing = false);
        return;
      }
      final monthRect =
          monthBox.localToGlobal(Offset.zero) & monthBox.size;
      final cardRect =
          cardBox.localToGlobal(Offset.zero) & cardBox.size;
      final palette = CalendarPalette.of(context);
      _startMorphGhost(
        finalRect: monthRect,
        startRect: cardRect,
        expand: false,
        monthContent: _ghostMonthContent(palette),
        startContent: CalendarMiniMonthCard(
          month: _visibleMonth,
          today: _today,
          markedDates: _markedDates,
          mondayFirst: _mondayFirst,
          palette: palette,
          isCurrentMonth:
              _visibleMonth.year == _today.year &&
                  _visibleMonth.month == _today.month,
        ),
      );
    });
  }

  Widget _ghostMonthContent(CalendarPalette palette) {
    return Container(
      color: palette.background,
      child: CalendarMonthGridContent(
        month: _visibleMonth,
        selectedDate: _selectedDate,
        today: _today,
        markedDates: _markedDates,
        mondayFirst: _mondayFirst,
        palette: palette,
        collapse: _collapse.value,
      ),
    );
  }

  /// ghost：铺在 [finalRect] 上，transform 在「映射到 [startRect]」与
  /// 恒等之间插值；expand=true 卡片放大成月历，false 月历缩回卡片。
  void _startMorphGhost({
    required Rect finalRect,
    required Rect startRect,
    required bool expand,
    required Widget monthContent,
    required Widget startContent,
  }) {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final finalOrigin = overlayBox.globalToLocal(finalRect.topLeft);
    final targetOrigin = overlayBox.globalToLocal(startRect.topLeft);
    final dx = targetOrigin.dx - finalOrigin.dx;
    final dy = targetOrigin.dy - finalOrigin.dy;
    final scaleX = startRect.width / math.max(1.0, finalRect.width);
    final scaleY = startRect.height / math.max(1.0, finalRect.height);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curve = CurvedAnimation(
      parent: controller,
      curve: const Cubic(0.32, 0.72, 0.22, 1),
    );
    _morphController = controller;

    final entry = OverlayEntry(
      builder: (context) {
        return AnimatedBuilder(
          animation: curve,
          builder: (context, _) {
            final t = curve.value;
            final tx = expand ? dx * (1 - t) : dx * t;
            final ty = expand ? dy * (1 - t) : dy * t;
            final sx = expand
                ? scaleX + (1 - scaleX) * t
                : 1 + (scaleX - 1) * t;
            final sy = expand
                ? scaleY + (1 - scaleY) * t
                : 1 + (scaleY - 1) * t;
            final monthOpacity = expand
                ? ((t - 0.42) / 0.58).clamp(0.0, 1.0)
                : (t < 0.8 ? 1.0 : (1 - t) / 0.2);
            final startOpacity = expand
                ? (t < 0.55 ? 1 - t / 0.55 : 0.0)
                : ((t - 0.6) / 0.4).clamp(0.0, 1.0);
            return Positioned(
              left: finalOrigin.dx,
              top: finalOrigin.dy,
              width: finalRect.width,
              height: finalRect.height,
              child: IgnorePointer(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(tx, ty, 0, 1)
                    ..scaleByDouble(sx, sy, 1, 1),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: monthOpacity,
                          child: monthContent,
                        ),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: startOpacity,
                          child: startContent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _morphEntry = entry;
    overlay.insert(entry);
    controller.forward(from: 0).whenComplete(() {
      entry.remove();
      _morphEntry = null;
      _morphController?.dispose();
      _morphController = null;
      if (!mounted) return;
      setState(() => _morphing = false);
    });
  }

  final GlobalKey _monthGridAreaKey = GlobalKey();
  final Map<int, GlobalKey> _yearCardKeys = {};

  /* ═══════════ 收展 ═══════════ */

  void _onCollapseDrive(double raw) {
    _collapseSpring.stop();
    _collapse.value = raw;
  }

  void _onCollapseSettle(double target, double velocity) {
    _collapseSpring.to(target, velocity: velocity);
  }

  /* ═══════════ 选择 / 翻页 ═══════════ */

  void _selectDate(DateTime date) {
    final day = calendarDateOnly(date);
    setState(() {
      _selectedDate = day;
      _visibleMonth = DateTime(day.year, day.month, 1);
      _year = day.year;
    });
    unawaited(_reload());
  }

  void _flipMonth(DateTime newMonth) {
    setState(() => _visibleMonth = DateTime(newMonth.year, newMonth.month, 1));
    unawaited(_reload());
  }

  void _shiftWeek(DateTime newWeekBase) {
    setState(() {
      _selectedDate = calendarDateOnly(newWeekBase);
      _visibleMonth =
          DateTime(newWeekBase.year, newWeekBase.month, 1);
    });
    unawaited(_reload());
  }

  void _goToday() {
    HapticFeedback.selectionClick();
    _selectDate(_today);
    _collapseSpring.to(1);
    CalendarToast.show(context, '已回到今天', CalendarPalette.of(context));
  }

  /* ═══════════ 任务操作 ═══════════ */

  Future<void> _addTask() async {
    if (_repo == null) {
      CalendarToast.show(
        context,
        _storageError ?? '本地数据库未就绪，请先重试',
        CalendarPalette.of(context),
      );
      return;
    }
    final draft = await showCalendarTaskSheet(
      context,
      palette: CalendarPalette.of(context),
      initialDate: _selectedDate,
    );
    if (draft == null || !mounted) return;
    try {
      await _repo!.create(draft);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      CalendarToast.show(context, '添加任务失败: $error', CalendarPalette.of(context));
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
      CalendarToast.show(context, '更新任务失败: $error', CalendarPalette.of(context));
    }
  }

  Future<void> _deleteTask(CalendarTask task) async {
    final repo = _repo;
    if (repo == null) return;
    final confirmed = await showCalendarConfirm(
      context,
      palette: CalendarPalette.of(context),
      title: '删除任务',
      message: '确定删除「${task.title}」吗？',
    );
    if (!confirmed || !mounted) return;
    try {
      await repo.delete(task.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      CalendarToast.show(context, '删除任务失败: $error', CalendarPalette.of(context));
    }
  }

  Future<void> _showSettings() async {
    await showCalendarSettingsSheet(
      context,
      palette: CalendarPalette.of(context),
      showCompleted: _showCompleted,
      mondayFirst: _mondayFirst,
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

  /* ═══════════ 标题 ═══════════ */

  String _titleText() {
    switch (_tab) {
      case 0:
        return '${_visibleMonth.year}年';
      case 1:
        final p = calendarClamp01(_collapse.value);
        if (p < 0.5) {
          final weekStart =
              calendarWeekStart(_selectedDate, mondayFirst: _mondayFirst);
          final week = _selectedDate.difference(weekStart).inDays ~/ 7 + 1;
          return '${_visibleMonth.month}月 · 第$week周';
        }
        return _visibleMonth.year == _today.year
            ? '${_visibleMonth.month}月'
            : '${_visibleMonth.year}年${_visibleMonth.month}月';
      case 2:
      case 3:
        return _selectedDate.year == _today.year
            ? '${_selectedDate.month}月${_selectedDate.day}日'
            : '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日';
      default:
        return '日程';
    }
  }

  /* ═══════════ 构建 ═══════════ */

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(palette),
            CalendarCapsuleNav(
              tabs: const ['年', '月', '周', '日', '日程'],
              activeIndex: _tab,
              progress: _tabT,
              onTap: _handleTabTap,
              palette: palette,
            ),
            Expanded(
              child: ClipRect(
                child: ValueListenableBuilder<double>(
                  valueListenable: _tabT,
                  builder: (context, t, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final w = math.max(1.0, constraints.maxWidth);
                        final tc = t.clamp(0.0, 4.0);
                        // 深度层叠：各面板独立 translate((i-tc)*w)。
                        // 命中区随偏移平移（active 面板 offset=0 恰好占满可视区，
                        // 相邻面板被自身边界拒绝），不会出现整排 Row 的
                        // 溢出或「只有第 0 页可点」的命中黑洞。
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < 5; i++)
                              Transform.translate(
                                offset: Offset((i - tc) * w, 0),
                                child: SizedBox(
                                  width: w,
                                  height: constraints.maxHeight,
                                  child: _paneLayer(i, t, w),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFabs(palette),
    );
  }

  /// 页签层：远端（|i-t|>1.1）不绘制；近端按距离缩放/淡出/视差滞后。
  Widget _paneLayer(int i, double t, double w) {
    final dRaw = (i - t).abs();
    if (dRaw > 1.1) {
      return const SizedBox.expand();
    }
    final d = math.min(dRaw, 1.0);
    final dd = d * d;
    // morph 期间 ghost 覆盖年/月两层，真实内容暂隐。
    final opacity = _morphing && (i == 0 || i == 1)
        ? 0.0
        : (1 - 1.25 * d).clamp(0.0, 1.0);
    final scale = 1 - 0.10 * dd;
    final px = (t.clamp(0.0, 4.0) - i) * w * 0.16 * (1 - d);
    return Transform.translate(
      offset: Offset(px, 0),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          alignment: const Alignment(0, -0.16), // origin 50% 42%
          child: _buildPane(i, w),
        ),
      ),
    );
  }

  Widget _buildPane(int index, double width) {
    final palette = CalendarPalette.of(context);
    final weekStart =
        calendarWeekStart(_selectedDate, mondayFirst: _mondayFirst);
    switch (index) {
      case 0:
        return Container(
          color: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CalendarYearPane(
            year: _year,
            today: _today,
            markedDates: _markedDates,
            mondayFirst: _mondayFirst,
            palette: palette,
            cardKeys: _yearCardKeys,
            onYearChanged: (year) {
              final days = calendarDaysInMonth(year, _visibleMonth.month);
              final day = math.min(_selectedDate.day, days);
              setState(() {
                _year = year;
                _selectedDate = DateTime(year, _visibleMonth.month, day);
                _visibleMonth = DateTime(year, _visibleMonth.month, 1);
              });
              unawaited(_reload());
            },
            onMonthTap: _morphToMonth,
          ),
        );
      case 1:
        return Container(
          color: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: KeyedSubtree(
            key: _monthGridAreaKey,
            child: CalendarMonthPane(
              month: _visibleMonth,
              selectedDate: _selectedDate,
              today: _today,
              markedDates: _markedDates,
              mondayFirst: _mondayFirst,
              palette: palette,
              collapse: _collapse,
              tasks: _selectedDayTasks,
              loading: _loading,
              storageAvailable: _repo != null,
              storageMessage: _storageError,
              onRetryStorage: _retryStorage,
              onCollapseDrive: _onCollapseDrive,
              onCollapseSettle: _onCollapseSettle,
              onFlipCommit: _flipMonth,
              onSelect: _selectDate,
              onToggleTask: _toggleTask,
              onDeleteTask: _deleteTask,
            ),
          ),
        );
      case 2:
        final weekStart =
            calendarWeekStart(_selectedDate, mondayFirst: _mondayFirst);
        return Container(
          color: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CalendarWeekStrip(
                weekBase: weekStart,
                selectedDate: _selectedDate,
                today: _today,
                mondayFirst: _mondayFirst,
                palette: palette,
                onShift: _shiftWeek,
                onSelect: _selectDate,
              ),
              CalendarAllDayChips(days: _weekTasks, palette: palette),
              Expanded(
                child: CalendarTimeline(
                  days: _weekTasks,
                  showNowLine: false,
                  palette: palette,
                  onToggle: _toggleTask,
                ),
              ),
            ],
          ),
        );
      case 3:
        return Container(
          color: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CalendarWeekStrip(
                weekBase: weekStart,
                selectedDate: _selectedDate,
                today: _today,
                mondayFirst: _mondayFirst,
                palette: palette,
                onShift: _shiftWeek,
                onSelect: _selectDate,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: CalendarTimeline(
                  days: [_selectedDayTasks],
                  showNowLine:
                      _selectedDate == _today,
                  palette: palette,
                  onToggle: _toggleTask,
                ),
              ),
            ],
          ),
        );
      default:
        return Container(
          color: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CalendarAgendaPane(
            groups: _agendaGroups,
            today: _today,
            palette: palette,
            loading: _loading,
            storageAvailable: _repo != null,
            storageMessage: _storageError,
            onRetry: _retryStorage,
            onToggle: _toggleTask,
            onDelete: _deleteTask,
          ),
        );
    }
  }

  Widget _buildHeader(CalendarPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _collapse,
              builder: (context, _, _) => Text(
                _titleText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          CalendarIconButton(
            icon: Icons.today_outlined,
            palette: palette,
            tooltip: '回到今天',
            onTap: _goToday,
          ),
          CalendarIconButton(
            icon: Icons.more_horiz,
            palette: palette,
            tooltip: '日历设置',
            onTap: _showSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildFabs(CalendarPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _goToday,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: palette.divider),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              '今',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.danger,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _addTask,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.add, size: 26, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
