import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_ocr_history.dart';

/// 小票 OCR 历史记录存储。
///
/// 持久化策略：
/// - 识别成功后自动 append 到 prefs（list，新条目在前）
/// - 图片保存到 app docs/receipt_ocr/`<id>`.jpg（重启路径稳定）
/// - 列表只主动清理才删除（用户操作）
class ReceiptOcrHistoryStore {
  static const _prefsKey = 'receipt_ocr_history';

  /// docs 子目录名。
  static const _imageSubdir = 'receipt_ocr';

  /// 历史最多保留条数（防止 prefs 无限膨胀）。
  static const maxEntries = 200;

  /// 加载所有历史。
  static Future<List<ReceiptOcrHistory>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = ReceiptOcrHistory.decodeList(raw);
      // 过滤掉图片已不存在的孤儿记录
      final dir = await _imageDir();
      return list
          .where((h) => File('${dir.path}/${h.imageFileName}').existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 添加一条历史（保存图片到 docs，自动写 prefs）。
  /// [sourceImagePath] 是相册/相机选出来的临时路径。
  static Future<ReceiptOcrHistory> add({
    required ReceiptOcrHistory history,
    required String sourceImagePath,
  }) async {
    final dir = await _imageDir();
    final dest = File('${dir.path}/${history.imageFileName}');
    await File(sourceImagePath).copy(dest.path);

    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.insert(0, history); // 新的在前
    if (list.length > maxEntries) {
      // 删除超出部分的图片文件
      for (final h in list.sublist(maxEntries)) {
        final f = File('${dir.path}/${h.imageFileName}');
        if (await f.exists()) await f.delete();
      }
      list.removeRange(maxEntries, list.length);
    }
    await prefs.setString(_prefsKey, ReceiptOcrHistory.encodeList(list));
    return history;
  }

  /// 主动清空全部历史（图片 + 索引）。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await _imageDir();
    if (await dir.exists()) {
      await for (final f in dir.list()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await prefs.remove(_prefsKey);
  }

  /// 删除单条历史。
  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final hit = list.firstWhere((h) => h.id == id, orElse: () => list.first);
    list.removeWhere((h) => h.id == id);
    await prefs.setString(_prefsKey, ReceiptOcrHistory.encodeList(list));
    final dir = await _imageDir();
    final f = File('${dir.path}/${hit.imageFileName}');
    if (await f.exists()) await f.delete();
  }

  static Future<Directory> _imageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_imageSubdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 暴露给 UI：历史图片所在的 docs 子目录绝对路径（同步获取，缓存）。
  static Future<String> imageDirPath() async =>
      (await _imageDir()).path;

  /// 给定文件名，返回历史图片的绝对路径。文件不存在返回 null。
  static Future<String?> resolveImagePath(String fileName) async {
    final dir = await _imageDir();
    final f = File('${dir.path}/$fileName');
    return f.existsSync() ? f.path : null;
  }
}