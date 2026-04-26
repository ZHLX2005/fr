import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/timetable_repository.dart';
import '../domain/models.dart';

/// 课表系统状态
class TimetableState {
  const TimetableState({
    required this.config,
    required this.items,
    this.isLoading = false,
  });

  final TimetableConfig config;
  /// 按 cellKey 索引，每个 key 对应该时间段的所有课程列表
  /// cellKey = 'd${dayOfCycle}_s$slotIndex'
  final Map<String, List<CourseItem>> items;
  final bool isLoading;

  TimetableState copyWith({
    TimetableConfig? config,
    Map<String, List<CourseItem>>? items,
    bool? isLoading,
  }) {
    return TimetableState(
      config: config ?? this.config,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// TimetableStore - 单一数据源 (SSOT)
class TimetableStore extends StateNotifier<TimetableState> {
  TimetableStore(this._repo)
    : super(
        const TimetableState(
          config: TimetableConfig.defaultConfig,
          items: {},
          isLoading: false,
        ),
      );

  final TimetableRepository _repo;

  /// 初始化并加载数据
  Future<void> hydrate() async {
    state = const TimetableState(
      config: TimetableConfig.defaultConfig,
      items: {},
      isLoading: true,
    );

    try {
      final config = await _repo.loadConfig();
      final itemsMap = await _repo.loadItems();

      state = TimetableState(config: config, items: itemsMap, isLoading: false);
    } catch (e) {
      state = TimetableState(
        config: TimetableConfig.defaultConfig,
        items: {},
        isLoading: false,
      );
    }
  }

  /// 新增或更新课程项目
  /// 如果 item.id 已存在则替换，不存在则追加到列表
  Future<void> upsertItem(CourseItem item) async {
    final newItems = Map<String, List<CourseItem>>.from(state.items);
    final cellKey = item.cellKey;
    final existing = List<CourseItem>.from(newItems[cellKey] ?? []);

    final idx = existing.indexWhere((c) => c.id == item.id);
    if (idx >= 0) {
      existing[idx] = item;
    } else {
      existing.add(item);
    }
    newItems[cellKey] = existing;

    state = state.copyWith(items: newItems);

    try {
      await _repo.upsertItems(cellKey, existing);
    } catch (e) {
      // 失败回滚
      newItems[cellKey] = existing.where((c) => c.id != item.id).toList();
      if (newItems[cellKey]!.isEmpty) newItems.remove(cellKey);
      state = state.copyWith(items: newItems);
    }
  }

  /// 直接更新整个列表（用于编辑器批量更新）
  Future<void> upsertItems(String cellKey, List<CourseItem> items) async {
    final newItems = Map<String, List<CourseItem>>.from(state.items);
    newItems[cellKey] = items;

    state = state.copyWith(items: newItems);

    try {
      await _repo.upsertItems(cellKey, items);
    } catch (e) {
      // 失败回滚
      final oldItems = state.items[cellKey];
      if (oldItems != null) {
        newItems[cellKey] = oldItems;
      } else {
        newItems.remove(cellKey);
      }
      state = state.copyWith(items: newItems);
    }
  }

  /// 删除课程项目（从cellKey对应的列表中删除指定id的课程）
  Future<void> deleteItem(String cellKey, {String? itemId}) async {
    final newItems = Map<String, List<CourseItem>>.from(state.items);
    final existing = newItems[cellKey];
    if (existing == null || existing.isEmpty) return;

    final deletedItemId = itemId ?? existing.last.id;
    final remaining = existing.where((c) => c.id != deletedItemId).toList();

    if (remaining.isEmpty) {
      newItems.remove(cellKey);
    } else {
      newItems[cellKey] = remaining;
    }

    state = state.copyWith(items: newItems);

    try {
      if (remaining.isEmpty) {
        await _repo.deleteItem(cellKey);
      } else {
        await _repo.upsertItems(cellKey, remaining);
      }
    } catch (e) {
      // 失败恢复
      newItems[cellKey] = existing;
      state = state.copyWith(items: newItems);
    }
  }

  /// 清空所有课程
  Future<void> clearAllItems() async {
    final newItems = <String, List<CourseItem>>{};
    state = state.copyWith(items: newItems);
    try {
      await _repo.clearItems();
    } catch (e) {
      // 失败时恢复（简化处理：不做回滚）
    }
  }

  /// 导出所有课程为 DSL 文本
  String exportToDsl() {
    final buffer = StringBuffer();

    for (final courseList in state.items.values) {
      for (final item in courseList) {
        final dayOfCycle = item.dayOfCycle + 1; // 1-based
        final slotStart = item.slotIndex + 1;
        final slotEnd = item.slotIndex + 1;
        final slotStr = slotStart == slotEnd ? '$slotStart' : '$slotStart-$slotEnd';

        final weeks = item.visibleInCycles != null && item.visibleInCycles!.isNotEmpty
            ? 'w${item.visibleInCycles!.map((i) => i + 1).join(",")}'
            : '';

        final location = item.location ?? '';
        final teacher = item.teacher ?? '';

        final parts = [item.title, '@', '$dayOfCycle', slotStr, weeks, location, teacher]
            .where((p) => p.isNotEmpty)
            .toList();

        buffer.writeln(parts.join(' '));
      }
    }

    return buffer.toString();
  }

  /// 更新配置
  Future<String?> updateConfig({
    String? startDateIso,
    int? cycleCount,
    int? daysPerCycle,
    int? slotsPerDay,
    bool? isSchoolMode,
  }) async {
    final oldConfig = state.config;

    // 计算新的 daysPerCycle 和 slotsPerDay
    final newDaysPerCycle =
        daysPerCycle?.clamp(
          TimetableConfig.minDaysPerCycle,
          TimetableConfig.maxDaysPerCycle,
        ) ??
        oldConfig.daysPerCycle;
    final newSlotsPerDay =
        slotsPerDay?.clamp(
          TimetableConfig.minSlotsPerDay,
          TimetableConfig.maxSlotsPerDay,
        ) ??
        oldConfig.slotsPerDay;

    // 检查是否有课程超出新的边界
    final newItems = Map<String, List<CourseItem>>.from(state.items);
    final deletedKeys = <String>[];

    // 检查 dayOfCycle 是否超出范围
    if (daysPerCycle != null) {
      newItems.removeWhere((key, courseList) {
        final outOfRange = courseList.where((item) => item.dayOfCycle >= newDaysPerCycle).toList();
        if (outOfRange.isNotEmpty) {
          deletedKeys.add(key);
          return true;
        }
        return false;
      });
    }

    // 检查 slotIndex 是否超出范围
    if (slotsPerDay != null) {
      newItems.removeWhere((key, courseList) {
        final outOfRange = courseList.where((item) => item.slotIndex >= newSlotsPerDay).toList();
        if (outOfRange.isNotEmpty) {
          deletedKeys.add(key);
          return true;
        }
        return false;
      });
    }

    final newConfig = oldConfig.copyWith(
      startDateIso: startDateIso,
      cycleCount: cycleCount?.clamp(
        TimetableConfig.minCycles,
        TimetableConfig.maxCycles,
      ),
      daysPerCycle: newDaysPerCycle,
      slotsPerDay: newSlotsPerDay,
      isSchoolMode: isSchoolMode,
    );

    // 保存配置
    await _repo.saveConfig(newConfig);

    // 保存更新后的 items（展平列表）
    await _repo.saveItems(newItems.values.expand((list) => list).toList());

    state = state.copyWith(config: newConfig, items: newItems);

    if (deletedKeys.isNotEmpty) {
      return '配置缩小，已删除 ${deletedKeys.length} 个超出范围的项目';
    }

    return null;
  }

  /// 更新背景图
  Future<void> updateBackgroundImage(String? path) async {
    final newConfig = state.config.copyWith(
      backgroundImagePath: path,
      clearBackgroundImage: path == null,
    );
    await _repo.saveConfig(newConfig);
    state = state.copyWith(config: newConfig);
  }

  /// Repository Provider
  static final repoProvider = Provider<TimetableRepository>((ref) {
    throw UnimplementedError('TimetableRepository must be provided in main()');
  });

  /// 初始化 Provider
  static final provider = StateNotifierProvider<TimetableStore, TimetableState>(
    (ref) {
      final repo = ref.watch(repoProvider);
      return TimetableStore(repo);
    },
  );

  /// Config Provider (只读，方便 Settings 页面只重建自己)
  static final configProvider = Provider<TimetableConfig>((ref) {
    return ref.watch(timetableProvider).config;
  });

  /// 单格课程列表 Provider (family) - 通过 cellKey 获取该时间段所有课程
  static final cellProvider = Provider.family<List<CourseItem>, String>((
    ref,
    cellKey,
  ) {
    final state = ref.watch(timetableProvider);
    return state.items[cellKey] ?? [];
  });

  /// 所有天的课程 Provider - 返回 Map<dayOfCycle, List<该天所有课程列表>>
  /// 这个 provider 按 dayOfCycle 存储课程，所以所有周期显示相同的课程
  static final allDaySlotsProvider = Provider<Map<int, List<List<CourseItem>>>>((
    ref,
  ) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);

    final result = <int, List<List<CourseItem>>>{};

    for (int dayOfCycle = 0; dayOfCycle < config.daysPerCycle; dayOfCycle++) {
      final slots = <List<CourseItem>>[];
      for (int slot = 0; slot < config.slotsPerDay; slot++) {
        slots.add(state.items['d${dayOfCycle}_s$slot'] ?? []);
      }
      result[dayOfCycle] = slots;
    }

    return result;
  });

  /// 某天所有节次 Provider (family) - 通过 dayOfCycle 获取
  static final daySlotsProvider = Provider.family<List<List<CourseItem>>, int>((
    ref,
    dayOfCycle,
  ) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);

    if (dayOfCycle >= config.daysPerCycle) {
      return [];
    }

    return List.generate(config.slotsPerDay, (slot) {
      return state.items['d${dayOfCycle}_s$slot'] ?? [];
    });
  });

  /// 某周期网格 Provider (family) - 返回 2D 数组 [dayOfCycle][slot]
  /// 每个单元格返回该时间段所有课程中在指定周期可见的第一个课程（用于显示）
  /// 如果没有可见课程，返回 null
  static final cycleGridProvider =
      Provider.family<List<List<CourseItem?>>, int>((ref, cycleIndex) {
        final config = ref.watch(configProvider);
        final state = ref.watch(timetableProvider);

        // 创建 2D 数组: [dayOfCycle][slot]
        final grid = List.generate(config.daysPerCycle, (dayOfCycle) {
          return List.generate(config.slotsPerDay, (slot) {
            final courseList = state.items['d${dayOfCycle}_s$slot'] ?? [];
            // 找第一个在该周期可见的课程
            for (final item in courseList) {
              if (item.isVisibleInCycle(cycleIndex)) {
                return item;
              }
            }
            return null;
          });
        });

        return grid;
      });

  /// 总览数据 Provider - 返回每个周期的摘要
  /// 由于课程按 dayOfCycle 存储，所有周期的课程数相同
  static final overviewProvider = Provider.family<List<CycleSummary>, int>((
    ref,
    _,
  ) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);

    // 计算一天的课程数
    int dayCourseCount = 0;
    for (int slot = 0; slot < config.slotsPerDay; slot++) {
      for (int dayOfCycle = 0; dayOfCycle < config.daysPerCycle; dayOfCycle++) {
        if ((state.items['d${dayOfCycle}_s$slot'] ?? []).isNotEmpty) {
          dayCourseCount++;
        }
      }
    }

    // 所有周期课程数相同
    final summaries = <CycleSummary>[];
    for (int cycle = 0; cycle < config.cycleCount; cycle++) {
      summaries.add(
        CycleSummary(
          cycleIndex: cycle,
          title: TimetableMappers.getCycleTitle(cycle, config.daysPerCycle),
          courseCount: dayCourseCount,
        ),
      );
    }

    return summaries;
  });

  /// 别名
  static final timetableProvider = provider;
}

/// 周期摘要数据
class CycleSummary {
  const CycleSummary({
    required this.cycleIndex,
    required this.title,
    required this.courseCount,
  });

  final int cycleIndex;
  final String title;
  final int courseCount;
}
