// 通用关系计算器 —— 数据模型（变量系统模型：A 的 B = C）
//
// 手写 toMap/fromMap（JSON 序列化），避开 Hive TypeAdapter part 文件的
// CI 编译坑（详见 skill: Flutter-Hive-TypeAdapter-part文件CI构建失败问题）。
// 存储用 SharedPreferences 简单存储（见 relation_calc_store.dart）。

/// 实体（图的节点）：如「我」「爸爸」「爷爷」「组长」「经理」。
///
/// 领域无关 —— 亲戚、公司团队等级、宠物、组织…任何「X 的 Y = Z」的 X/Z。
class RelationEntity {
  RelationEntity({
    required this.id,
    required this.name,
    this.note = '',
  });

  /// 稳定 id（预设 'e_xxx'；用户新建 'e_' + 微秒时间戳）。
  final String id;

  /// 显示名（可改）。
  String name;

  /// 可选描述（如「父亲的父亲」）。
  String note;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'note': note};

  static RelationEntity fromMap(Map m) => RelationEntity(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        note: (m['note'] ?? '') as String,
      );
}

/// 关系词（有向边的标签）：如「爸爸」「妈妈」「哥哥」「上级」。
class RelationTerm {
  RelationTerm({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  static RelationTerm fromMap(Map m) => RelationTerm(
        id: (m['id'] ?? '') as String,
        name: (m['name'] ?? '') as String,
      );
}

/// 规则（有向边）：EntityA 的 Term = EntityB。
///
/// 语义：`fromId` 实体的 `termId` 关系词 → `toId` 实体。
class RelationRule {
  RelationRule({
    required this.id,
    required this.fromId,
    required this.termId,
    required this.toId,
  });

  final String id;
  String fromId;
  String termId;
  String toId;

  Map<String, dynamic> toMap() =>
      {'id': id, 'from': fromId, 'term': termId, 'to': toId};

  static RelationRule fromMap(Map m) => RelationRule(
        id: (m['id'] ?? '') as String,
        fromId: (m['from'] ?? '') as String,
        termId: (m['term'] ?? '') as String,
        toId: (m['to'] ?? '') as String,
      );
}

/// 整库快照：entities + terms + rules。
///
/// SharedPreferences 一次 JSON 读写（数据量小：几十个实体/关系词/规则）。
class RelationGraphData {
  const RelationGraphData({
    this.entities = const [],
    this.terms = const [],
    this.rules = const [],
  });

  final List<RelationEntity> entities;
  final List<RelationTerm> terms;
  final List<RelationRule> rules;

  Map<String, dynamic> toMap() => {
        'entities': entities.map((e) => e.toMap()).toList(),
        'terms': terms.map((e) => e.toMap()).toList(),
        'rules': rules.map((e) => e.toMap()).toList(),
      };

  static RelationGraphData fromMap(Map m) => RelationGraphData(
        entities: (m['entities'] as List? ?? [])
            .whereType<Map>()
            .map(RelationEntity.fromMap)
            .toList(),
        terms: (m['terms'] as List? ?? [])
            .whereType<Map>()
            .map(RelationTerm.fromMap)
            .toList(),
        rules: (m['rules'] as List? ?? [])
            .whereType<Map>()
            .map(RelationRule.fromMap)
            .toList(),
      );
}
