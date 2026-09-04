// lib/core/chess/skins/chess_skin_localizer.dart
//
// Thin compat wrapper over game_kit/skin/game_skin_localizer.dart.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/game_skin_localizer.dart' as g;
import '../../game_kit/skin/game_skin_meta.dart' as gmeta;
import '../../game_kit/skin/game_skin_spec.dart';
import 'chess_skin_meta.dart';
import 'local_chess_skin.dart';

class ChessSkinLocalizer {
  ChessSkinLocalizer({
    required FileResolver resolver,
    http.Client? client,
    Future<Directory> Function()? dirProvider,
    ChessSkinMeta? Function(String id)? metaById,
    Duration? timeout,
  }) : _inner = g.GameSkinLocalizer(
          spec: kChessSkinSpec,
          resolver: resolver,
          client: client,
          dirProvider: dirProvider,
          metaById: metaById == null
              ? null
              : (String id) {
                  final m = metaById(id);
                  if (m == null) return null;
                  return gmeta.GameSkinMeta(
                    id: m.id,
                    displayName: m.displayName,
                    pieces: m.pieces,
                    boardBackground: m.boardBackground,
                    author: m.author,
                    description: m.description,
                    version: m.version,
                    colorStyle: m.colorStyle,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt,
                  );
                },
          timeout: timeout,
        );

  final g.GameSkinLocalizer _inner;

  static const Duration defaultTimeout = g.GameSkinLocalizer.defaultTimeout;
  static const String kRootDirName = 'chess_skins';
  static const String kCachedMetaFileName = g.GameSkinLocalizer.kCachedMetaFileName;
  static const String kDoneMarker = g.GameSkinLocalizer.kDoneMarker;
  static bool get isSupported => g.GameSkinLocalizer.isSupported;

  static Future<void> ensureBaseDirInit() => g.GameSkinLocalizer.ensureBaseDirInitFor(kChessSkinSpec);

  // ignore: invalid_use_of_visible_for_testing_member
  static void setBaseDirForTest(Directory? dir) =>
      // ignore: invalid_use_of_visible_for_testing_member
      g.GameSkinLocalizer.setBaseDirForTest(dir, spec: kChessSkinSpec);

  static File? cachedPieceFile(
    String skinId,
    String fileName, {
    required String expectedFileId,
  }) =>
      g.GameSkinLocalizer.cachedPieceFileFor(
        kChessSkinSpec,
        skinId,
        fileName,
        expectedFileId: expectedFileId,
      );

  Future<Directory> dirFor(String skinId) => _inner.dirFor(skinId);
  Future<bool> isCached(String skinId) => _inner.isCached(skinId);
  Future<LocalChessSkin?> fromCache(String skinId) async {
    final s = await _inner.fromCache(skinId);
    if (s == null) return null;
    return LocalChessSkin(
      meta: ChessSkinMeta(
        id: s.meta.id,
        displayName: s.meta.displayName,
        pieces: s.meta.pieces,
        boardBackground: s.meta.boardBackground,
        author: s.meta.author,
        description: s.meta.description,
        version: s.meta.version,
        colorStyle: s.meta.colorStyle,
        createdAt: s.meta.createdAt,
        updatedAt: s.meta.updatedAt,
      ),
      dir: s.dir,
    );
  }

  Future<LocalChessSkin> ensureLocal(ChessSkinMeta meta) async {
    final gmeta.GameSkinMeta gmeta2 = gmeta.GameSkinMeta(
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
    );
    final s = await _inner.ensureLocal(gmeta2);
    return LocalChessSkin(
      meta: ChessSkinMeta(
        id: s.meta.id,
        displayName: s.meta.displayName,
        pieces: s.meta.pieces,
        boardBackground: s.meta.boardBackground,
        author: s.meta.author,
        description: s.meta.description,
        version: s.meta.version,
        colorStyle: s.meta.colorStyle,
        createdAt: s.meta.createdAt,
        updatedAt: s.meta.updatedAt,
      ),
      dir: s.dir,
    );
  }

  Future<LocalChessSkin> download(ChessSkinMeta meta) async {
    final gmeta.GameSkinMeta gmeta2 = gmeta.GameSkinMeta(
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
    );
    final s = await _inner.download(gmeta2);
    return LocalChessSkin(
      meta: ChessSkinMeta(
        id: s.meta.id,
        displayName: s.meta.displayName,
        pieces: s.meta.pieces,
        boardBackground: s.meta.boardBackground,
        author: s.meta.author,
        description: s.meta.description,
        version: s.meta.version,
        colorStyle: s.meta.colorStyle,
        createdAt: s.meta.createdAt,
        updatedAt: s.meta.updatedAt,
      ),
      dir: s.dir,
    );
  }
}
