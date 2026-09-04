// lib/core/chess/skins/chess_skin.dart
//
// Thin compat wrapper over game_kit/skin.
// Preserves: ChessSkin, ChessDefaultSkin, ChessSkinBundle, kDefaultChessSkinBaseUrl,
//            kChessSkinKeys, chessSkinKeyOf, chessSkinIsComplete.

import 'dart:async' show unawaited;

import '../../game_kit/skin/file_resolver.dart';
import '../../game_kit/skin/game_skin_bundle.dart' as g;
import '../../game_kit/skin/game_skin_localizer.dart';
import '../../game_kit/skin/game_skin_meta.dart' as gmeta;
import '../../game_kit/skin/game_skin_spec.dart';
import '../models/piece.dart';
import 'chess_skin_meta.dart';

/// 内置 skin 远端 baseUrl 默认值。
const String kDefaultChessSkinBaseUrl = 'http://47.110.80.47:8988';

/// 12 个 piece key 集合（compat 别名）.
const Set<String> kChessSkinKeys = kChessSkin12PieceKeys;

String chessSkinKeyOf(PieceColor color, PieceType type) {
  const whiteBack = ['wK', 'wQ', 'wR', 'wB', 'wN'];
  const blackBack = ['bK', 'bQ', 'bR', 'bB', 'bN'];
  if (type == PieceType.pawn) {
    return color == PieceColor.white ? 'wp' : 'bp';
  }
  final arr = color == PieceColor.white ? whiteBack : blackBack;
  return arr[type.index];
}

bool chessSkinIsComplete(ChessSkin skin) =>
    skin.pieces.length == kChessSkinKeys.length &&
        kChessSkinKeys.every(skin.pieces.containsKey);

/// 兼容类型别名（旧代码 import ChessSkin）.
typedef ChessSkin = g.GameSkin;
typedef ChessDefaultSkin = g.GameDefaultSkin;

/// Thin static facade over a singleton GameSkinBundle(chess spec).
abstract class ChessSkinBundle {
  static final g.GameSkinBundle _bundle = g.GameSkinBundle(kChessSkinSpec);

  static Map<String, ChessSkin> get all => _bundle.all;
  static List<gmeta.GameSkinMeta> get metas =>
      _bundle.metas.cast<gmeta.GameSkinMeta>();
  static int get metaCount => _bundle.metaCount;
  static ChessSkin byId(String id) => _bundle.byId(id);

  static g.GameSkinBundle get bundle => _bundle;

  static void registerHardcoded() {
    unawaited(GameSkinLocalizer.ensureBaseDirInitFor(kChessSkinSpec));
    final catalog = kChessSkinsCatalog
        .map((m) => gmeta.GameSkinMeta(
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
            ))
        .toList();
    _bundle.registerHardcoded(
      catalog,
      fileResolver: const PublicFileResolver(baseUrl: kDefaultChessSkinBaseUrl),
    );
  }

  static void registerRemoteSkins(
    List<gmeta.GameSkinMeta> metas, {
    required FileResolver fileResolver,
  }) {
    _bundle.registerRemoteSkins(metas, fileResolver: fileResolver);
  }

  // ignore: invalid_use_of_visible_for_testing_member
  static void resetForTest() => _bundle.resetForTest();
}
