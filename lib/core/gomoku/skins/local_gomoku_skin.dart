// lib/core/gomoku/skins/local_gomoku_skin.dart
//
// 五子棋本地皮肤 —— FileImage 离线渲染（对齐 LocalChessSkin）。

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import '../../chess/skins/chess_skin_meta.dart' show FileRef;
import 'gomoku_skin.dart';
import 'gomoku_skin_meta.dart';

class LocalGomokuSkin implements GomokuSkin {
  LocalGomokuSkin({required this.meta, required this.dir});

  final GomokuSkinMeta meta;
  final Directory dir;

  @override
  String get id => meta.id;
  @override
  String get displayName => meta.displayName;

  @override
  ImageProvider? get boardBackground {
    final f = _boardBackgroundFile;
    if (f == null || !f.existsSync()) return null;
    return FileImage(f);
  }

  @override
  Map<String, ImageProvider> get pieces => {
        for (final key in kGomokuStoneKeys)
          if (_pieceFile(key).existsSync()) key: FileImage(_pieceFile(key)),
      };

  static LocalGomokuSkin? tryCreate({
    required GomokuSkinMeta meta,
    required Directory dir,
  }) {
    if (kIsWeb) return null;
    if (!dir.existsSync()) return null;
    return LocalGomokuSkin(meta: meta, dir: dir);
  }

  static String boardBackgroundFileName(FileRef bg) {
    final ct = bg.contentType.toLowerCase();
    if (ct.contains('png')) return 'boardBackground.png';
    if (ct.contains('jpeg') || ct.contains('jpg')) return 'boardBackground.jpg';
    return 'boardBackground.webp';
  }

  File? get _boardBackgroundFile {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return File('${dir.path}/${boardBackgroundFileName(bg)}');
  }

  File _pieceFile(String key) => File('${dir.path}/$key.webp');
}
