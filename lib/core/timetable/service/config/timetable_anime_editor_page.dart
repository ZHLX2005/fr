import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/timetable_store.dart';
import 'anime_dsl_generator.dart';
import '../../../../../widgets/theme/zen_theme.dart';
import '../../../../../widgets/theme/zen_date_picker.dart';

/// 追剧排期编辑页 —— 垂直时间轴视角，剧模型 CRUD（全 zen 主题，fr #26）。
///
/// 剧模型是 SSOT（存储于空间 record）：增删改剧后由 store 自动派生 DSL
/// 并应用到课表（无需手动生成/预览/覆盖）。本页提供只读的 DSL 预览。
class TimetableAnimeEditorPage extends ConsumerStatefulWidget {
  const TimetableAnimeEditorPage({super.key});

  @override
  ConsumerState<TimetableAnimeEditorPage> createState() =>
      _TimetableAnimeEditorPageState();
}

class _TimetableAnimeEditorPageState
    extends ConsumerState<TimetableAnimeEditorPage> {
  List<AnimeSeriesDraft> get _series =>
      ref.watch(TimetableStore.provider).animeSeries;

  Future<void> _addSeries() async {
    final draft = await showDialog<AnimeSeriesDraft>(
      context: context,
      builder: (_) => const _AnimeEditDialog(),
    );
    if (draft != null) {
      await ref.read(TimetableStore.provider.notifier).addAnimeSeries(draft);
    }
  }

  Future<void> _editSeries(AnimeSeriesDraft target) async {
    final draft = await showDialog<AnimeSeriesDraft>(
      context: context,
      builder: (_) => _AnimeEditDialog(initial: target),
    );
    if (draft != null) {
      await ref.read(TimetableStore.provider.notifier).updateAnimeSeries(draft);
    }
  }

  Future<void> _deleteSeries(AnimeSeriesDraft target) async {
    final ok = await ZenConfirmDialog.show(
      context: context,
      title: '删除剧',
      message: '确定删除「${target.title}」吗？',
      confirmLabel: '删除',
      onConfirm: () {},
    );
    if (ok == true) {
      await ref
          .read(TimetableStore.provider.notifier)
          .deleteAnimeSeries(target.id);
    }
  }

  /// 只读 DSL 预览（当前剧模型派生的结果）
  Future<void> _previewDsl() async {
    final series = _series;
    if (series.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('还没有剧，先添加一部吧')));
      return;
    }
    final result = buildAnimeDsl(
      series.map((s) => s.toInput()).toList(growable: false),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ZenColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: ZenColors.hair),
        ),
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前追剧 DSL', style: ZenText.title),
              const SizedBox(height: 8),
              Text(
                '起始 ${result.config.startDateIso} · '
                '每天 ${result.config.slotsPerDay} 行 · '
                '共 ${result.config.cycleCount} 周 · 已自动应用',
                style: ZenText.label,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZenColors.sage.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZenColors.hair),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    result.dsl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.5,
                      color: ZenColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '关闭',
                    style: ZenText.button.copyWith(color: ZenColors.secondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = _series;
    final sorted = List<AnimeSeriesDraft>.from(series)
      ..sort((a, b) => a.time.compareTo(b.time));
    final summary = series.isEmpty
        ? ''
        : () {
            final r = buildAnimeDsl(
              series.map((s) => s.toInput()).toList(growable: false),
            );
            return '起始 ${r.config.startDateIso}（周一） · '
                '每天 ${r.config.slotsPerDay} 行 · '
                '共 ${r.config.cycleCount} 周';
          }();

    return zenPageScaffold(
      title: '追剧排期',
      actions: [
        TextButton.icon(
          onPressed: _previewDsl,
          icon: const Icon(Icons.visibility_outlined,
              size: 18, color: ZenColors.sage),
          label: Text(
            '查看 DSL',
            style: ZenText.button.copyWith(color: ZenColors.sage, fontSize: 14),
          ),
        ),
      ],
      fab: FloatingActionButton.extended(
        onPressed: _addSeries,
        backgroundColor: ZenColors.sage,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('添加剧'),
      ),
      body: Column(
        children: [
          // 自动派生摘要条（剧变更即时自动应用，这里只展示结果）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ZenColors.sage.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: ZenColors.sage,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    series.isEmpty
                        ? '添加剧后自动计算并应用排期'
                        : '已自动应用：$summary · ${series.length} 部剧',
                    style: ZenText.body.copyWith(
                      color: ZenColors.sage,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: ZenColors.hair),
          Expanded(
            child: sorted.isEmpty
                ? ZenEmptyState(
                    icon: Icons.movie_filter_outlined,
                    message: '还没有剧\n添加后自动计算并应用排期（起始日期/行数/周数）',
                    actionLabel: '添加第一部剧',
                    onAction: _addSeries,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: sorted.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final s = sorted[index];
                      return _SeriesTile(
                        draft: s,
                        onEdit: () => _editSeries(s),
                        onDelete: () => _deleteSeries(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 垂直时间轴行：左侧时间标签 + 剧信息
class _SeriesTile extends StatelessWidget {
  final AnimeSeriesDraft draft;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SeriesTile({
    required this.draft,
    required this.onEdit,
    required this.onDelete,
  });

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final title = draft.title.trim().isEmpty ? '（未命名剧）' : draft.title.trim();

    return Container(
      decoration: zenCard(),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: ZenColors.sage.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  draft.time.trim().isEmpty ? '--:--' : draft.time.trim(),
                  style: ZenText.body.copyWith(
                    color: ZenColors.sage,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '周${_weekdayNames[draft.weekday - 1]} · '
                      '${draft.episodes} 期 · '
                      '每期 ${draft.durationMin} 分钟 · '
                      '${draft.startDateIso} 开播',
                      style: ZenText.label.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: ZenColors.secondary),
                visualDensity: VisualDensity.compact,
                tooltip: '编辑',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: ZenColors.mutedRed),
                visualDensity: VisualDensity.compact,
                tooltip: '删除',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// zen 风格输入框装饰 —— 编辑弹窗内统一使用
InputDecoration _zenInputDecoration(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: ZenText.label,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: ZenColors.hair),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: ZenColors.hair),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: ZenColors.sage),
      ),
    );

/// 剧编辑对话框 —— 字段全部是"剧的语言"，无任何课表概念（全 zen 主题）
class _AnimeEditDialog extends StatefulWidget {
  final AnimeSeriesDraft? initial;

  const _AnimeEditDialog({this.initial});

  @override
  State<_AnimeEditDialog> createState() => _AnimeEditDialogState();
}

class _AnimeEditDialogState extends State<_AnimeEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _episodesCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _currentEpisodeCtrl;
  late int _weekday;
  bool _useBackfill = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i?.title ?? '');
    _dateCtrl = TextEditingController(text: i?.startDateIso ?? '');
    _timeCtrl = TextEditingController(text: i?.time ?? '');
    _episodesCtrl = TextEditingController(text: i?.episodes.toString() ?? '13');
    _durationCtrl = TextEditingController(
      text: (i?.durationMin ?? 45).toString(),
    );
    _currentEpisodeCtrl = TextEditingController();
    _weekday = i?.weekday ?? 1;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _episodesCtrl.dispose();
    _durationCtrl.dispose();
    _currentEpisodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_dateCtrl.text);
    final picked = await showZenDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      title: '开播日期',
    );
    if (picked == null) return;
    setState(() {
      _dateCtrl.text = picked.toIso8601String().split('T')[0];
    });
  }

  void _backfill() {
    final ep = int.tryParse(_currentEpisodeCtrl.text.trim());
    if (ep == null || ep < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入当前期数（正整数）')),
      );
      return;
    }
    setState(() {
      _dateCtrl.text = backfillStartDate(ep, _weekday);
    });
  }

  AnimeSeriesDraft? _submit() {
    final title = _titleCtrl.text.trim();
    final startDateIso = _dateCtrl.text.trim();
    // 时间自动对齐（fr #25）："22" → "22:00"、"2230" → "22:30"
    final time = normalizeAnimeTimeInput(_timeCtrl.text);
    final episodes = int.tryParse(_episodesCtrl.text.trim());
    final duration = int.tryParse(_durationCtrl.text.trim());
    if (title.isEmpty || startDateIso.isEmpty || time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧名、开播日期、播出时间必填')),
      );
      return null;
    }
    if (DateTime.tryParse(startDateIso) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开播日期无效')),
      );
      return null;
    }
    // 对齐结果回填输入框，让用户看到最终生效的时间
    _timeCtrl.text = time;
    return AnimeSeriesDraft(
      id: widget.initial?.id,
      title: title,
      startDateIso: startDateIso,
      weekday: _weekday,
      time: time,
      episodes: (episodes ?? 13).clamp(1, 999),
      durationMin: (duration ?? 45).clamp(1, 600),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ZenColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: ZenColors.hair),
      ),
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? '添加剧' : '编辑剧',
                style: ZenText.title,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                autofocus: widget.initial == null,
                style: ZenText.body,
                decoration: _zenInputDecoration('剧名（番名）'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _useBackfill
                        ? TextField(
                            controller: _currentEpisodeCtrl,
                            keyboardType: TextInputType.number,
                            style: ZenText.body,
                            decoration:
                                _zenInputDecoration('当前第几期'),
                          )
                        : InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(6),
                            child: InputDecorator(
                              decoration: _zenInputDecoration('开播日期'),
                              child: Text(
                                _dateCtrl.text.isEmpty
                                    ? '选择日期'
                                    : _dateCtrl.text,
                                style: _dateCtrl.text.isEmpty
                                    ? ZenText.label
                                    : ZenText.body,
                              ),
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _useBackfill = !_useBackfill;
                      if (!_useBackfill) _currentEpisodeCtrl.clear();
                    }),
                    child: Text(
                      _useBackfill ? '直接选日期' : '当前第N期反推',
                      style: ZenText.button
                          .copyWith(color: ZenColors.sage, fontSize: 12),
                    ),
                  ),
                  if (_useBackfill)
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high,
                          size: 18, color: ZenColors.sage),
                      tooltip: '反推并填入',
                      onPressed: _backfill,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _weekday,
                      isDense: true,
                      style: ZenText.body.copyWith(fontSize: 14),
                      decoration: _zenInputDecoration('星期几'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('周一')),
                        DropdownMenuItem(value: 2, child: Text('周二')),
                        DropdownMenuItem(value: 3, child: Text('周三')),
                        DropdownMenuItem(value: 4, child: Text('周四')),
                        DropdownMenuItem(value: 5, child: Text('周五')),
                        DropdownMenuItem(value: 6, child: Text('周六')),
                        DropdownMenuItem(value: 7, child: Text('周日')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _weekday = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _timeCtrl,
                      keyboardType: TextInputType.datetime,
                      style: ZenText.body,
                      decoration: _zenInputDecoration('几点播出（22→22:00）'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _episodesCtrl,
                      keyboardType: TextInputType.number,
                      style: ZenText.body,
                      decoration: _zenInputDecoration('总集数'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _durationCtrl,
                      keyboardType: TextInputType.number,
                      style: ZenText.body,
                      decoration: _zenInputDecoration('每集分钟'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '取消',
                      style: ZenText.button.copyWith(color: ZenColors.secondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final draft = _submit();
                      if (draft != null) Navigator.pop(context, draft);
                    },
                    child: Text(
                      '保存',
                      style: ZenText.button.copyWith(
                        color: ZenColors.sage,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
