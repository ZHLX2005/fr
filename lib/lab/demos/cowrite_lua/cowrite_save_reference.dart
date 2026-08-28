// lib/lab/demos/cowrite_lua/cowrite_save_reference.dart
//
// Co-Write Notebook — 本地参考（reference）存储。
//
// 把"当前房间的笔记内容"保存到 SharedPreferences 字符串 key，
// 便于后续打开时回看 / 复制 / 复用。key 形如 `cowrite_lua.reference.{roomCode}`。
//
// 这是**纯本端**存储 —— 服务端不参与；不跨用户共享。

import 'package:shared_preferences/shared_preferences.dart';

import 'cowrite_constants.dart';

/// Co-Write 本地参考（reference）的存储 / 读取工具。
class CoWriteReferenceStore {
  CoWriteReferenceStore._();

  static String _key(String roomCode) => '$kCoWriteReferencePrefix$roomCode';

  /// 把 [content] 保存为房间 [roomCode] 的本地参考。
  /// 返回是否成功（true = 已落盘；false = 失败或空内容拒绝保存）。
  static Future<bool> save(String roomCode, String content) async {
    if (roomCode.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(roomCode), content);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取房间 [roomCode] 的本地参考（不存在返回 null）。
  static Future<String?> load(String roomCode) async {
    if (roomCode.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(roomCode));
    } catch (_) {
      return null;
    }
  }

  /// 删除房间 [roomCode] 的本地参考。
  static Future<bool> remove(String roomCode) async {
    if (roomCode.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_key(roomCode));
    } catch (_) {
      return false;
    }
  }

  /// 列出所有本地参考的 roomCode（不返回内容，只返回 key 后缀）。
  static Future<List<String>> listAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys()
          .where((k) => k.startsWith(kCoWriteReferencePrefix))
          .toList();
      return keys
          .map((k) => k.substring(kCoWriteReferencePrefix.length))
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }
}
