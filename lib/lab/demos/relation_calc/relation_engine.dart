// 通用关系计算引擎 —— 不感知领域，任何「X 的 Y = Z」都能算。
//
// 变量系统模型：A 的 B = C，C 的 D = E … 无限嵌套、链式传递。
// 引擎只依赖 [RelationGraphData]（纯数据），不碰存储，便于单测。

import 'relation_calc_models.dart';

/// 单步结果：from 的 term = to。
class RelationStep {
  const RelationStep({
    required this.from,
    required this.term,
    required this.to,
  });

  final RelationEntity from;
  final RelationTerm term;
  final RelationEntity to;
}

/// 链式计算结果。
///
/// [success] 为 true 时 [steps] 完整走完，[finalEntity] 即最终结果；
/// 为 false 时 [failedIndex] 指向失败的关系词下标（0-based，相对
/// 传入的 termIds），[steps] 只含成功的前缀（可用于展示「走到哪一步断了」）。
class RelationCalcResult {
  const RelationCalcResult({
    required this.steps,
    required this.success,
    this.failedIndex,
    this.startEntity,
  });

  final List<RelationStep> steps;
  final bool success;
  final int? failedIndex;

  /// 起点实体（起点不存在时为 null）。
  final RelationEntity? startEntity;

  /// 最终实体：空链时即起点；success 时必非空。
  RelationEntity? get finalEntity =>
      steps.isEmpty ? startEntity : steps.last.to;
}

/// 通用关系计算引擎。
///
/// 从 [graph] 构建索引；[step] 做单步边查找；[resolve] 做链式计算。
/// 线程/领域无关：亲戚、公司团队等级、宠物…共用同一引擎。
class RelationEngine {
  RelationEngine(this.graph);

  final RelationGraphData graph;

  Map<String, RelationEntity>? _entityById;
  Map<String, RelationTerm>? _termById;

  Map<String, RelationEntity> get entityById =>
      _entityById ??= {for (final e in graph.entities) e.id: e};

  Map<String, RelationTerm> get termById =>
      _termById ??= {for (final t in graph.terms) t.id: t};

  RelationEntity? entity(String id) => entityById[id];
  RelationTerm? term(String id) => termById[id];

  /// 单步：fromId 的 termId → 目标实体；无规则返回 null。
  RelationEntity? step(String fromId, String termId) {
    for (final r in graph.rules) {
      if (r.fromId == fromId && r.termId == termId) {
        return entityById[r.toId];
      }
    }
    return null;
  }

  /// 链式计算：从 [startId] 出发，依次应用 [termIds]。
  ///
  /// 任一步无匹配规则即失败（[RelationCalcResult.failedIndex] 指向该步）。
  RelationCalcResult resolve(String startId, List<String> termIds) {
    final steps = <RelationStep>[];
    final start = entityById[startId];
    if (start == null) {
      return RelationCalcResult(steps: steps, success: false, failedIndex: 0);
    }
    var current = start;
    for (var i = 0; i < termIds.length; i++) {
      final t = termById[termIds[i]];
      if (t == null) {
        return RelationCalcResult(
          steps: steps,
          success: false,
          failedIndex: i,
          startEntity: start,
        );
      }
      final to = step(current.id, t.id);
      if (to == null) {
        return RelationCalcResult(
          steps: steps,
          success: false,
          failedIndex: i,
          startEntity: start,
        );
      }
      steps.add(RelationStep(from: current, term: t, to: to));
      current = to;
    }
    return RelationCalcResult(
      steps: steps,
      success: true,
      startEntity: start,
    );
  }
}
