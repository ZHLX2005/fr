import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_gallery_models.dart';

/// AI 分析结果持久化（SharedPreferences JSON map：assetId → result）。
///
/// Lab demo 级别不引入 Hive Box（D 序列标准面向正式模块）；结果可重建
/// （重新扫描覆盖），SharedPreferences 足够。
class AiGalleryResultStore {
  static const _key = 'ai_gallery_results_v1';

  Future<Map<String, AiScanResult>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: AiScanResult.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  /// 整体覆写（扫描批次完成时调用；单张更新走 [upsert]）。
  Future<void> saveAll(Map<String, AiScanResult> results) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode({
        for (final e in results.entries) e.key: e.value.toJson(),
      }),
    );
  }

  Future<void> upsert(AiScanResult result) async {
    final all = await loadAll();
    all[result.assetId] = result;
    await saveAll(all);
  }

  /// 批量移除分析记录（多选删除用；对应图片是否删除由调用方决定）。
  ///
  /// 返回真正被移除的 id —— 传进来的可能是已经不在库里的 id。
  Future<Set<String>> removeAll(Iterable<String> assetIds) async {
    final all = await loadAll();
    final removed = <String>{};
    for (final id in assetIds) {
      if (all.remove(id) != null) removed.add(id);
    }
    if (removed.isNotEmpty) await saveAll(all);
    return removed;
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
