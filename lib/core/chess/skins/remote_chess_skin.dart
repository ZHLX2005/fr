// lib/core/chess/skins/remote_chess_skin.dart
//
// Thin compat wrapper over game_kit/skin/remote_game_skin.dart.

import 'package:flutter/painting.dart' show ImageProvider;

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/game_skin_meta.dart' as gmeta;
import '../../game_kit/skin/local_game_skin.dart' as g;
import '../../game_kit/skin/remote_game_skin.dart' as gremote;
import 'chess_skin.dart';
import 'chess_skin_meta.dart';

class RemoteChessSkin implements ChessSkin {
  RemoteChessSkin({
    required this.meta,
    required this.fileResolver,
  }) : _inner = gremote.RemoteGameSkin(
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
          fileResolver: fileResolver,
          boardBackgroundFileNameOf: g.LocalGameSkin.boardBackgroundFileName,
        );

  final ChessSkinMeta meta;
  final FileResolver fileResolver;
  final gremote.RemoteGameSkin _inner;

  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  @override
  Map<String, ImageProvider> get pieces => _inner.pieces;

  @override
  ImageProvider? get boardBackground => _inner.boardBackground;
}
