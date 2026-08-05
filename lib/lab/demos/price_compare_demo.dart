import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/storage/box_descriptor.dart';
import '../../core/storage/storage_registry.dart';
import '../lab_container.dart';
import 'price_compare/price_compare_chrome.dart';
import 'price_compare/price_compare_models.dart';
import 'price_compare/price_compare_row.dart';
import 'price_compare/price_compare_store.dart';
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
  bool _loading = true;
  PriceTopic? _topic;
  final TextEditingController _titleCtrl = TextEditingController();
  // 每行三个 controller；index 与 _topic.rows 对齐
  final List<TextEditingController> _resCtrls = [];
  final List<TextEditingController> _amtCtrls = [];
  final List<TextEditingController> _noteCtrls = [];
  Timer? _saveDebouncer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _registerToStorageRegistry();
    // 恢复上次主题；没有就新建
    final lastId = await PriceCompareStore.instance.getLastTopicId();
    PriceTopic? loaded;
    if (lastId != null) {
      loaded = await PriceCompareStore.instance.getTopic(lastId);
    }
    loaded ??= await _createNewTopic(persist: true);
    _bindTopic(loaded);
    if (mounted) setState(() => _loading = false);
  }

  /// 把 box 注册到 StorageRegistry，存储分析面板自动接管展示/清空。
  /// 幂等：已注册则跳过。Hive 操作委托给 PriceCompareStore，避免 demo 直接 import hive。
  void _registerToStorageRegistry() {
    if (StorageRegistry.has(kPriceCompareBoxName)) return;
    StorageRegistry.register(BoxDescriptor(
      name: kPriceCompareBoxName,
      displayName: '比价主题',
      openUntyped: PriceCompareStore.openBoxForDescriptor,
      formatValue: (v) {
        if (v is Map) {
          final title = v['title'];
          final rows = v['rows'];
          final rowCount = rows is List ? rows.length : 0;
          final t = (title is String && title.isNotEmpty) ? title : '（未命名）';
          return '$t · $rowCount 行';
        }
        return v.toString();
      },
    ));
  }

  Future<PriceTopic> _createNewTopic({bool persist = false}) async {
    final id = persist
        ? await PriceCompareStore.instance.createEmptyTopic()
        : 't${DateTime.now().microsecondsSinceEpoch}';
    final t = PriceTopic(id: id);
    if (persist) {
      await PriceCompareStore.instance.setLastTopicId(id);
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
    for (final c in _noteCtrls) {
      c.dispose();
    }
    _resCtrls
      ..clear()
      ..addAll(t.rows.map((r) => TextEditingController(text: r.resource)));
    _amtCtrls
      ..clear()
      ..addAll(t.rows.map((r) => TextEditingController(text: r.amount)));
    _noteCtrls
      ..clear()
      ..addAll(t.rows.map((r) => TextEditingController(text: r.note)));
  }

  void _persistDebounced() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 300), _persistNow);
  }

  Future<void> _persistNow() async {
    final t = _topic;
    if (t == null) return;
    await PriceCompareStore.instance.putTopic(t);
    await PriceCompareStore.instance.setLastTopicId(t.id);
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
    for (final c in _noteCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- 用户操作 ----------------------------------------------------------
  void _onTitleChanged(String v) {
    _topic?.title = v;
    _persistDebounced();
  }

  void _onRowChanged(int i, {String? res, String? amt, String? note}) {
    final row = _topic?.rows[i];
    if (row == null) return;
    if (res != null) row.resource = res;
    if (amt != null) row.amount = amt;
    if (note != null) row.note = note;
    // 备注不影响单价高亮，可少一次 setState；但改动少不追求极致，统一 setState
    setState(() {});
    _persistDebounced();
  }

  void _addRow() {
    _topic?.rows.add(PriceRow());
    _resCtrls.add(TextEditingController());
    _amtCtrls.add(TextEditingController());
    _noteCtrls.add(TextEditingController());
    setState(() {});
    _persistDebounced();
  }

  void _removeRow(int i) {
    if (_topic == null) return;
    if (_topic!.rows.length <= 1) {
      // 至少保留一行；改成清空（同时重置时间为现在——等价于新起一行）
      _topic!.rows[i] = PriceRow();
      _resCtrls[i].clear();
      _amtCtrls[i].clear();
      _noteCtrls[i].clear();
    } else {
      _topic!.rows.removeAt(i);
      _resCtrls.removeAt(i).dispose();
      _amtCtrls.removeAt(i).dispose();
      _noteCtrls.removeAt(i).dispose();
    }
    setState(() {});
    _persistDebounced();
  }

  Future<void> _switchTopic() async {
    await _persistNow();
    final summaries = await PriceCompareStore.instance.listSummaries();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => PriceTopicPickerSheet(
        summaries: summaries,
        currentId: _topic?.id,
        onNew: () => Navigator.pop(ctx, '__new__'),
        onDelete: (id) async {
          await PriceCompareStore.instance.deleteTopic(id);
          if (!ctx.mounted) return;
          Navigator.pop(ctx, '__deleted__:$id');
        },
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == '__new__') {
      final t = await _createNewTopic(persist: true);
      setState(() => _bindTopic(t));
      return;
    }
    if (selected.startsWith('__deleted__:')) {
      final deletedId = selected.substring('__deleted__:'.length);
      if (deletedId == _topic?.id) {
        // 当前被删；选下一个或新建
        final remaining = await PriceCompareStore.instance.listSummaries();
        final t = remaining.isNotEmpty
            ? await PriceCompareStore.instance.getTopic(remaining.first.id)
                ?? await _createNewTopic(persist: true)
            : await _createNewTopic(persist: true);
        setState(() => _bindTopic(t));
        await _persistNow();
      } else {
        setState(() {}); // 刷新可能显示的列表
      }
      return;
    }
    final loaded = await PriceCompareStore.instance.getTopic(selected);
    if (loaded != null) {
      setState(() => _bindTopic(loaded));
      await _persistNow();
    }
  }

  // ---- 构建 --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // 最低单价索引（用于高亮）
    final prices = _topic!.rows.map((r) => r.unitPrice).toList();
    final validPrices = prices.whereType<double>().toList();
    final minPrice = validPrices.isEmpty
        ? null
        : validPrices.reduce((a, b) => a < b ? a : b);

    return Column(
      children: [
        PriceCompareHeader(
          titleController: _titleCtrl,
          createdAt: _topic!.createdAt,
          onTitleChanged: _onTitleChanged,
          onSwitchTopic: _switchTopic,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
            itemCount: _topic!.rows.length,
            itemBuilder: (ctx, i) => PriceCompareRow(
              index: i,
              unitPrice: prices[i],
              minPrice: minPrice,
              createdAt: _topic!.rows[i].createdAt,
              resourceController: _resCtrls[i],
              amountController: _amtCtrls[i],
              noteController: _noteCtrls[i],
              onResourceChanged: (v) => _onRowChanged(i, res: v),
              onAmountChanged: (v) => _onRowChanged(i, amt: v),
              onNoteChanged: (v) => _onRowChanged(i, note: v),
              onRemove: () => _removeRow(i),
            ),
          ),
        ),
        PriceCompareFooter(
          validCount: validPrices.length,
          minPrice: minPrice,
          onAddRow: _addRow,
        ),
      ],
    );
  }
}
