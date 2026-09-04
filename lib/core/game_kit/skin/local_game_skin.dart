// lib/core/game_kit/skin/local_game_skin.dart
//
// Generic local skin: disk FileImage skin (extracted from lib/core/chess/skins/local_chess_skin.dart).

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import 'game_skin_bundle.dart';
import 'game_skin_meta.dart';

/// 本地皮肤 —— 从本地文件渲染（FileImage），离线可用。
class LocalGameSkin implements GameSkin {
  LocalGameSkin({
    required this.meta,
    required this.dir,
    required this.assetKeys,
    required this.boardBackgroundFileNameOf,
  });

  final GameSkinMeta meta;
  final Directory dir;
  final Set<String> assetKeys;
  final String Function(FileRef bg) boardBackgroundFileNameOf;

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
    for (final key in assetKeys)
      if (_pieceFile(key).existsSync()) key: FileImage(_pieceFile(key)),
  };

  static LocalGameSkin? tryCreate({
    required GameSkinMeta meta,
    required Directory dir,
    required Set<String> assetKeys,
    required String Function(FileRef bg) boardBackgroundFileNameOf,
  }) {
    if (kIsWeb) return null;
    if (!dir.existsSync()) return null;
    return LocalGameSkin(
      meta: meta,
      dir: dir,
      assetKeys: assetKeys,
      boardBackgroundFileNameOf: boardBackgroundFileNameOf,
    );
  }

  static String boardBackgroundFileName(FileRef bg) {
    final contentType = bg.contentType.toLowerCase();
    if (contentType.contains('png')) return 'boardBackground.png';
    if (contentType.contains('jpeg') || contentType.contains('jpg')) {
      return 'boardBackground.jpg';
    }
    return 'boardBackground.webp';
  }

  File? get _boardBackgroundFile {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return File('${dir.path}/${boardBackgroundFileNameOf(bg)}');
  }

  File _pieceFile(String key) => File('${dir.path}/$key.webp');
}
