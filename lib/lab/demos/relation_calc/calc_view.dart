// 计算主界面 —— 关系词点按链条：起点 + 逐步叠加关系词，实时显示结果。
//
// 布局（zen 主题 + 边框强调）：
//   顶部：起点选择 + 关系链横排（我 → 爸爸 → 爸爸）
//   中央：ZenSection 大卡，当前结果大字（失败显示「无法计算」+ 失败步）
//   中部：关系词按钮盘（Wrap 自动平衡，zenButton 描边强调）
//   底部：撤销 / 清空

import 'package:flutter/material.dart';
import '../../../core/theme/context/colors.dart';

import '../../../core/ui/global/button/main.dart';
import '../../../core/ui/global/zen/main.dart';
import 'const_relation_calc.dart';
import 'kinship_solver.dart';
import 'kinship_table.g.dart';
import 'relation_calc_models.dart';
import 'relation_engine.dart';
import '../../../core/ui/global/section/main.dart';

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
      backgroundColor: context.colors.surface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.all(12),
          children: [
            Text(RelationCalcUiText.pickStart, style: ZenText.title),
            SizedBox(height: 8),
            for (final e in entities)
              ListTile(
                title: Text(e.name),
                subtitle: e.note.isEmpty
                    ? null
                    : Text(e.note, style: ZenText.label),
                trailing: e.id == _startId
                    ? Icon(Icons.check, color: context.colors.accent)
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
    // 规则库没配到 → **结构推导**兜底（fr #14）。
    //
    // 关系库是用户可编辑的称谓表，十词三层共 1000 条组合它覆盖不完；以前没配到
    // 就一句「无法计算」，等于把「我没配」说成「这关系不存在」。现在这类链交给
    // `solveKinship` 按辈分与性别推：推得出来给称谓或描述式，推不出来才说
    // 无此关系（并说清是性别矛盾还是真的没有）。
    //
    // 只对起点「我」生效：三层组合都是以我为原点数的；换起点（爷爷/组长）
    // 走关系库那套领域无关的引擎。
    final derived = (!result.success &&
            _termIds.isNotEmpty &&
            start?.name == RelationCalcConsts.defaultStartEntityName)
        ? _derive()
        : null;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStartRow(start),
                  SizedBox(height: 12),
                  _buildChainCard(result, start, derived),
                  SizedBox(height: 12),
                  _buildResultCard(result, derived),
                  SizedBox(height: 12),
                  _buildTermPad(),
                  SizedBox(height: 12),
                  _buildActions(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 三层组合优先查**审阅过的表**（`kinship_table.g.dart`，1000 条，
  /// 生成后人工填充/减枝过），表里没有才现场按结构推。
  ///
  /// 为什么不一上来就推：表里那 188 条剔除项写着「为什么不可能」，
  /// 现场推虽然也能判性别矛盾，但表是**人看过一遍**的，说法更稳。
  KinAnswer? _derive() {
    final labels = <String>[];
    for (final id in _termIds) {
      final name = _engine.term(id)?.name;
      if (name == null) return solveKinship(_termIds);
      labels.add(name);
    }
    final key = labels.join(',');
    final pruned = kKinshipThreeLayerPruned[key];
    if (pruned != null) {
      return KinAnswer(label: '', standard: false, reason: pruned);
    }
    final hit = kKinshipThreeLayer[key];
    if (hit != null) {
      return KinAnswer(label: hit, standard: !hit.contains('的'));
    }
    return solveKinship(_termIds);
  }

  /// 顶部：起点实体 chip + 切换。
  Widget _buildStartRow(RelationEntity? start) {
    return Row(
      children: [
        Text(RelationCalcUiText.startEntityLabel, style: ZenText.label),
        SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickStart,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: zenCardTheme(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(start?.name ?? '—', style: ZenText.button),
                    SizedBox(width: 6),
                    Icon(
                      Icons.swap_vert,
                      size: 16,
                      color: context.colors.textMuted,
                    ),
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
  Widget _buildChainCard(
    RelationCalcResult result,
    RelationEntity? start,
    KinAnswer? derived,
  ) {
    return BaseSection(
      title: RelationCalcUiText.chainLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chainChip(start?.name ?? '—', emphasized: true, failed: false),
            for (var i = 0; i < _termIds.length; i++) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: context.colors.outline,
                ),
              ),
              _chainChip(
                _engine.term(_termIds[i])?.name ?? '?',
                emphasized: false,
                // 推导兜得住就不标红：这一步不是「断了」，只是规则库没配
                failed: derived == null && result.failedIndex == i,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chainChip(
    String label, {
    required bool emphasized,
    required bool failed,
  }) {
    final color = failed
        ? context.colors.danger
        : (emphasized ? context.colors.accent : context.colors.text);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? context.colors.danger.withValues(alpha: 0.08)
            : context.colors.surface,
        border: Border.all(
          color: failed ? context.colors.danger : context.colors.outline,
          width: emphasized ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: ZenText.button.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 中央结果大卡。
  Widget _buildResultCard(RelationCalcResult result, KinAnswer? derived) {
    // 三段取值：规则库命中 > 结构推导 > 都无法计算
    final fromGraph = result.success;
    final label = fromGraph
        ? (result.finalEntity?.name ?? '—')
        : (derived != null && !derived.impossible ? derived.label : null);
    final impossible = !fromGraph && (derived?.impossible ?? false);
    final hint = fromGraph || label == null
        ? null
        : (derived!.standard
            ? RelationCalcUiText.derivedHint
            : RelationCalcUiText.descriptiveHint);
    return BaseSection(
      title: RelationCalcUiText.resultLabel,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: zenCardTheme(context),
        child: Column(
          children: [
            if (label != null) ...[
              Text(
                label,
                style: ZenText.monoDigitLarge.copyWith(
                  color: context.colors.text,
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hint != null) ...[
                SizedBox(height: 8),
                Text(hint, style: ZenText.label, textAlign: TextAlign.center),
              ],
            ] else ...[
              Text(
                impossible
                    ? RelationCalcUiText.noSuchRelation
                    : RelationCalcUiText.notResolvable,
                style: ZenText.title.copyWith(color: context.colors.danger),
              ),
              SizedBox(height: 6),
              Text(
                _termIds.isEmpty
                    ? RelationCalcUiText.emptyChainHint
                    : (impossible
                        ? derived!.reason!
                        : RelationCalcUiText.notResolvableHint),
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
      return BaseSection(
        title: '关系词',
        child: Text('还没有关系词，去「管理」页添加', style: ZenText.label),
      );
    }
    return BaseSection(
      title: '关系词',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in terms)
            OutlinedButton(
              onPressed: () => _appendTerm(t.id),
              style: zenButtonTheme(
                context,
                foreground: context.colors.text,
                border: context.colors.outline,
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
          child: BaseIconButton(
            icon: Icons.undo,
            onTap: _termIds.isEmpty ? null : _undo,
            color: context.colors.textMuted,
            variant: BaseIconButtonVariant.outline,
          ),
        ),
        SizedBox(width: 16),
        Tooltip(
          message: RelationCalcUiText.clear,
          child: BaseIconButton(
            icon: Icons.restart_alt,
            onTap: _termIds.isEmpty ? null : _clear,
            color: context.colors.accent,
            variant: BaseIconButtonVariant.outline,
          ),
        ),
      ],
    );
  }
}
