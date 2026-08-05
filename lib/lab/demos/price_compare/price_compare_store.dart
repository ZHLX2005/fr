import 'package:hive_flutter/hive_flutter.dart';

import 'price_compare_models.dart';

/// 比价计算器存储层 —— 封装 `price_compare_topics` Hive box 的所有读写。
///
/// 之前 box 操作散落在 `price_compare_demo.dart` 与
/// `receipt_ocr_message_strategy.dart` 两处，难以复用且容易出错。
/// 这里集中为语义化方法，外部只看到 findOrCreateTopic / appendRow / listSummaries 等。
///
/// box 内容是 `Map<String, dynamic>`（避开 TypeAdapter part 文件的 CI 编译坑），
/// 与 `PriceTopic.toMap` / `PriceTopic.fromMap` / `PriceRow.toMap` /
/// `PriceRow.fromMap` 一一对应。
class PriceCompareStore {
  PriceCompareStore._();

  static final PriceCompareStore instance = PriceCompareStore._();

  /// 确保 box 已打开。多次调用安全。
  Future<Box<dynamic>> _openBox() async {
    if (!Hive.isBoxOpen(kPriceCompareBoxName)) {
      await Hive.initFlutter();
      await Hive.openBox(kPriceCompareBoxName);
    }
    return Hive.box(kPriceCompareBoxName);
  }

  /// 列出所有主题摘要（按 updatedAt 倒序），供 PickerSheet / 选择面板使用。
  /// 同时跳过孤儿/格式异常的 entry。
  Future<List<PriceTopicSummary>> listSummaries() async {
    final box = await _openBox();
    final out = <PriceTopicSummary>[];
    for (final k in box.keys) {
      if (k == kPriceCompareLastTopicIdKey) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      final id = v['id'];
      if (id is! String) continue;
      final createdAtMs = (v['createdAt'] as int?) ?? (v['updatedAt'] as int?);
      out.add(PriceTopicSummary(
        id: id,
        title: (v['title'] as String?) ?? '',
        rowCount: ((v['rows'] as List?) ?? const []).length,
        createdAt: createdAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      ));
    }
    out.sort((a, b) {
      final ua = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final ub = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return ub.compareTo(ua);
    });
    return out;
  }

  /// 读单个完整主题（含 title + rows）。不存在返回 null。
  /// 比 [listRows] 多返回 title 与 createdAt，是 demo 页面 `last_topic_id` 恢复用的入口。
  Future<PriceTopic?> getTopic(String topicId) async {
    final box = await _openBox();
    final v = box.get(topicId);
    if (v is! Map) return null;
    final id = v['id'];
    if (id is! String || id != topicId) return null;
    final rowsRaw = (v['rows'] as List?) ?? const [];
    final rows = rowsRaw.whereType<Map>().map(PriceRow.fromMap).toList();
    final createdAtMs = (v['createdAt'] as int?) ?? (v['updatedAt'] as int?);
    return PriceTopic(
      id: id,
      title: (v['title'] as String?) ?? '',
      rows: rows,
      createdAt: createdAtMs == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  /// 根据 id 取主题 rows（已反序列化为 [PriceRow]）。不存在返回空列表。
  Future<List<PriceRow>> listRows(String topicId) async {
    final box = await _openBox();
    final v = box.get(topicId);
    if (v is! Map) return [];
    final rowsRaw = v['rows'] as List? ?? const [];
    return rowsRaw
        .whereType<Map>()
        .map(PriceRow.fromMap)
        .toList();
  }

  /// 找同名主题；不存在则新建并返回 id。
  /// 用于"按后端 LLM 给的 default_topic 直接落库"——同名主题会复用同一 box entry。
  Future<String> findOrCreateTopic(String title) async {
    final box = await _openBox();
    for (final k in box.keys) {
      if (k == kPriceCompareLastTopicIdKey) continue;
      final v = box.get(k);
      if (v is Map && (v['title'] as String?) == title && v['id'] is String) {
        return v['id'] as String;
      }
    }
    final id = 't${DateTime.now().microsecondsSinceEpoch}_${title.hashCode}';
    await box.put(id, {
      'id': id,
      'title': title,
      'rows': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  /// 追加一行到指定主题。topic 不存在时自动创建（title 用 [fallbackTitle]，默认空）。
  Future<void> appendRow(
    String topicId, {
    required PriceRow row,
    String fallbackTitle = '',
  }) async {
    final box = await _openBox();
    final v = box.get(topicId);
    if (v is! Map) {
      // 主题不存在则用 fallbackTitle 建一个
      await box.put(topicId, {
        'id': topicId,
        'title': fallbackTitle,
        'rows': <Map<String, dynamic>>[],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    final cur = box.get(topicId) as Map;
    final rowsRaw = ((cur['rows'] as List?) ?? const []).toList();
    rowsRaw.add(row.toMap());
    await box.put(topicId, {
      ...cur,
      'rows': rowsRaw,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 新建一个空主题（PickerSheet 的"新建"按钮走这里）。返回主题 id。
  Future<String> createEmptyTopic({String title = ''}) async {
    final box = await _openBox();
    final id = 't${DateTime.now().microsecondsSinceEpoch}';
    await box.put(id, {
      'id': id,
      'title': title,
      'rows': <Map<String, dynamic>>[],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  /// 重命名主题标题（不改 id，rows 保留）。
  Future<void> renameTopic(String topicId, String newTitle) async {
    final box = await _openBox();
    final v = box.get(topicId);
    if (v is! Map) return;
    await box.put(topicId, {
      ...v,
      'title': newTitle,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 删除主题。如果删的就是当前打开的，则清掉 last_topic_id。
  Future<void> deleteTopic(String topicId) async {
    final box = await _openBox();
    await box.delete(topicId);
    if (box.get(kPriceCompareLastTopicIdKey) == topicId) {
      await box.delete(kPriceCompareLastTopicIdKey);
    }
  }

  /// 把整个主题替换为 [topic]（含 rows、title）。[PriceCompareDemo] 持久化行变更用。
  Future<void> putTopic(PriceTopic topic) async {
    final box = await _openBox();
    await box.put(topic.id, topic.toMap());
  }

  /// 设置"上次打开的主题"，用于重启恢复。
  Future<void> setLastTopicId(String topicId) async {
    final box = await _openBox();
    await box.put(kPriceCompareLastTopicIdKey, topicId);
  }

  /// 读取"上次打开的主题" id；不存在返回 null。
  Future<String?> getLastTopicId() async {
    final box = await _openBox();
    return box.get(kPriceCompareLastTopicIdKey) as String?;
  }

  /// 给 BoxDescriptor.openUntyped 用的回调，避免 demo 直接 import hive。
  static Future<Box<dynamic>> openBoxForDescriptor() async {
    if (!Hive.isBoxOpen(kPriceCompareBoxName)) {
      await Hive.initFlutter();
      await Hive.openBox(kPriceCompareBoxName);
    }
    return Hive.box<dynamic>(kPriceCompareBoxName);
  }
}