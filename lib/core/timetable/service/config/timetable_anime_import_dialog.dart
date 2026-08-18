import 'package:flutter/material.dart';
import '../../../../../widgets/context_colors.dart';
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
  AnimeSeason _season = currentAnimeSeason();
  late int _year = DateTime.now().year;
  List<AnimeDraft> _drafts = [];
  final Set<String> _selectedKeys = {};

  /// 年份选择范围：当前年 ± 2（追剧场景不需要更早/更远）
  static List<int> get _yearOptions {
    final now = DateTime.now().year;
    return [now + 1, now, now - 1, now - 2];
  }

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
      final drafts = await _adapter.fetchSeason(_season, _year);
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
          child: Container(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.26)),
        ),
        Center(
          child: Material(
            elevation: 4,
            color: context.colors.surface,
            // Material 断言禁止 shape 与 borderRadius 同时传（fr 28 修复崩溃）；
            // 圆角由 shape 自带
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: context.colors.outline),
            ),
            child: Container(
              width: 360,
              height: 500,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.outline, width: 1),
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
                              color: context.colors.outline,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.movie_outlined,
                                  size: 16, color: context.colors.accent),
                              SizedBox(width: 6),
                              Text('番剧导入', style: ZenText.title),
                            ],
                          ),
                        ),
                        Spacer(),
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
                          icon: Icon(Icons.close,
                              size: 20, color: context.colors.textMuted),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.colors.outline),
                  // 季节 / 年份 选择（fr 28 扩展）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Text('季节', style: ZenText.label.copyWith(fontSize: 12)),
                        const SizedBox(width: 8),
                        DropdownButton<AnimeSeason>(
                          value: _season,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: ZenText.body.copyWith(fontSize: 13),
                          items: [
                            for (final s in AnimeSeason.values)
                              DropdownMenuItem(
                                value: s,
                                child: Text('${s.label}季',
                                    style:
                                        ZenText.body.copyWith(fontSize: 13)),
                              ),
                          ],
                          onChanged: (s) {
                            if (s == null || s == _season) return;
                            setState(() => _season = s);
                            _fetch();
                          },
                        ),
                        SizedBox(width: 16),
                        Text('年份', style: ZenText.label.copyWith(fontSize: 12)),
                        SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _year,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: ZenText.body.copyWith(fontSize: 13),
                          items: [
                            for (final y in _yearOptions)
                              DropdownMenuItem(
                                value: y,
                                child: Text('$y',
                                    style:
                                        ZenText.body.copyWith(fontSize: 13)),
                              ),
                          ],
                          onChanged: (y) {
                            if (y == null || y == _year) return;
                            setState(() => _year = y);
                            _fetch();
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.colors.outline),
                  // 内容
                  Expanded(child: _buildBody()),
                  Divider(height: 1, color: context.colors.outline),
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
                                color: context.colors.textMuted, fontSize: 14),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: _selectedCount > 0 && !_loading
                                ? _doConfirm
                                : null,
                            style: zenButtonTheme(context,
                              foreground: context.colors.accent,
                              border: context.colors.accent.withValues(alpha: 0.5),
                            ),
                            child: Text(
                              _selectedCount > 0
                                  ? '添加 $_selectedCount 部'
                                  : '添加',
                              style: ZenText.button
                                  .copyWith(color: context.colors.accent),
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
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.colors.accent,
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
              Icon(
                Icons.cloud_off,
                size: 40,
                color: context.colors.textMuted,
              ),
              SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: ZenText.label.copyWith(fontSize: 12),
              ),
              SizedBox(height: 12),
              OutlinedButton(
                onPressed: _fetch,
                style: zenButtonTheme(context,
                  foreground: context.colors.accent,
                  border: context.colors.accent.withValues(alpha: 0.5),
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
          activeColor: context.colors.accent,
          checkColor: Theme.of(context).colorScheme.surface,
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
