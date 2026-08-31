// lib/core/chess/endgame/chess_endgame_store.dart
//
// 残局存储：内置 assets + 本地目录的合并读取 / 保存 / 导入 / 导出 / 删除。
//
// 目录约定（仿 chess_skin_localizer 的 <documents>/chess_skins/ 模式）：
//   本地残局 = <documents>/chess_endgames/<id>.chessendgame.json
//   内置残局 = assets/data/chess_endgames/*.json（pubspec 目录条目）
//
// 导入：FilePicker 选 .json → bytes/path 双通道读取（web / 移动端兼容，
//   仿 block_editor_demo 的跨平台读取模式）→ tryParse → save 落盘。
// 导出：写 <documents>/chess_endgames/<id>.chessendgame.json →
//   Share.shareXFiles 分享（项目无 saveFile 先例，走 share_plus 分享）。
//
// web 平台：path_provider / File 均不可用 —— loadAll 只返回内置 assets，
//   save/import/delete 抛 UnsupportedError 的文案化异常（调用方 Snackbar）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'chess_endgame.dart';

/// 残局存储（静态方法集 + 可注入目录构造，测试用）。
class ChessEndgameStore {
  /// 内置残局 assets 目录（pubspec 注册为目录条目）。
  static const String kBuiltinAssetDir = 'assets/data/chess_endgames';

  /// 本地子目录名（<documents>/chess_endgames/）。
  static const String kLocalDirName = 'chess_endgames';

  /// 应用文档目录 provider（测试注入点）。
  final Future<Directory> Function() dirProvider;

  /// web 标记（测试可覆盖）。
  final bool isWeb;

  ChessEndgameStore({Future<Directory> Function()? dirProvider, bool? isWeb})
      : dirProvider = dirProvider ?? getApplicationDocumentsDirectory,
        isWeb = isWeb ?? kIsWeb;

  // ─────────────────────────── 读取 ───────────────────────────

  /// 全量残局列表 = 内置 assets + 本地目录合并（本地同 id 覆盖内置）。
  Future<List<ChessEndgame>> loadAll() async {
    final result = <String, ChessEndgame>{};
    // 1. 内置 assets（缺失 / 坏文件逐个跳过，不影响其余）。
    try {
      final manifest = await rootBundle.loadString(
        '$kBuiltinAssetDir/index.json',
      );
      for (final name in (jsonDecodeList(manifest) ?? const <String>[])) {
        final e = await _tryLoadAsset(name);
        if (e != null) result[e.id] = e;
      }
    } on Object {
      // index.json 不存在（老包）→ 直接按文件名加载（fallback）。
      for (var i = 1; i <= 20; i++) {
        final name = 'eg_builtin_${i.toString().padLeft(2, '0')}';
        final e = await _tryLoadAsset(name);
        if (e != null) result[e.id] = e;
      }
    }
    // 2. 本地目录（web 无文件系统 → 跳过）。
    if (!isWeb) {
      try {
        final dir = await _ensureLocalDir();
        await for (final f in dir.list()) {
          if (f is! File) continue;
          if (!f.path.endsWith(kChessEndgameFileExt)) continue;
          final raw = await f.readAsString();
          final e = ChessEndgame.tryParse(
            raw,
            source: ChessEndgameSource.imported,
          );
          if (e != null) result[e.id] = e;
        }
      } on Object {
        // 目录读失败（权限等）→ 只返回内置。
      }
    }
    final list = result.values.toList();
    // 内置在前、其余按创建时间倒序（新导出的在最上）。
    list.sort((a, b) {
      final aB = a.source == ChessEndgameSource.builtin ? 0 : 1;
      final bB = b.source == ChessEndgameSource.builtin ? 0 : 1;
      if (aB != bB) return aB - bB;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  /// 内置 asset 文件名（不带扩展名）→ ChessEndgame（null = 缺失 / 坏文件）。
  Future<ChessEndgame?> _tryLoadAsset(String name) async {
    try {
      final raw =
          await rootBundle.loadString('$kBuiltinAssetDir/$name.json');
      return ChessEndgame.tryParse(
        raw,
        source: ChessEndgameSource.builtin,
      );
    } on Object {
      return null;
    }
  }

  // ─────────────────────────── 保存 / 删除 ───────────────────────────

  /// 保存（回放导出 / 导入落盘统一入口）→ <documents>/chess_endgames/。
  Future<void> save(ChessEndgame e) async {
    final dir = await _ensureLocalDir();
    final f = File('${dir.path}/${e.id}$kChessEndgameFileExt');
    await f.writeAsString(e.encode(), flush: true);
  }

  /// 本地文件是否已存在（回放导出幂等提示用）。
  Future<bool> existsLocal(String id) async {
    if (isWeb) return false;
    try {
      final dir = await _ensureLocalDir();
      return File('${dir.path}/$id$kChessEndgameFileExt').existsSync();
    } on Object {
      return false;
    }
  }

  /// 删除本地残局（内置 assets 不可删 —— 调用方只对本地条目露出删除入口）。
  Future<void> delete(String id) async {
    if (isWeb) return;
    final dir = await _ensureLocalDir();
    final f = File('${dir.path}/$id$kChessEndgameFileExt');
    if (await f.exists()) {
      await f.delete();
    }
  }

  // ─────────────────────────── 导入 / 导出 ───────────────────────────

  /// 导入：用户选 .json 文件 → 解析 → 落盘。
  ///
  /// 返回 null = 用户取消 / 文件非法（调用方 Snackbar 区分 cancelled）。
  Future<ChessEndgame?> importFromFile() async {
    if (isWeb) {
      throw UnsupportedError('web 端暂不支持文件导入');
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '选择残局文件',
      withData: true, // web / 部分平台直接带内存数据
    );
    final file = picked?.files.single;
    if (file == null) return null; // 用户取消
    // bytes（withData 内存通道）优先，否则 path（移动端文件通道）。
    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    } else {
      return null;
    }
    final e = ChessEndgame.tryParse(raw, source: ChessEndgameSource.imported);
    if (e == null) return null;
    await save(e);
    return e;
  }

  /// 导出并分享：写临时目录 → share_plus 拉起系统分享。
  /// 返回文件路径（分享失败抛异常，调用方 Snackbar）。
  Future<String> exportAndShare(ChessEndgame e) async {
    final dir = await _ensureLocalDir();
    final f = File('${dir.path}/${e.id}$kChessEndgameFileExt');
    await f.writeAsString(e.encode(), flush: true);
    final result = await Share.shareXFiles(
      [XFile(f.path)],
      text: '残局：${e.title}',
      subject: e.title,
    );
    if (result.status == ShareResultStatus.dismissed) {
      // 用户取消分享 —— 文件已落盘，不算错误。
    }
    return f.path;
  }

  // ─────────────────────────── 内部 ───────────────────────────

  Future<Directory> _ensureLocalDir() async {
    final docs = await dirProvider();
    final dir = Directory('${docs.path}/$kLocalDirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 简单 JSON 字符串数组解析（index.json 用，null = 非法）。
  static List<String>? jsonDecodeList(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is List) return v.map((e) => e.toString()).toList();
    } on FormatException {
      return null;
    }
    return null;
  }
}
