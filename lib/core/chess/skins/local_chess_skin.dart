// lib/core/chess/skins/local_chess_skin.dart
//
// 本地皮肤 —— 棋子/棋盘图片从本地磁盘文件读取（FileImage），离线可用。
//
// 与 RemoteChessSkin（CachedNetworkImage，逐帧走网络）的区别：
//   · pieces / boardBackground 全部是 FileImage(File(...)) —— 零网络
//   · 文件由 ChessSkinLocalizer.download() 预先写到
//     <app documents>/chess_skins/<skinId>/ 目录
//   · 文件缺 key 时（半缓存 / 目录被清理）该 key 直接不出现在 pieces，
//     上层 ChessBoard / PromotionPanel 自动走 unicode 回退 —— 与
//     ChessDefaultSkin（空 map）行为一致，绝不抛异常
//
// Web 平台注意：dart:io FileImage 在 web 上不可用，构造时返回 null
// （由调用方决定回退 RemoteChessSkin / unicode），见 [LocalChessSkin.tryCreate]。

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import 'chess_skin.dart';
import 'chess_skin_meta.dart';

/// 本地皮肤 —— 棋子/棋盘图片从本地文件读取（FileImage），离线可用。
class LocalChessSkin implements ChessSkin {
  LocalChessSkin({required this.meta, required this.dir});

  /// 源 metadata（id / displayName / 资源引用）。
  final ChessSkinMeta meta;

  /// 本地资源目录（`<app documents>/chess_skins/<skinId>/`）。
  final Directory dir;

  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  /// 棋盘底图：`<dir>/boardBackground.<ext>` 存在才提供，否则 null。
  @override
  ImageProvider? get boardBackground {
    final f = _boardBackgroundFile;
    if (f == null || !f.existsSync()) return null;
    return FileImage(f);
  }

  /// 12 个棋子：`<dir>/<pieceKey>.webp` 存在才提供（缺文件 → 省略 → unicode 回退）。
  @override
  Map<String, ImageProvider> get pieces => {
    for (final key in kChessSkin12PieceKeys)
      if (_pieceFile(key).existsSync()) key: FileImage(_pieceFile(key)),
  };

  /// 构造 [LocalChessSkin] 的 Web 安全入口。
  ///
  /// - Web（无 dart:io / FileImage）→ 返回 null（调用方回退网络皮肤 / unicode）。
  /// - [dir] 不存在 → 返回 null（目录被清理等场景，走重新下载）。
  static LocalChessSkin? tryCreate({
    required ChessSkinMeta meta,
    required Directory dir,
  }) {
    if (kIsWeb) return null;
    if (!dir.existsSync()) return null;
    return LocalChessSkin(meta: meta, dir: dir);
  }

  /// 棋盘底图文件名（按 [FileRef.contentType] 推导扩展名；未知类型用 webp 兜底）。
  static String boardBackgroundFileName(FileRef bg) {
    final contentType = bg.contentType.toLowerCase();
    if (contentType.contains('png')) return 'boardBackground.png';
    if (contentType.contains('jpeg') || contentType.contains('jpg')) {
      return 'boardBackground.jpg';
    }
    // webp / octet-stream / 未知 → 按 webp 处理（server 上棋皮均为 webp）
    return 'boardBackground.webp';
  }

  File? get _boardBackgroundFile {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return File('${dir.path}/${boardBackgroundFileName(bg)}');
  }

  File _pieceFile(String key) => File('${dir.path}/$key.webp');
}
