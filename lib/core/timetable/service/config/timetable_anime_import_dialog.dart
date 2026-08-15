import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'anime_source_adapter.dart';
import '../../../../../widgets/theme/zen_theme.dart';

/// 番剧开放 API 来源导入对话框（全 zen 主题，fr #26）
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
    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.black26),
        ),
        Center(
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: ZenColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: ZenColors.hair),
            ),
            child: Container(
              width: 360,
              height: 500,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ZenColors.hair, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: ZenColors.hair,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_outlined,
                                  size: 16, color: ZenColors.sage),
                              SizedBox(width: 6),
                              Text('番剧导入', style: ZenText.title),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // 来源切换
                        DropdownButton<String>(
                          value: _adapter.id,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: ZenText.body.copyWith(fontSize: 13),
                          items: [
                            for (final a in kAnimeSourceAdapters)
                              DropdownMenuItem(
                                value: a.id,
                                child: Text(a.label,
                                    style:
                                        ZenText.body.copyWith(fontSize: 13)),
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
                          icon: const Icon(Icons.close,
                              size: 20, color: ZenColors.secondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: ZenColors.hair),
                  // 内容
                  Expanded(child: _buildBody()),
                  const Divider(height: 1, color: ZenColors.hair),
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
                            style: ZenText.label.copyWith(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _fetch,
                          child: Text(
                            '刷新',
                            style: ZenText.button.copyWith(
                                color: ZenColors.secondary, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: _selectedCount > 0 && !_loading
                                ? _doConfirm
                                : null,
                            style: zenButton(
                              foreground: ZenColors.sage,
                              border: ZenColors.sage.withValues(alpha: 0.5),
                            ),
                            child: Text(
                              _selectedCount > 0
                                  ? '添加 $_selectedCount 部'
                                  : '添加',
                              style: ZenText.button
                                  .copyWith(color: ZenColors.sage),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ZenColors.sage,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off,
                size: 40,
                color: ZenColors.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: ZenText.label.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _fetch,
                style: zenButton(
                  foreground: ZenColors.sage,
                  border: ZenColors.sage.withValues(alpha: 0.5),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_drafts.isEmpty) {
      return Center(
        child: Text('该来源暂无数据', style: ZenText.label),
      );
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
          activeColor: ZenColors.sage,
          checkColor: Colors.white,
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
            style: ZenText.body.copyWith(
              fontSize: 14,
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
            style: ZenText.label.copyWith(fontSize: 11),
          ),
        );
      },
    );
  }
}
