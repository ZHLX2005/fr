// lib/core/chess/skins/local_chess_skin.dart
//
// Thin compat wrapper over game_kit/skin/local_game_skin.dart.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show ImageProvider;

import '../../game_kit/skin/game_skin_meta.dart' as gmeta;
import '../../game_kit/skin/game_skin_spec.dart';
import '../../game_kit/skin/local_game_skin.dart' as g;
import 'chess_skin.dart';
import 'chess_skin_meta.dart';

class LocalChessSkin implements ChessSkin {
  LocalChessSkin({required this.meta, required this.dir})
      : _inner = g.LocalGameSkin(
          meta: gmeta.GameSkinMeta(
            id: meta.id,
            displayName: meta.displayName,
            pieces: meta.pieces,
            boardBackground: meta.boardBackground,
            author: meta.author,
            description: meta.description,
            version: meta.version,
            colorStyle: meta.colorStyle,
            createdAt: meta.createdAt,
            updatedAt: meta.updatedAt,
          ),
          dir: dir,
          assetKeys: kChessSkinSpec.assetKeys,
          boardBackgroundFileNameOf: g.LocalGameSkin.boardBackgroundFileName,
        );

  final ChessSkinMeta meta;
  final Directory dir;
  final g.LocalGameSkin _inner;

  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  @override
  ImageProvider? get boardBackground => _inner.boardBackground;

  @override
  Map<String, ImageProvider> get pieces => _inner.pieces;

  static LocalChessSkin? tryCreate({
    required ChessSkinMeta meta,
    required Directory dir,
  }) {
    if (kIsWeb) return null;
    if (!dir.existsSync()) return null;
    return LocalChessSkin(meta: meta, dir: dir);
  }

  static String boardBackgroundFileName(gmeta.FileRef bg) =>
      g.LocalGameSkin.boardBackgroundFileName(bg);
}
