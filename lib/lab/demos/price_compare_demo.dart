import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../lab_container.dart';
import 'price_compare/price_compare_models.dart';
import 'price_compare/price_compare_row.dart';
import 'price_compare/price_topic_picker_sheet.dart';

// ============================================================================
// Demo 注册
// ============================================================================
class PriceCompareDemo extends DemoPage {
  @override
  String get title => '比价计算器';

  @override
  String get slug => 'price-compare';

  @override
  String get description => '资源+金额快速算单价，多主题持久化';

  @override
  Widget buildPage(BuildContext context) => const _PriceComparePage();
}

void registerPriceCompareDemo() {
  DemoRegistry().register(PriceCompareDemo());
}

// ============================================================================
// 页面
// ============================================================================
class _PriceComparePage extends StatefulWidget {
  const _PriceComparePage();

  @override
  State<_PriceComparePage> createState() => _PriceComparePageState();
}

class _PriceComparePageState extends State<_PriceComparePage> {
  Box? _box;
  bool _loading = true;
  PriceTopic? _topic;
  final TextEditingController _titleCtrl = TextEditingController();
  // 每行两个 controller；index 与 _topic.rows 对齐
  final List<TextEditingController> _resCtrls = [];
  final List<TextEditingController> _amtCtrls = [];
  Timer? _saveDebouncer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Hive.isBoxOpen(kPriceCompareBoxName)) {
      await Hive.initFlutter();
      await Hive.openBox(kPriceCompareBoxName);
    }
    _box = Hive.box(kPriceCompareBoxName);
    // 恢复上次主题；没有就新建
    final lastId = _box!.get(kPriceCompareLastTopicIdKey) as String?;
    PriceTopic? loaded;
    if (lastId != null) {
      final raw = _box!.get(lastId);
      if (raw is Map) loaded = PriceTopic.fromMap(raw);
    }
    loaded ??= _createNewTopic(persist: true);
    _bindTopic(loaded);
    if (mounted) setState(() => _loading = false);
  }

  PriceTopic _createNewTopic({bool persist = false}) {
    final id = 't${DateTime.now().microsecondsSinceEpoch}';
    final t = PriceTopic(id: id);
    if (persist && _box != null) {
      _box!.put(id, t.toMap());
      _box!.put(kPriceCompareLastTopicIdKey, id);
    }
    return t;
  }

  void _bindTopic(PriceTopic t) {
    _topic = t;
    _titleCtrl.text = t.title;
    for (final c in _resCtrls) {
      c.dispose();
    }
    for (final c in _amtCtrls) {
      c.dispose();
    }
    _resCtrls
      ..clear()
      ..addAll(t.rows.map((r) => TextEditingController(text: r.resource)));
    _amtCtrls
      ..clear()
      ..addAll(t.rows.map((r) => TextEditingController(text: r.amount)));
  }

  void _persistDebounced() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 300), _persistNow);
  }

  Future<void> _persistNow() async {
    final t = _topic;
    final box = _box;
    if (t == null || box == null) return;
    await box.put(t.id, t.toMap());
    await box.put(kPriceCompareLastTopicIdKey, t.id);
  }

  @override
  void dispose() {
    _saveDebouncer?.cancel();
    _persistNow();
    _titleCtrl.dispose();
    for (final c in _resCtrls) {
      c.dispose();
    }
    for (final c in _amtCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- 用户操作 ----------------------------------------------------------
  void _onTitleChanged(String v) {
    _topic?.title = v;
    _persistDebounced();
  }

  void _onRowChanged(int i, {String? res, String? amt}) {
    final row = _topic?.rows[i];
    if (row == null) return;
    if (res != null) row.resource = res;
    if (amt != null) row.amount = amt;
    setState(() {}); // 触发单价重算 / 高亮刷新
    _persistDebounced();
  }

  void _addRow() {
    _topic?.rows.add(PriceRow());
    _resCtrls.add(TextEditingController());
    _amtCtrls.add(TextEditingController());
    setState(() {});
    _persistDebounced();
  }

  void _removeRow(int i) {
    if (_topic == null) return;
    if (_topic!.rows.length <= 1) {
      // 至少保留一行；改成清空
      _topic!.rows[i] = PriceRow();
      _resCtrls[i].clear();
      _amtCtrls[i].clear();
    } else {
      _topic!.rows.removeAt(i);
      _resCtrls.removeAt(i).dispose();
      _amtCtrls.removeAt(i).dispose();
    }
    setState(() {});
    _persistDebounced();
  }

  Future<void> _switchTopic() async {
    await _persistNow();
    final entries = _allTopicEntries();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => PriceTopicPickerSheet(
        entries: entries,
        currentId: _topic?.id,
        onNew: () => Navigator.pop(ctx, '__new__'),
        onDelete: (id) async {
          await _box?.delete(id);
          if (!ctx.mounted) return;
          Navigator.pop(ctx, '__deleted__:$id');
        },
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == '__new__') {
      final t = _createNewTopic(persist: true);
      setState(() => _bindTopic(t));
      return;
    }
    if (selected.startsWith('__deleted__:')) {
      final deletedId = selected.substring('__deleted__:'.length);
      if (deletedId == _topic?.id) {
        // 当前被删；选下一个或新建
        final remaining = _allTopicEntries();
        final t = remaining.isNotEmpty
            ? PriceTopic.fromMap(remaining.first.value)
            : _createNewTopic(persist: true);
        setState(() => _bindTopic(t));
        await _persistNow();
      } else {
        setState(() {}); // 刷新可能显示的列表
      }
      return;
    }
    final raw = _box?.get(selected);
    if (raw is Map) {
      setState(() => _bindTopic(PriceTopic.fromMap(raw)));
      await _persistNow();
    }
  }

  List<MapEntry<String, Map>> _allTopicEntries() {
    final box = _box;
    if (box == null) return const [];
    final entries = <MapEntry<String, Map>>[];
    for (final k in box.keys) {
      if (k == kPriceCompareLastTopicIdKey) continue;
      final v = box.get(k);
      if (v is Map && v['id'] is String) {
        entries.add(MapEntry(k as String, v));
      }
    }
    entries.sort((a, b) {
      final ua = (a.value['updatedAt'] as int?) ?? 0;
      final ub = (b.value['updatedAt'] as int?) ?? 0;
      return ub.compareTo(ua);
    });
    return entries;
  }

  // ---- 构建 --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    // 最低单价索引（用于高亮）
    final prices = _topic!.rows.map((r) => r.unitPrice).toList();
    final validPrices = prices.whereType<double>().toList();
    final minPrice = validPrices.isEmpty
        ? null
        : validPrices.reduce((a, b) => a < b ? a : b);

    return Column(
      children: [
        _buildHeader(scheme),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            itemCount: _topic!.rows.length,
            itemBuilder: (ctx, i) => PriceCompareRow(
              index: i,
              unitPrice: prices[i],
              minPrice: minPrice,
              resourceController: _resCtrls[i],
              amountController: _amtCtrls[i],
              onResourceChanged: (v) => _onRowChanged(i, res: v),
              onAmountChanged: (v) => _onRowChanged(i, amt: v),
              onRemove: () => _removeRow(i),
            ),
          ),
        ),
        _buildFooter(scheme),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final primary = scheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(color: primary.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_rounded, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              onChanged: _onTitleChanged,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: '主题（例如：卫生纸比价）',
                hintStyle: TextStyle(
                  color: primary.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '切换/管理主题',
            icon: Icon(Icons.swap_horiz_rounded, color: primary),
            onPressed: _switchTopic,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    final primary = scheme.primary;
    // 总览：有效行数、最低单价
    final valid = _topic!.rows.where((r) => r.unitPrice != null).toList();
    String hint;
    if (valid.isEmpty) {
      hint = '输入至少一行「资源/金额」';
    } else {
      final min =
          valid.map((r) => r.unitPrice!).reduce((a, b) => a < b ? a : b);
      hint = '共 ${valid.length} 行有效 · 最低单价 ¥${formatUnitPrice(min)}';
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: primary.withValues(alpha: 0.12)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
            // border-emphasis 风格的 + 按钮
            Container(
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.4)),
              ),
              child: TextButton.icon(
                onPressed: _addRow,
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('新增一行'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
