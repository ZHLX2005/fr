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
  final Map<String, CourseItem> items; // 按 cellKey 索引
  final bool isLoading;

  TimetableState copyWith({
    TimetableConfig? config,
    Map<String, CourseItem>? items,
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
  TimetableStore(this._repo) : super(const TimetableState(
    config: TimetableConfig.defaultConfig,
    items: {},
    isLoading: false,
  ));

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
      final itemsList = await _repo.loadItems();
      final items = {for (var item in itemsList) item.cellKey: item};

      state = TimetableState(
        config: config,
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = TimetableState(
        config: TimetableConfig.defaultConfig,
        items: {},
        isLoading: false,
      );
    }
  }

  /// 新增或更新课程项目
  Future<void> upsertItem(CourseItem item) async {
    final newItems = Map<String, CourseItem>.from(state.items);
    newItems[item.cellKey] = item;

    // 立即更新 UI (optimistic update)
    state = state.copyWith(items: newItems);

    // 持久化
    try {
      await _repo.upsertItem(item);
    } catch (e) {
      // 失败则回滚 (简化处理)
      newItems.remove(item.cellKey);
      state = state.copyWith(items: newItems);
    }
  }

  /// 删除课程项目
  Future<void> deleteItem(String cellKey) async {
    final newItems = Map<String, CourseItem>.from(state.items);
    final deletedItem = newItems.remove(cellKey);

    if (deletedItem == null) return;

    state = state.copyWith(items: newItems);

    try {
      await _repo.deleteItem(cellKey);
    } catch (e) {
      // 失败则恢复
      newItems[cellKey] = deletedItem;
      state = state.copyWith(items: newItems);
    }
  }

  /// 更新配置
  Future<String?> updateConfig({
    String? startDateIso,
    int? cycleCount,
    int? daysPerCycle,
    int? slotsPerDay,
  }) async {
    final oldConfig = state.config;
    final oldTotalDays = oldConfig.totalDays;

    final newConfig = oldConfig.copyWith(
      startDateIso: startDateIso,
      cycleCount: cycleCount?.clamp(TimetableConfig.minCycles, TimetableConfig.maxCycles),
      daysPerCycle: daysPerCycle?.clamp(TimetableConfig.minDaysPerCycle, TimetableConfig.maxDaysPerCycle),
      slotsPerDay: slotsPerDay?.clamp(TimetableConfig.minSlotsPerDay, TimetableConfig.maxSlotsPerDay),
    );

    final newTotalDays = newConfig.totalDays;
    final hasDaysReduced = newTotalDays < oldTotalDays;

    // 处理越界数据
    final newItems = Map<String, CourseItem>.from(state.items);
    final deletedKeys = <String>[];

    if (hasDaysReduced) {
      newItems.removeWhere((key, item) {
        final shouldDelete = item.dayIndex >= newTotalDays;
        if (shouldDelete) {
          deletedKeys.add(key);
        }
        return shouldDelete;
      });
    }

    // 保存配置
    await _repo.saveConfig(newConfig);

    // 保存更新后的 items
    await _repo.saveItems(newItems.values.toList());

    state = state.copyWith(config: newConfig, items: newItems);

    if (deletedKeys.isNotEmpty) {
      return '配置缩小，已删除 ${deletedKeys.length} 个超出范围的项目';
    }

    return null;
  }

  /// Repository Provider
  static final repoProvider = Provider<TimetableRepository>((ref) {
    throw UnimplementedError('TimetableRepository must be provided in main()');
  });

  /// 初始化 Provider
  static final provider = StateNotifierProvider<TimetableStore, TimetableState>((ref) {
    final repo = ref.watch(repoProvider);
    return TimetableStore(repo);
  });

  /// Config Provider (只读，方便 Settings 页面只重建自己)
  static final configProvider = Provider<TimetableConfig>((ref) {
    return ref.watch(timetableProvider).config;
  });

  /// 单格 Provider (family)
  static final cellProvider = Provider.family<CourseItem?, String>((ref, cellKey) {
    final state = ref.watch(timetableProvider);
    return state.items[cellKey];
  });

  /// 某天所有节次 Provider (family)
  static final daySlotsProvider = Provider.family<List<CourseItem?>, int>((ref, dayIndex) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);
    final items = <CourseItem?>[];

    for (int slot = 0; slot < config.slotsPerDay; slot++) {
      items.add(state.items['d${dayIndex}_s$slot']);
    }

    return items;
  });

  /// 某周期网格 Provider (family) - 返回 2D 数组
  static final cycleGridProvider = Provider.family<List<List<CourseItem?>>, int>((ref, cycleIndex) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);

    // 创建 2D 数组: [dayOfCycle][slot]
    final grid = List.generate(
      config.daysPerCycle,
      (dayOfCycle) {
        final dayIndex = TimetableMappers.cycleToDayIndex(cycleIndex, dayOfCycle, config.daysPerCycle);
        return List.generate(config.slotsPerDay, (slot) {
          return state.items['d$dayIndex\_s$slot'];
        });
      },
    );

    return grid;
  });

  /// 总览数据 Provider - 返回每个周期的摘要
  static final overviewProvider = Provider.family<List<CycleSummary>, int>((ref, _) {
    final config = ref.watch(configProvider);
    final state = ref.watch(timetableProvider);

    final summaries = <CycleSummary>[];

    for (int cycle = 0; cycle < config.cycleCount; cycle++) {
      int courseCount = 0;
      final startDay = cycle * config.daysPerCycle;
      final endDay = startDay + config.daysPerCycle - 1;

      for (int day = startDay; day <= endDay; day++) {
        for (int slot = 0; slot < config.slotsPerDay; slot++) {
          if (state.items['d${day}_s$slot'] != null) {
            courseCount++;
          }
        }
      }

      summaries.add(CycleSummary(
        cycleIndex: cycle,
        title: TimetableMappers.getCycleTitle(cycle, config.daysPerCycle),
        courseCount: courseCount,
      ));
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
