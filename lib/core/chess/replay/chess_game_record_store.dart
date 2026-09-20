// lib/core/chess/replay/chess_game_record_store.dart
//
// 整局对局记录存储 —— 仿 ChessEndgameStore 的本地目录模式：
//   `<documents>/chess_games/<id>.chessgame.json`
//
// 与残局库的差异（刻意最小化）：
//   · 无内置 assets（对局记录全是本地产物）
//   · 无 FilePicker 导入 / share 分享（需要时再加）
//
// web 平台：path_provider / File 均不可用 —— loadAll 返回空表，
//   save/delete 抛 UnsupportedError 文案化异常（调用方 Snackbar）。

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'chess_game_record.dart';

/// 整局对局记录存储（静态语义 + 可注入目录构造，测试用）。
class ChessGameRecordStore {
  /// 本地子目录名（`<documents>/chess_games/`）。
  static const String kLocalDirName = 'chess_games';

  /// 应用文档目录 provider（测试注入点）。
  final Future<Directory> Function() dirProvider;

  /// web 标记（测试可覆盖）。
  final bool isWeb;

  ChessGameRecordStore({Future<Directory> Function()? dirProvider, bool? isWeb})
      : dirProvider = dirProvider ?? getApplicationDocumentsDirectory,
        isWeb = isWeb ?? kIsWeb;

  /// 全部对局记录（按保存时间倒序 —— 新保存的在最上）。
  ///
  /// 坏文件逐个跳过，不影响其余。
  Future<List<ChessGameRecord>> loadAll() async {
    if (isWeb) return const [];
    final out = <ChessGameRecord>[];
    try {
      final dir = await _ensureLocalDir();
      await for (final f in dir.list()) {
        if (f is! File) continue;
        if (!f.path.endsWith(kChessGameFileExt)) continue;
        try {
          final raw = await f.readAsString();
          final r = ChessGameRecord.tryParse(raw);
          if (r != null) out.add(r);
        } on Object {
          // 单文件读失败（编码 / 权限）→ 跳过。
        }
      }
    } on Object {
      // 目录读失败（权限等）→ 返回空表。
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// 保存（落盘统一入口）→ `<documents>/chess_games/`。
  Future<void> save(ChessGameRecord r) async {
    if (isWeb) {
      throw UnsupportedError('web 端暂不支持保存对局记录');
    }
    final dir = await _ensureLocalDir();
    final f = File('${dir.path}/${r.id}$kChessGameFileExt');
    await f.writeAsString(r.encode(), flush: true);
  }

  /// 本地文件是否已存在（保存幂等提示用）。
  Future<bool> existsLocal(String id) async {
    if (isWeb) return false;
    try {
      final dir = await _ensureLocalDir();
      return File('${dir.path}/$id$kChessGameFileExt').existsSync();
    } on Object {
      return false;
    }
  }

  /// 删除本地对局记录。
  Future<void> delete(String id) async {
    if (isWeb) return;
    final dir = await _ensureLocalDir();
    final f = File('${dir.path}/$id$kChessGameFileExt');
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<Directory> _ensureLocalDir() async {
    final docs = await dirProvider();
    final dir = Directory('${docs.path}/$kLocalDirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
