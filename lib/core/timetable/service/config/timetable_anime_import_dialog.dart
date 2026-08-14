import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../domain/models.dart';
import '../../presentation/timetable_store.dart';
import '../../presentation/timetable_colors.dart';
import '../../../design/emphasis_button.dart';

/// 新番（动画更新时间表）导入对话框
///
/// 数据源：Bangumi 公开日历 API `https://api.bgm.tv/calendar`，
/// 返回按星期分组的本季新番列表。勾选导入为课表：
/// dayOfCycle = 星期（0=周一），title = 中文名优先，location = 开播日期。
class TimetableAnimeImportDialog extends ConsumerStatefulWidget {
  const TimetableAnimeImportDialog({super.key});

  @override
  ConsumerState<TimetableAnimeImportDialog> createState() =>
      _TimetableAnimeImportDialogState();
}

/// 星期分组的新番条目
class _AnimeDayGroup {
  final int weekdayIndex; // 0=周一 ... 6=周日
  final List<_AnimeItem> items;
  const _AnimeDayGroup({required this.weekdayIndex, required this.items});
}

class _AnimeItem {
  final int id;
  final String name; // 日文名
  final String? nameCn; // 中文名
  final String? airDate; // 开播日期 YYYY-MM-DD
  final int airWeekday; // bangumi: 0=周日 ... 6=周六

  _AnimeItem({
    required this.id,
    required this.name,
    this.nameCn,
    this.airDate,
    required this.airWeekday,
  });

  String get displayName => (nameCn != null && nameCn!.isNotEmpty) ? nameCn! : name;

  /// 0=周一 ... 6=周日
  int get dayOfCycle => airWeekday == 0 ? 6 : airWeekday - 1;
}

class _TimetableAnimeImportDialogState
    extends ConsumerState<TimetableAnimeImportDialog> {
  bool _loading = false;
  String? _error;
  List<_AnimeDayGroup> _groups = [];
  final Set<int> _selectedIds = {};

  static const _apiUrl = 'https://api.bgm.tv/calendar';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'User-Agent': 'xiaodouzi-fr/1.0 (timetable anime adapter)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;

      final groups = <_AnimeDayGroup>[];
      for (int i = 0; i < data.length; i++) {
        final day = data[i] as Map<String, dynamic>;
        final itemsJson = day['items'] as List<dynamic>? ?? [];
        final items = <_AnimeItem>[];
        for (final raw in itemsJson) {
          final m = raw as Map<String, dynamic>;
          final item = _AnimeItem(
            id: m['id'] as int,
            name: m['name'] as String? ?? '未知动画',
            nameCn: m['name_cn'] as String?,
            airDate: m['air_date'] as String?,
            airWeekday: (m['air_weekday'] as int?) ?? (i + 1) % 7,
          );
          items.add(item);
        }
        if (items.isNotEmpty) {
          groups.add(_AnimeDayGroup(weekdayIndex: i, items: items));
        }
      }

      if (mounted) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '拉取新番列表失败: $e\n（需要网络；可稍后重试）';
        });
      }
    }
  }

  int get _selectedCount => _selectedIds.length;

  Future<void> _doImport() async {
    final selected = <_AnimeItem>[];
    for (final group in _groups) {
      for (final item in group.items) {
        if (_selectedIds.contains(item.id)) selected.add(item);
      }
    }
    if (selected.isEmpty) return;

    final store = ref.read(TimetableStore.provider.notifier);
    final config = ref.read(TimetableStore.configProvider);

    // 每星期的序号分配（0 起）；跨天独立计数
    final slotCursor = <int>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    final courses = <CourseItem>[];
    for (final item in selected) {
      final slotIndex = slotCursor.length;
      slotCursor.add(slotIndex);
      courses.add(
        CourseItem(
          id: 'anime_${item.id}_$now',
          dayOfCycle: item.dayOfCycle,
          slotIndex: slotIndex,
          title: item.displayName,
          location: item.airDate ?? '每周更新',
          colorSeed: item.id % 1000,
          version: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // 确保行列能容纳：daysPerCycle=7（按周目录），slotsPerDay 至少覆盖最大序号
    final neededSlots = courses.map((c) => c.slotIndex).fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final newDays = config.daysPerCycle < 7 ? 7 : config.daysPerCycle;
    final newSlots = config.slotsPerDay < neededSlots ? neededSlots : config.slotsPerDay;
    if (newDays != config.daysPerCycle || newSlots != config.slotsPerDay) {
      await store.updateConfig(
        daysPerCycle: newDays,
        slotsPerDay: newSlots,
        startDateIso: config.startDateIso,
      );
    }

    final grouped = <String, List<CourseItem>>{};
    for (final course in courses) {
      grouped.putIfAbsent(course.cellKey, () => []).add(course);
    }
    for (final entry in grouped.entries) {
      await store.upsertItems(entry.key, entry.value);
    }

    if (mounted) {
      Navigator.pop(context, courses.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.black26),
        ),
        Center(
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: Container(
              width: 360,
              height: 480,
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
                              const Icon(Icons.movie_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '新番导入',
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
                  // 内容
                  Expanded(
                    child: _buildBody(theme),
                  ),
                  const Divider(height: 1),
                  // 底部操作
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedCount > 0
                                ? '已选 $_selectedCount 部'
                                : '勾选要追踪的新番',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: TimetableColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _fetch,
                          child: const Text('刷新'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed:
                                _selectedCount > 0 && !_loading ? _doImport : null,
                            style: EmphasisButton.borderEmphasis(
                              context,
                              color: TimetableColors.accent,
                            ),
                            child: Text(
                              _selectedCount > 0 ? '导入 $_selectedCount 部' : '导入',
                            ),
                          ),
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

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: TimetableColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _fetch, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _groups.length,
      itemBuilder: (context, groupIdx) {
        final group = _groups[groupIdx];
        final dayName = weekdayNames[group.weekdayIndex % 7];
        final daySelected = group.items
            .where((i) => _selectedIds.contains(i.id))
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TimetableColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dayName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: TimetableColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${group.items.length} 部${daySelected > 0 ? ' · 已选 $daySelected' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: TimetableColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            ...group.items.map(
              (item) => CheckboxListTile(
                dense: true,
                value: _selectedIds.contains(item.id),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedIds.add(item.id);
                    } else {
                      _selectedIds.remove(item.id);
                    }
                  });
                },
                title: Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  item.airDate ?? '更新日 ${item.dayOfCycle + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: TimetableColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
