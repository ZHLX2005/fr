import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'anime_source_adapter.dart';
import '../../presentation/timetable_colors.dart';
import '../../../design/emphasis_button.dart';

/// 番剧开放 API 来源导入对话框
///
/// 通过 [kAnimeSourceAdapters] 选择来源 → 拉取番剧列表 → 勾选 →
/// 返回选中草稿（List[AnimeDraft]），由设置页追剧区填充为剧行。
class TimetableAnimeImportDialog extends ConsumerStatefulWidget {
  const TimetableAnimeImportDialog({super.key});

  @override
  ConsumerState<TimetableAnimeImportDialog> createState() =>
      _TimetableAnimeImportDialogState();
}

class _TimetableAnimeImportDialogState
    extends ConsumerState<TimetableAnimeImportDialog> {
  bool _loading = false;
  String? _error;
  AnimeSourceAdapter _adapter = kAnimeSourceAdapters.first;
  List<AnimeDraft> _drafts = [];
  final Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String _keyOf(AnimeDraft d) =>
      '${d.title}_${d.startDateIso}_${d.weekday}';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _drafts = [];
      _selectedKeys.clear();
    });
    try {
      final drafts = await _adapter.fetch();
      if (mounted) {
        setState(() {
          _drafts = drafts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '拉取 ${_adapter.label} 失败: $e\n（需要网络；可稍后重试）';
        });
      }
    }
  }

  int get _selectedCount => _selectedKeys.length;

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
              height: 500,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TimetableColors.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
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
                                '番剧导入',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: TimetableColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // 来源切换
                        DropdownButton<String>(
                          value: _adapter.id,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final a in kAnimeSourceAdapters)
                              DropdownMenuItem(
                                value: a.id,
                                child: Text(a.label, style: const TextStyle(fontSize: 13)),
                              ),
                          ],
                          onChanged: (id) {
                            if (id == null || id == _adapter.id) return;
                            final next = kAnimeSourceAdapters.firstWhere(
                              (a) => a.id == id,
                            );
                            setState(() => _adapter = next);
                            _fetch();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 内容
                  Expanded(child: _buildBody(theme)),
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
                                : '勾选要追踪的番剧（缺播出时间可在下一步补）',
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
                            onPressed: _selectedCount > 0 && !_loading
                                ? _doConfirm
                                : null,
                            style: EmphasisButton.borderEmphasis(
                              context,
                              color: TimetableColors.accent,
                            ),
                            child: Text(
                              _selectedCount > 0 ? '添加 $_selectedCount 部' : '添加',
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

  void _doConfirm() {
    final selected = _drafts
        .where((d) => _selectedKeys.contains(_keyOf(d)))
        .toList();
    Navigator.pop(context, selected);
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
    if (_drafts.isEmpty) {
      return const Center(child: Text('该来源暂无数据'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _drafts.length,
      itemBuilder: (context, index) {
        final draft = _drafts[index];
        final key = _keyOf(draft);
        final isSelected = _selectedKeys.contains(key);
        return CheckboxListTile(
          dense: true,
          value: isSelected,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedKeys.add(key);
              } else {
                _selectedKeys.remove(key);
              }
            });
          },
          title: Text(
            draft.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            [
              if (draft.startDateIso != null) draft.startDateIso!,
              if (draft.weekday != null) '周${draft.weekday!}',
              if (draft.time != null) draft.time!,
              if (draft.episodes != null) '${draft.episodes}期',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: TimetableColors.textTertiary,
            ),
          ),
        );
      },
    );
  }
}
