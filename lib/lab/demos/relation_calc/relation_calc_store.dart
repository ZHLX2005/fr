// 关系库持久化 —— SharedPreferences 简单存储（用户拍板：不用 Hive）。
//
// 整库快照 JSON 一次读写（数据量小：几十个实体/关系词/规则），
// 参照 team_card 预设 / web_bookmark 的 SharedPreferences 先例。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'relation_calc_models.dart';

/// 关系库存储。
///
/// load-modify-save 模式：读整库 → 增删改 → save 整库。
/// 删除实体/关系词时联动清理引用它的规则，避免悬空边。
class RelationCalcStore {
  RelationCalcStore._();

  static final RelationCalcStore instance = RelationCalcStore._();

  static const String kStoreKey = 'relation_calc.graph.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 读整库；无数据/损坏返回空快照。
  Future<RelationGraphData> load() async {
    final p = await _prefs;
    final raw = p.getString(kStoreKey);
    if (raw == null || raw.isEmpty) return const RelationGraphData();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const RelationGraphData();
      return RelationGraphData.fromMap(decoded);
    } catch (_) {
      // 数据损坏：返回空（调用方可选择重新导入预设）。
      return const RelationGraphData();
    }
  }

  /// 写整库。
  Future<void> save(RelationGraphData data) async {
    final p = await _prefs;
    await p.setString(kStoreKey, jsonEncode(data.toMap()));
  }

  /// 清空（重置回预设前调用）。
  Future<void> clear() async {
    final p = await _prefs;
    await p.remove(kStoreKey);
  }

  // ---------------------------------------------------------------------
  // CRUD 语义方法（load-modify-save）
  // ---------------------------------------------------------------------

  static String _newId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  /// 新增/覆盖实体（同 id 覆盖）。返回写入后的快照。
  Future<RelationGraphData> upsertEntity(RelationEntity entity) async {
    final data = await load();
    final entities = [...data.entities];
    final idx = entities.indexWhere((e) => e.id == entity.id);
    if (idx >= 0) {
      entities[idx] = entity;
    } else {
      entities.add(entity);
    }
    final next = RelationGraphData(
      entities: entities,
      terms: data.terms,
      rules: data.rules,
    );
    await save(next);
    return next;
  }

  /// 删除实体，并清理引用它的规则（from/to 都删）。
  Future<RelationGraphData> deleteEntity(String id) async {
    final data = await load();
    final next = RelationGraphData(
      entities: data.entities.where((e) => e.id != id).toList(),
      terms: data.terms,
      rules: data.rules
          .where((r) => r.fromId != id && r.toId != id)
          .toList(),
    );
    await save(next);
    return next;
  }

  /// 新增/覆盖关系词。返回写入后的快照。
  Future<RelationGraphData> upsertTerm(RelationTerm term) async {
    final data = await load();
    final terms = [...data.terms];
    final idx = terms.indexWhere((t) => t.id == term.id);
    if (idx >= 0) {
      terms[idx] = term;
    } else {
      terms.add(term);
    }
    final next = RelationGraphData(
      entities: data.entities,
      terms: terms,
      rules: data.rules,
    );
    await save(next);
    return next;
  }

  /// 删除关系词，并清理引用它的规则。
  Future<RelationGraphData> deleteTerm(String id) async {
    final data = await load();
    final next = RelationGraphData(
      entities: data.entities,
      terms: data.terms.where((t) => t.id != id).toList(),
      rules: data.rules.where((r) => r.termId != id).toList(),
    );
    await save(next);
    return next;
  }

  /// 新增/覆盖规则。返回写入后的快照。
  Future<RelationGraphData> upsertRule(RelationRule rule) async {
    final data = await load();
    final rules = [...data.rules];
    final idx = rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      rules[idx] = rule;
    } else {
      rules.add(rule);
    }
    final next = RelationGraphData(
      entities: data.entities,
      terms: data.terms,
      rules: rules,
    );
    await save(next);
    return next;
  }

  /// 删除规则。
  Future<RelationGraphData> deleteRule(String id) async {
    final data = await load();
    final next = RelationGraphData(
      entities: data.entities,
      terms: data.terms,
      rules: data.rules.where((r) => r.id != id).toList(),
    );
    await save(next);
    return next;
  }

  /// 生成新 id（实体/关系词/规则通用）。
  static String newId(String prefix) => _newId(prefix);
}
