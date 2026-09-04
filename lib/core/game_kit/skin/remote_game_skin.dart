// lib/core/game_kit/skin/remote_game_skin.dart
//
// Generic remote skin: GameSkinMeta + FileResolver → GameSkin
// (extracted from lib/core/chess/skins/remote_chess_skin.dart).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import 'file_resolver.dart';
import 'game_skin_bundle.dart';
import 'game_skin_localizer.dart';
import 'game_skin_meta.dart';

class RemoteGameSkin implements GameSkin {
  final GameSkinMeta meta;
  final FileResolver fileResolver;
  final String Function(FileRef bg) boardBackgroundFileNameOf;

  const RemoteGameSkin({
    required this.meta,
    required this.fileResolver,
    required this.boardBackgroundFileNameOf,
  });

  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  @override
  Map<String, ImageProvider> get pieces => {
        for (final entry in meta.pieces.entries)
          entry.key: _providerFor('${entry.key}.webp', entry.value.fileId),
      };

  @override
  ImageProvider? get boardBackground {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return _providerFor(boardBackgroundFileNameOf(bg), bg.fileId);
  }

  ImageProvider _providerFor(String localFileName, String fileId) {
    final local = GameSkinLocalizer.cachedPieceFile(
      meta.id,
      localFileName,
      expectedFileId: fileId,
    );
    if (local != null) return FileImage(local);
    return CachedNetworkImageProvider(fileResolver.url(fileId));
  }
}
