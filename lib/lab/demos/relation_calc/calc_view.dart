// 计算主界面 —— 关系词点按链条：起点 + 逐步叠加关系词，实时显示结果。
//
// 布局（zen 主题 + 边框强调）：
//   顶部：起点选择 + 关系链横排（我 → 爸爸 → 爸爸）
//   中央：ZenSection 大卡，当前结果大字（失败显示「无法计算」+ 失败步）
//   中部：关系词按钮盘（Wrap 自动平衡，zenButton 描边强调）
//   底部：撤销 / 清空

import 'package:flutter/material.dart';

import '../../../../widgets/theme/zen_theme.dart';
import 'const_relation_calc.dart';
import 'relation_calc_models.dart';
import 'relation_engine.dart';

class CalcView extends StatefulWidget {
  const CalcView({super.key, required this.data});

  final RelationGraphData data;

  @override
  State<CalcView> createState() => _CalcViewState();
}

class _CalcViewState extends State<CalcView> {
  late RelationEngine _engine;
  String? _startId;
  final List<String> _termIds = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant CalcView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _rebuild();
    }
  }

  void _rebuild() {
    _engine = RelationEngine(widget.data);
    if (_startId == null || _engine.entity(_startId!) == null) {
      _startId = _defaultStartId();
    }
  }

  /// 默认起点：预设「我」；没有则取第一个实体。
  String? _defaultStartId() {
    for (final e in widget.data.entities) {
      if (e.name == RelationCalcConsts.defaultStartEntityName) return e.id;
    }
    return widget.data.entities.isEmpty ? null : widget.data.entities.first.id;
  }

  void _appendTerm(String termId) {
    setState(() => _termIds.add(termId));
  }

  void _undo() {
    if (_termIds.isEmpty) return;
    setState(() => _termIds.removeLast());
  }

  void _clear() {
    setState(_termIds.clear);
  }

  Future<void> _pickStart() async {
    final entities = widget.data.entities;
    if (entities.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ZenColors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            Text(RelationCalcUiText.pickStart, style: ZenText.title),
            const SizedBox(height: 8),
            for (final e in entities)
              ListTile(
                title: Text(e.name),
                subtitle: e.note.isEmpty ? null : Text(e.note,
                    style: ZenText.label),
                trailing: e.id == _startId
                    ? const Icon(Icons.check, color: ZenColors.sage)
                    : null,
                onTap: () => Navigator.pop(ctx, e.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _startId = picked;
        _termIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = _engine.entity(_startId ?? '');
    final result = start == null
        ? const RelationCalcResult(steps: [], success: false, failedIndex: 0)
        : _engine.resolve(start.id, _termIds);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStartRow(start),
                  const SizedBox(height: 12),
                  _buildChainCard(result, start),
                  const SizedBox(height: 12),
                  _buildResultCard(result),
                  const SizedBox(height: 12),
                  _buildTermPad(),
                  const SizedBox(height: 12),
                  _buildActions(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 顶部：起点实体 chip + 切换。
  Widget _buildStartRow(RelationEntity? start) {
    return Row(
      children: [
        Text(RelationCalcUiText.startEntityLabel, style: ZenText.label),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickStart,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: zenCard(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(start?.name ?? '—', style: ZenText.button),
                    const SizedBox(width: 6),
                    const Icon(Icons.swap_vert,
                        size: 16, color: ZenColors.secondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 关系链展示：我 → 爸爸 → 爸爸（含失败步高亮）。
  Widget _buildChainCard(RelationCalcResult result, RelationEntity? start) {
    return ZenSection(
      title: RelationCalcUiText.chainLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chainChip(start?.name ?? '—',
                emphasized: true, failed: false),
            for (var i = 0; i < _termIds.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward,
                    size: 16, color: ZenColors.hair),
              ),
              _chainChip(
                _engine.term(_termIds[i])?.name ?? '?',
                emphasized: false,
                failed: result.failedIndex == i,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chainChip(String label,
      {required bool emphasized, required bool failed}) {
    final color = failed
        ? ZenColors.mutedRed
        : (emphasized ? ZenColors.sage : ZenColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? ZenColors.mutedRed.withValues(alpha: 0.08)
            : ZenColors.surface,
        border: Border.all(
          color: failed ? ZenColors.mutedRed : ZenColors.hair,
          width: emphasized ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: ZenText.button.copyWith(
              color: color, fontWeight: FontWeight.w600)),
    );
  }

  /// 中央结果大卡。
  Widget _buildResultCard(RelationCalcResult result) {
    final ok = result.success;
    final finalName = ok ? (result.finalEntity?.name ?? '—') : null;
    return ZenSection(
      title: RelationCalcUiText.resultLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: zenCard(color: ZenColors.surface),
        child: Column(
          children: [
            if (finalName != null)
              Text(
                finalName,
                style: ZenText.monoDigitLarge.copyWith(
                  color: ZenColors.ink,
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else ...[
              Text(RelationCalcUiText.notResolvable,
                  style: ZenText.title.copyWith(color: ZenColors.mutedRed)),
              const SizedBox(height: 6),
              Text(
                _termIds.isEmpty
                    ? RelationCalcUiText.emptyChainHint
                    : RelationCalcUiText.notResolvableHint,
                style: ZenText.label,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 关系词按钮盘（Wrap 自动平衡 + zenButton 描边强调）。
  Widget _buildTermPad() {
    final terms = widget.data.terms;
    if (terms.isEmpty) {
      return ZenSection(
        title: '关系词',
        child: Text('还没有关系词，去「管理」页添加', style: ZenText.label),
      );
    }
    return ZenSection(
      title: '关系词',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in terms)
            OutlinedButton(
              onPressed: () => _appendTerm(t.id),
              style: zenButton(
                foreground: ZenColors.ink,
                border: ZenColors.hair,
              ),
              child: Text(t.name),
            ),
        ],
      ),
    );
  }

  /// 底部操作：撤销 / 清空。
  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: RelationCalcUiText.undo,
          child: ZenIconButton(
            icon: Icons.undo,
            onTap: _termIds.isEmpty ? null : _undo,
            color: ZenColors.secondary,
            variant: ZenIconButtonVariant.outline,
          ),
        ),
        const SizedBox(width: 16),
        Tooltip(
          message: RelationCalcUiText.clear,
          child: ZenIconButton(
            icon: Icons.restart_alt,
            onTap: _termIds.isEmpty ? null : _clear,
            color: ZenColors.sage,
            variant: ZenIconButtonVariant.outline,
          ),
        ),
      ],
    );
  }
}
