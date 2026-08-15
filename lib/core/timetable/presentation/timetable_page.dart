import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/timetable_repository.dart';
import '../domain/models.dart';
import 'timetable_store.dart';
import 'timetable_cell.dart';
import 'timetable_editor_dialog.dart';
import 'timetable_colors.dart';
import '../service/config/timetable_settings_page.dart';
import '../service/config/timetable_anime_editor_page.dart';
import '../service/config/anime_dsl_generator.dart';
import '../../../widgets/image_picker_widget.dart';

/// 简洁日历风格课表页面
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  late PageController _pageController;
  int _currentCycleIndex = 0;
  // 选中的单元格 key: 'c${cycleIndex}_d${dayOfCycle}_s${slotIndex}'
  String? _selectedCellKey;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1.0);
    // 默认定位到今天所在周期
    final config = ref.read(TimetableStore.configProvider);
    final todayIdx = config.todayCycleIndex;
    if (todayIdx != null) {
      _currentCycleIndex = todayIdx;
      // 让 PageView 一开始就显示该周期
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(todayIdx);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 生成单元格唯一键
  String _cellKey(int cycleIndex, int dayOfCycle, int slotIndex) {
    return '$cycleIndex-$dayOfCycle-$slotIndex';
  }

  /// 打开空间选择面板（仿 kv 清单头部工作空间选择）
  Future<void> _openSpaceSheet() async {
    final store = ref.read(TimetableStore.provider.notifier);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SpaceSheet(
        store: store,
        activeId: store.activeSpaceId,
      ),
    );
    if (selected != null) {
      // 空间名等变化，刷新列表 provider
      ref.invalidate(TimetableStore.spacesProvider);
      if (mounted) setState(() {});
    }
  }

  /// 选择背景图
  Future<void> _pickBackgroundImage() async {
    final config = ref.read(TimetableStore.provider).config;
    if (config.backgroundImagePath != null) {
      // 已有背景图，显示菜单
      _showBackgroundImageMenu();
    } else {
      // 无背景图，直接选择
      final path = await ImagePickerPage.navigate(
        context,
        config: const ImagePickerConfig(),
        title: '选择背景图',
      );
      if (path != null) {
        await ref
            .read(TimetableStore.provider.notifier)
            .updateBackgroundImage(path);
      }
    }
  }

  /// 显示背景图菜单
  void _showBackgroundImageMenu() {
    final pageContext = context;
    showModalBottomSheet(
      context: pageContext,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('更换背景图'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final path = await ImagePickerPage.navigate(
                  pageContext,
                  config: const ImagePickerConfig(),
                  title: '选择背景图',
                );
                if (path != null) {
                  await ref
                      .read(TimetableStore.provider.notifier)
                      .updateBackgroundImage(path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('移除背景图', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref
                    .read(TimetableStore.provider.notifier)
                    .updateBackgroundImage(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(TimetableStore.configProvider);
    final spacesAsync = ref.watch(TimetableStore.spacesProvider);
    final activeId = ref.read(TimetableStore.provider.notifier).activeSpaceId;
    final activeSpaceName =
        spacesAsync.valueOrNull?.firstWhere(
          (s) => s.id == activeId,
          orElse: () => const TimetableSpaceInfo(
            id: TimetableRepository.defaultSpaceId,
            name: '默认课表',
          ),
        ).name ??
        (activeId == TimetableRepository.defaultSpaceId ? '默认课表' : activeId);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '时间周期',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 头部空间选择（仿 kv 清单工作空间选择模式）
          IconButton(
            icon: const Icon(Icons.workspaces_outlined),
            tooltip: '工作空间: $activeSpaceName（点击切换）',
            onPressed: _openSpaceSheet,
          ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            onPressed: _pickBackgroundImage,
            tooltip: '设置背景图',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimetableSettingsPage()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 背景图（固定不动）
          if (config.backgroundImagePath != null)
            Positioned.fill(
              child: Image.file(
                File(config.backgroundImagePath!),
                fit: BoxFit.cover,
              ),
            ),
          // 课表内容层
          Column(
            children: [
              // 天数标题行
              _buildWeekdayHeader(theme, config),
              const Divider(height: 1),
              // 课表网格（可左右滑动）
              Expanded(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentCycleIndex = index;
                          _selectedCellKey = null; // 切换周期时清除选中
                        });
                      },
                      itemCount: config.cycleCount,
                      itemBuilder: (context, cycleIndex) {
                        return _buildTimetableGrid(theme, config, cycleIndex);
                      },
                    ),
                    // 右上角 - 回到今天按钮
                    if (config.todayCycleIndex != null &&
                        config.todayCycleIndex != _currentCycleIndex)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              config.todayCycleIndex!,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: TimetableColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: TimetableColors.accent.withValues(alpha: 0.5),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.today,
                                  size: 14,
                                  color: TimetableColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '今天',
                                  style: TextStyle(
                                    color: TimetableColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 天数标题行 - 显示"第1天、第2天..."
  Widget _buildWeekdayHeader(ThemeData theme, TimetableConfig config) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 左上角 - 显示当前周期
          Container(
            width: 64,
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                '第${_currentCycleIndex + 1}周期',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: TimetableColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          // 天数列 - 只显示 daysPerCycle 列
          Expanded(
            child: Row(
              children: List.generate(config.daysPerCycle, (dayOfCycle) {
                final globalDayIndex = TimetableMappers.cycleToDayIndex(
                  _currentCycleIndex,
                  dayOfCycle,
                  config.daysPerCycle,
                );
                return Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '第${dayOfCycle + 1}天',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: TimetableColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          TimetableMappers.formatDate(
                            config.startDateIso,
                            globalDayIndex,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: TimetableColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 课表网格 - 使用 cycleGridProvider 获取课程（按周期过滤）
  Widget _buildTimetableGrid(
    ThemeData theme,
    TimetableConfig config,
    int cycleIndex,
  ) {
    // 使用 cycleGridProvider 获取课程（会根据 visibleInCycles 过滤）
    final cycleGrid = ref.watch(TimetableStore.cycleGridProvider(cycleIndex));

    return LayoutBuilder(
      builder: (context, constraints) {
        // 行高按「一页视口行数」计算（fr 28：追剧模式每部剧独占 slot，
        // slotsPerDay 可远超一屏；slotsPerDay 不满一页时仍平铺占满）
        final totalHeight = constraints.maxHeight;
        final rowsPerPage = config.slotsPerPage < config.slotsPerDay
            ? config.slotsPerPage
            : config.slotsPerDay;
        final rowHeight = totalHeight / rowsPerPage;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: config.slotsPerDay,
          itemBuilder: (context, slotIndex) {
            return SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  // 时间列
                  _SlotLabel(
                    slotIndex: slotIndex,
                    height: rowHeight,
                    config: config,
                  ),
                  // 课程网格列
                  ...List.generate(config.daysPerCycle, (dayOfCycle) {
                    final course = cycleGrid[dayOfCycle][slotIndex];
                    final cellKeyValue = '$cycleIndex-$dayOfCycle-$slotIndex';
                    final isSelected = _selectedCellKey == cellKeyValue;
                    final cellKey = 'd${dayOfCycle}_s$slotIndex';

                    return Expanded(
                      child: TimetableCell(
                        key: ValueKey(cellKeyValue),
                        state: isSelected
                            ? TimetableCellState.selected
                            : (course != null
                                  ? TimetableCellState.filled
                                  : TimetableCellState.empty),
                        course: course,
                        onTap: () => _handleCellTap(
                          cycleIndex,
                          dayOfCycle,
                          slotIndex,
                          course,
                        ),
                        onLongPress: () => _handleCellLongPress(
                          cycleIndex,
                          dayOfCycle,
                          slotIndex,
                          cellKey,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 处理单元格点击
  void _handleCellTap(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    CourseItem? course,
  ) {
    final cellKeyValue = _cellKey(cycleIndex, dayOfCycle, slotIndex);
    final cellKey = 'd${dayOfCycle}_s$slotIndex';
    final hasVisibleCourse = course != null;

    if (_selectedCellKey == cellKeyValue) {
      // 点击已选中的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, course);
      } else {
        // 空白 → 打开编辑器
        _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey);
      }
    } else {
      // 点击不同的单元格
      if (hasVisibleCourse) {
        // 有课程 → 显示预览抽屉
        _showCoursePreview(cycleIndex, dayOfCycle, slotIndex, course);
      } else {
        // 空白 → 选中当前单元格（进入+状态）
        setState(() => _selectedCellKey = cellKeyValue);
      }
    }
  }

  /// 显示课程预览抽屉
  void _showCoursePreview(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    CourseItem course,
  ) {
    // 清除选中状态
    setState(() => _selectedCellKey = null);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _CoursePreviewSheet(
        course: course,
        cycleIndex: cycleIndex,
        dayOfCycle: dayOfCycle,
        slotIndex: slotIndex,
        onEdit: () {
          Navigator.pop(context); // 关闭抽屉
          final cellKey = 'd${dayOfCycle}_s$slotIndex';
          _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey, focusCourse: course);
        },
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  /// 处理单元格长按
  void _handleCellLongPress(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    String cellKey,
  ) {
    // 长按直接打开编辑器
    _openEditor(cycleIndex, dayOfCycle, slotIndex, cellKey);
  }

  /// 打开编辑器（居中对话框）
  ///
  /// 按模式路由（fr 28）：课表模式 → 课程编辑器（课程名/地点/老师）；
  /// 追剧模式 → 剧模型编辑（课程由剧模型自动派生，直接编课程会被覆盖）。
  void _openEditor(
    int cycleIndex,
    int dayOfCycle,
    int slotIndex,
    String cellKey, {
    CourseItem? focusCourse,
  }) {
    if (ref.read(TimetableStore.configProvider).isAnimeMode) {
      _openAnimeSeriesEditor(focusCourse);
      return;
    }
    // 从 store 获取该 cellKey 的所有课程
    final courses = ref.read(TimetableStore.cellProvider(cellKey));

    // 清除选中状态
    setState(() => _selectedCellKey = null);

    // 显示居中的对话框
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => TimetableEditorDialog(
        dayOfCycle: dayOfCycle,
        slotIndex: slotIndex,
        cycleIndex: cycleIndex,
        cellKey: cellKey,
        existingCourses: courses,
        focusCourse: focusCourse,
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  /// 追剧模式：cell 编辑路由到剧模型编辑。
  /// 匹配到剧 → 剧编辑对话框；空 cell/匹配不到 → 提示走排期页
  /// （直接创建/编辑课程会被下次剧变更的自动派生覆盖）。
  Future<void> _openAnimeSeriesEditor(CourseItem? focusCourse) async {
    final state = ref.read(TimetableStore.provider);
    final store = ref.read(TimetableStore.provider.notifier);

    // 按 title 匹配剧模型（CourseItem.title 即剧名）
    AnimeSeriesDraft? target;
    final title = focusCourse?.title;
    if (title != null) {
      for (final s in state.animeSeries) {
        if (s.title == title) {
          target = s;
          break;
        }
      }
    }

    setState(() => _selectedCellKey = null);

    if (target != null) {
      final draft = await showAnimeSeriesEditDialog(context, initial: target);
      if (draft != null) {
        await store.updateAnimeSeries(draft);
      }
      return;
    }

    // 空 cell：不提供直接编辑（会被覆盖），引导去排期页
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('追剧模式'),
        content: const Text(
          '课程由剧模型自动派生，直接编辑会被覆盖。\n请到追剧排期页添加或修改剧。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去排期页'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const TimetableAnimeEditorPage(),
        ),
      );
    }
  }
}

/// 空间选择底部面板：单选切换 + 新建/重命名/删除（default 不可删）
class _SpaceSheet extends StatefulWidget {
  final TimetableStore store;
  final String activeId;

  const _SpaceSheet({required this.store, required this.activeId});

  @override
  State<_SpaceSheet> createState() => _SpaceSheetState();
}

class _SpaceSheetState extends State<_SpaceSheet> {
  late List<TimetableSpaceInfo> _spaces;
  late String _activeId;

  @override
  void initState() {
    super.initState();
    _spaces = [];
    _activeId = widget.activeId;
    _reload();
  }

  Future<void> _reload() async {
    final spaces = await widget.store.listSpaces();
    if (mounted) setState(() => _spaces = spaces);
  }

  Future<void> _createSpace() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建空间'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '空间名称，如: 新番目录 / 日程安排',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.store.createSpace(name);
    _activeId = widget.store.activeSpaceId;
    await _reload();
  }

  Future<void> _renameSpace(TimetableSpaceInfo space) async {
    final controller = TextEditingController(text: space.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名空间'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == space.name) return;
    await widget.store.renameSpace(space.id, name);
    await _reload();
  }

  Future<void> _deleteSpace(TimetableSpaceInfo space) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除空间'),
        content: Text('确定删除「${space.name}」吗？该空间下的课表数据将一并删除，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteSpace(space.id);
    _activeId = widget.store.activeSpaceId;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Text(
                  '工作空间',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_spaces.length} 个',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final space in _spaces)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      space.id == _activeId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: space.id == _activeId
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    title: Text(
                      space.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: space.isDefault
                        ? const Text('默认空间（历史数据）')
                        : null,
                    trailing: space.isDefault
                        ? (_activeId == space.id
                              ? const Text('当前')
                              : null)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (space.id == _activeId)
                                const Text('当前'),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _renameSpace(space);
                                  } else if (value == 'delete') {
                                    _deleteSpace(space);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('重命名'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      '删除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                    onTap: () {
                      if (space.id != _activeId) {
                        widget.store.setActiveSpace(space.id);
                      }
                      Navigator.pop(context, space.id);
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.add,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            title: const Text('新建空间'),
            onTap: _createSpace,
          ),
        ],
      ),
    );
  }
}

/// 左侧节数标签组件
///
/// 按 config.leftLabelMode 渲染三种模式：
/// 0=节次序号 / 1=时间段(开始-结束) / 2=自定义文字；宽度取 config.leftWidth。
class _SlotLabel extends StatelessWidget {
  const _SlotLabel({
    required this.slotIndex,
    required this.height,
    required this.config,
  });

  final int slotIndex;
  final double height;
  final TimetableConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: config.leftWidth,
      height: height - 8,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline, width: 1.5),
      ),
      child: Center(
        child: Text(
          config.slotLabel(slotIndex),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: TimetableColors.textPrimary,
            fontWeight: FontWeight.w700,
            height: 1.2,
            fontSize: config.leftLabelMode == 0 ? 16 : 11,
          ),
        ),
      ),
    );
  }
}

/// 周期胶囊标签组件 - 低饱和度圆角边框风格
class _CycleChips extends StatelessWidget {
  const _CycleChips({required this.cycles});

  final List<int> cycles;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cycles.map((cycle) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: TimetableColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: TimetableColors.border,
              width: 1,
            ),
          ),
          child: Text(
            '周期${cycle + 1}',
            style: TextStyle(
              fontSize: 12,
              color: TimetableColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 课程预览底部抽屉
class _CoursePreviewSheet extends StatelessWidget {
  const _CoursePreviewSheet({
    required this.course,
    required this.cycleIndex,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.onEdit,
    required this.onClose,
  });

  final CourseItem course;
  final int cycleIndex;
  final int dayOfCycle;
  final int slotIndex;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = TimetableColors.getCourseColor(course.colorSeed ?? 0);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: TimetableColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 内容区
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题和颜色标签
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '第${dayOfCycle + 1}天 · 第${slotIndex + 1}节',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: TimetableColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 地点
                if (course.location != null && course.location!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: TimetableColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(course.location!, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ],
                // 可见周期
                if (course.visibleInCycles != null &&
                    course.visibleInCycles!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _CycleChips(cycles: course.visibleInCycles!),
                ],
                // 编辑按钮
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: theme.colorScheme.outline,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.outline,
                    ),
                    label: Text(
                      '编辑',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 底部安全区
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
