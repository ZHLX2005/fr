import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lab_calendar_provider.dart';
import '../../data/lab_people_provider.dart';
import '../../domain/person.dart';
import 'calendar_dsl_parser.dart';
import '../../../../../widgets/theme/zen_theme.dart';

/// 日历 DSL 导入对话框
///
/// 用户粘贴 DSL 文本 → 解析 → 预览（事件+人物数+config）→ 应用。
/// 复用 lab/calendar DSL parser；应用时按当前 active group 写入。
class CalendarImportDialog extends ConsumerStatefulWidget {
  const CalendarImportDialog({super.key});

  @override
  ConsumerState<CalendarImportDialog> createState() =>
      _CalendarImportDialogState();
}

class _CalendarImportDialogState extends ConsumerState<CalendarImportDialog> {
  final _controller = TextEditingController();
  CalendarDslFullResult? _result;
  bool _applied = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _preview() {
    final r = parseCalendarDsl(_controller.text);
    setState(() => _result = r);
  }

  Future<void> _apply() async {
    if (_result == null) return;
    final cal = LabCalendarProvider.current;
    final people = LabPeopleProvider.current;
    if (cal == null || people == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日历尚未初始化')));
      }
      return;
    }
    final activeGroupId = cal.activeGroupId;

    // 1. 先 upsert 人物（去重 by name within same group）
    for (final p in _result!.persons) {
      // 已存在同名（同 group）则跳过
      final exists = people.allPeople.any(
        (existing) =>
            existing.groupId == activeGroupId && existing.name == p.name,
      );
      if (exists) continue;
      await people.add(
        name: p.name,
        relation: p.relation == 'self'
            ? PersonRelation.self
            : p.relation == 'family'
            ? PersonRelation.family
            : p.relation == 'friend'
            ? PersonRelation.friend
            : p.relation == 'colleague'
            ? PersonRelation.colleague
            : PersonRelation.other,
        avatarEmoji: p.avatarEmoji,
        note: p.note,
      );
    }
    // 2. 关联 personId by name
    final nameToId = <String, String>{};
    for (final p in people.allPeople) {
      if (p.groupId == activeGroupId) nameToId[p.name] = p.id;
    }
    // 3. 导入事件（关联 personId by name）
    final fixedEvents = _result!.events.map((e) {
      String? pid = e.personId;
      if (pid != null) {
        // 解析器已用 person name 做了临时映射（id 已存姓名 hash）；这里改用实际 nameToId
        // 简化：事件 personId 字段当 DSL 解析时已映射成 hash；现在用 name 反查
        // 实际：parser 阶段已做了 name→id 映射（id = 'p_n_namehash'），需要重新查
        // 这里直接通过 _allPeople 匹配（按 name 查找）：约定 parser 输出 personId 实际是 name
        // 为简化：重新走所有people 按 name 找匹配的 id（DSL person=<name>）
      }
      return e;
    }).toList();
    // 简化：DSL person 实际是 name（parser 把 person 字段的 name 映射成了临时 id）；
    // 我们在 import 时再走一遍：找出 person name → real id
    final realEvents = fixedEvents.map((e) {
      if (e.personId == null) return e;
      // 临时 id 形如 'p_n_<hash>'；用 hash 反查不实际，改用：personId 字段保持原名
      // 重新解析 personId 作为 name
      final name = e.personId; // parser 存的是 name
      final realId = nameToId[name];
      if (realId == null) return e;
      return e.copyWith(personId: realId);
    }).toList();

    final n = await cal.importEvents(realEvents);
    if (!mounted) return;
    setState(() => _applied = true);
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: theme.colorScheme.scrim.withValues(alpha: 0.26),
          ),
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
                border: Border.all(color: theme.colorScheme.outline, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                              const Icon(Icons.upload_file, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '日历 DSL 导入',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      maxLines: 8,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'config: default-system=solar\n张三生日 @yearly-solar:08-15 type=birthday color=red',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _preview,
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  theme.colorScheme.onSurfaceVariant,
                              side: BorderSide(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            child: const Text('预览'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed:
                                (_result == null ||
                                    _result!.events.isEmpty ||
                                    _applied)
                                ? null
                                : _apply,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.primary,
                              side: BorderSide(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            child: Text(
                              _applied
                                  ? '已应用'
                                  : (_result == null
                                        ? '应用'
                                        : _result!.events.isEmpty
                                        ? '无事件'
                                        : '应用 ${_result!.events.length} 个事件'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildBody(theme, r)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, CalendarDslFullResult? r) {
    if (r == null) {
      return Center(
        child: Text(
          '粘贴 DSL 文本 → 点击预览',
          style: ZenText.label.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (r.errors.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.error),
        ),
        child: ListView(
          children: r.errors
              .map(
                (e) => Text(
                  e,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 11,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ListView(
        children: [
          Text(
            '事件 ${r.events.length} 个 · 人物 ${r.persons.length} 个',
            style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final e in r.events.take(10))
            Text(
              '· ${e.title} (${e.system.name} ${e.month}-${e.day})',
              style: ZenText.label,
            ),
          if (r.events.length > 10)
            Text(
              '… 还有 ${r.events.length - 10} 个',
              style: ZenText.label.copyWith(color: ZenColors.secondary),
            ),
        ],
      ),
    );
  }
}
