import 'package:flutter/material.dart';

import '../../../core/ai_chat/receipt_ocr/receipt_ocr_models.dart';
import '../../../core/schema/schema.dart';
import '../../../core/storage/hive/price_compare_repository.dart';
import '../../../lab/demos/price_compare/price_compare_models.dart';
import '../../../lab/demos/price_compare/price_topic_picker_sheet.dart';
import '../interfaces/interfaces.dart';
import '../data/receipt_ocr_message_data.dart';

/// 小票 OCR 消息策略：每行 pending → recorded / rejected；
/// 底部提供「打开比价计算器」schema 跳链。
class ReceiptOcrMessageWidgetStrategy
    extends MessageWidgetStrategy<ReceiptOcrMessageData> {
  @override
  Widget build(BuildContext context, ReceiptOcrMessageData data) {
    return _ReceiptOcrContent(data: data);
  }

  @override
  ReceiptOcrMessageData createMockData() => ReceiptOcrMessageData(
        result: ReceiptResult(
          storeName: '盒马鲜生',
          purchasedAt: DateTime.now(),
          recommendedTopic: '日常水果',
          items: const [
            LineItem(resource: '红富士苹果', quantity: 2, unitPrice: 5.5, note: '盒马'),
            LineItem(resource: '进口香蕉',   quantity: 1, unitPrice: 12.8, note: '盒马'),
            LineItem(resource: '泰国椰青',   quantity: 3, unitPrice: 9.9, note: '盒马'),
          ],
        ),
      );
}

class _ReceiptOcrContent extends StatefulWidget {
  final ReceiptOcrMessageData data;
  const _ReceiptOcrContent({required this.data});

  @override
  State<_ReceiptOcrContent> createState() => _ReceiptOcrContentState();
}

class _ReceiptOcrContentState extends State<_ReceiptOcrContent> {
  late final List<ReceiptLineStatus> _statuses;
  /// 行 i 已记入到的主题 ID（Hive box 的 key）。null = 未记入 / 待修改。
  late final List<String?> _recordedTopicIds;
  /// 行 i 当前显示的主题标题（首次 = item.defaultTopic；改主题后会变）。
  late final List<String> _topicTitles;

  @override
  void initState() {
    super.initState();
    final items = widget.data.result.items;
    final n = items.length;
    _statuses = List<ReceiptLineStatus>.filled(n, ReceiptLineStatus.pending);
    _recordedTopicIds = List<String?>.filled(n, null);
    // 初始显示主题：优先 LLM 推断的 default_topic，否则暂用 recommendedTopic，最后兜底 '默认'
    _topicTitles = List<String>.generate(n, (i) {
      final t = items[i].defaultTopic;
      if (t.isNotEmpty) return t;
      final r = widget.data.result.recommendedTopic;
      return r.isNotEmpty ? r : '默认';
    });
    _refreshSummariesCache();
  }

  /// ✓ 记入 —— 优先按默认主题（default_topic）落库，无 default_topic 时才弹选择器。
  /// 后端 LLM 已给主题就是为了省心智；用户主动改主题才弹 PickerSheet。
  ///
  /// 落库语义：找到/新建同名主题 → 追加一行 PriceRow（资源/金额/备注）。
  Future<void> _onTapRecord(int i) async {
    if (_statuses[i] != ReceiptLineStatus.pending) return;
    final proposed = _topicTitles[i];

    // 缺省主题：弹 picker 让用户选
    if (proposed.isEmpty || proposed == '默认') {
      await _showPickerAndRecord(i);
      return;
    }

    // 默认主题流程：find-or-create 同名主题 → 追加一行 → 标记 recorded
    final item = widget.data.result.items[i];
    final topicId =
        await PriceCompareRepository.instance.findOrCreateTopic(proposed);
    await PriceCompareRepository.instance.appendRow(
      topicId,
      row: _rowFromItem(item),
      fallbackTitle: proposed,
    );
    if (!mounted) return;
    setState(() {
      _statuses[i] = ReceiptLineStatus.recorded;
      _recordedTopicIds[i] = topicId;
    });
  }

