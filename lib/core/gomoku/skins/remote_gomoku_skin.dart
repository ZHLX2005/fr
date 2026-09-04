// lib/core/gomoku/skins/remote_gomoku_skin.dart
//
// GomokuSkin 的远端实现：FileRef → ImageProvider（本地缓存优先，网络回退）。

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import '../../chess/skins/chess_skin_localizer.dart';
import '../../chess/skins/file_resolver.dart';
import 'gomoku_skin.dart';
import 'gomoku_skin_meta.dart';
import 'local_gomoku_skin.dart';

class RemoteGomokuSkin implements GomokuSkin {
  final GomokuSkinMeta meta;
  final FileResolver fileResolver;

  const RemoteGomokuSkin({required this.meta, required this.fileResolver});

  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  @override
  Map<String, ImageProvider> get pieces => {
        for (final entry in meta.assets.entries)
          if (entry.key == 'black' || entry.key == 'white')
            entry.key: _providerFor('${entry.key}.webp', entry.value.fileId),
      };

  @override
  ImageProvider? get boardBackground {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return _providerFor(LocalGomokuSkin.boardBackgroundFileName(bg), bg.fileId);
  }

  ImageProvider _providerFor(String localFileName, String fileId) {
    final local = ChessSkinLocalizer.cachedPieceFile(
      meta.id,
      localFileName,
      expectedFileId: fileId,
    );
    if (local != null) return FileImage(local);
    return CachedNetworkImageProvider(fileResolver.url(fileId));
  }
}