  /// 把后端 item 映射成比价器的 PriceRow。
  /// amount = unit_price * quantity（小计），便于比价器立刻能对比。
  PriceRow _rowFromItem(LineItem item) => PriceRow(
        resource: item.resource,
        amount: (item.unitPrice * item.quantity).toStringAsFixed(2),
        note: item.note,
      );

  /// 用户主动改主题（点击芯片触发）—— 弹 PickerSheet。
  Future<void> _changeTopic(int i) async {
    if (!mounted) return;
    final wasRecorded = _statuses[i] == ReceiptLineStatus.recorded;
    final oldId = _recordedTopicIds[i];
    final oldTitle = _topicTitles[i];

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return PriceTopicPickerSheet(
          summaries: _summariesCache,
          currentId: oldId,
          onNew: () => Navigator.pop(sheetCtx, '__new__'),
          onDelete: (id) async {
            await PriceCompareRepository.instance.deleteTopic(id);
            if (!sheetCtx.mounted) return;
            Navigator.pop(sheetCtx, '__deleted__:$id');
          },
        );
      },
    );
    if (!mounted) return;
    if (picked == null) return;
    if (picked == '__new__') {
      // 新建：用旧标题（或 default_topic）
      final title = oldTitle.isNotEmpty ? oldTitle : '新主题';
      final id = await PriceCompareRepository.instance.createEmptyTopic(title: title);
      setState(() {
        _recordedTopicIds[i] = id;
        _topicTitles[i] = title;
        _statuses[i] = ReceiptLineStatus.recorded;
      });
      return;
    }
    if (picked.startsWith('__deleted__:')) return;
    final s = _summariesCache.firstWhere(
      (e) => e.id == picked,
      orElse: () => const PriceTopicSummary(
          id: '', title: '未命名主题', rowCount: 0, createdAt: null),
    );
    setState(() {
      _recordedTopicIds[i] = s.id;
      _topicTitles[i] = s.title.isEmpty ? '未命名主题' : s.title;
      if (!wasRecorded) _statuses[i] = ReceiptLineStatus.recorded;
    });
  }

  /// 兜底流程：原本的 PickerSheet 选主题（仅在 default_topic 为空时使用）
  Future<void> _showPickerAndRecord(int i) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => PriceTopicPickerSheet(
        summaries: _summariesCache,
        currentId: null,
        onNew: () => Navigator.pop(sheetCtx, '__new__'),
        onDelete: (id) async {
          await PriceCompareRepository.instance.deleteTopic(id);
          if (!sheetCtx.mounted) return;
          Navigator.pop(sheetCtx, '__deleted__:$id');
        },
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == '__new__') {
      final id = await PriceCompareRepository.instance.createEmptyTopic();
      setState(() {
        _recordedTopicIds[i] = id;
        _topicTitles[i] = '新主题';
        _statuses[i] = ReceiptLineStatus.recorded;
      });
      return;
    }
    if (picked.startsWith('__deleted__:')) return;
    final s = _summariesCache.firstWhere(
      (e) => e.id == picked,
      orElse: () => const PriceTopicSummary(
          id: '', title: '未命名主题', rowCount: 0, createdAt: null),
    );
    setState(() {
      _recordedTopicIds[i] = s.id;
      _topicTitles[i] = s.title.isEmpty ? '未命名主题' : s.title;
      _statuses[i] = ReceiptLineStatus.recorded;
    });
  }

  /// 缓存的摘要列表。PickerSheet 是同步构造，必须用缓存而不是 async。
  List<PriceTopicSummary> _summariesCache = const [];

  Future<void> _refreshSummariesCache() async {
    final list = await PriceCompareRepository.instance.listSummaries();
    if (!mounted) return;
    setState(() => _summariesCache = list);
  }

  void _onTapReject(int i) {
    if (_statuses[i] != ReceiptLineStatus.pending) return;
    setState(() => _statuses[i] = ReceiptLineStatus.rejected);
  }

  int get _recordedCount =>
      _statuses.where((s) => s == ReceiptLineStatus.recorded).length;
  int get _rejectedCount =>
      _statuses.where((s) => s == ReceiptLineStatus.rejected).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.data.result;
    final pendingItems = <int>[];
    final recordedItems = <int>[];
    final rejectedItems = <int>[];
    for (int i = 0; i < _statuses.length; i++) {
      switch (_statuses[i]) {
        case ReceiptLineStatus.pending:
          pendingItems.add(i);
          break;
        case ReceiptLineStatus.recorded:
          recordedItems.add(i);
          break;
        case ReceiptLineStatus.rejected:
          rejectedItems.add(i);
          break;
      }
    }
    final orderedIndices = [...pendingItems, ...recordedItems, ...rejectedItems];

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部元信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.receipt_long, size: 18,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${result.storeName} · ${result.purchasedAt.year}/${result.purchasedAt.month.toString().padLeft(2, "0")}/${result.purchasedAt.day.toString().padLeft(2, "0")}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          // 行列表：pending → recorded → rejected 顺序
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: orderedIndices
                  .map((i) => _buildLine(i, theme))
                  .toList(),
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          // 底部 footer：状态摘要 + 跳链
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '已记入 $_recordedCount/${_statuses.length}，拒绝 $_rejectedCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '推荐主题：${result.recommendedTopic}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      const SchemaText(
                        '[打开比价计算器](fr://lab/demo/price-compare)',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(int i, ThemeData theme) {
    final item = widget.data.result.items[i];
    final status = _statuses[i];
    final itemText =
        '${item.resource} ×${_fmt(item.quantity)}  ¥${item.unitPrice.toStringAsFixed(2)}';
    final note = item.note;

    switch (status) {
      case ReceiptLineStatus.pending:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(itemText, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // 主题芯片（点击改主题）。pending 行默认按 _topicTitles 显示，
                        // 后端 default_topic 已在 initState 装入。
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _changeTopic(i),
                          child: _topicChip(
                            theme,
                            label: _topicTitles[i],
                            isAi: true,
                          ),
                        ),
                        if (note.isNotEmpty)
                          _topicChip(theme, label: note, isAi: false),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _EmphasisIconButton(
                icon: Icons.check,
                tooltip: '按此主题记入',
                color: theme.colorScheme.primary,
                onPressed: () => _onTapRecord(i),
              ),
              const SizedBox(width: 6),
              _EmphasisIconButton(
                icon: Icons.close,
                tooltip: '拒绝',
                color: theme.colorScheme.error,
                onPressed: () => _onTapReject(i),
              ),
            ],
          ),
        );
      case ReceiptLineStatus.recorded:
        final topic = _topicTitles[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${item.resource} ×${_fmt(item.quantity)} · ¥${item.unitPrice.toStringAsFixed(2)} · 已记入「$topic」',
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 改主题入口（边框强调 IconButton）
                _EmphasisIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: '改主题',
                  color: theme.colorScheme.primary,
                  onPressed: () => _changeTopic(i),
                ),
              ],
            ),
          ),
        );
      case ReceiptLineStatus.rejected:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              itemText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                decoration: TextDecoration.lineThrough,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
    }
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  /// 行内小标签：[isAi]=true 是 LLM 推断的 default_topic（primary 色边框强调），
  /// false 是备注（中性灰）。
  Widget _topicChip(ThemeData theme,
      {required String label, required bool isAi}) {
    if (label.isEmpty) return const SizedBox.shrink();
    final color = isAi ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        isAi ? 'AI · $label' : label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// 边框强调式 IconButton —— 沿用 EmphasisButton 颜色 token。
class _EmphasisIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _EmphasisIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.65 : 0.5),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}