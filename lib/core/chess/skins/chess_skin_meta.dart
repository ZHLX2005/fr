// lib/core/chess/skins/chess_skin_meta.dart
//
// Thin compat wrapper: re-exports generic game_skin_meta + chess 12-key
// constants + kChessSkinsCatalog (preserved verbatim for zero regression).

import '../../game_kit/skin/game_skin_meta.dart' as g;

export '../../game_kit/skin/game_skin_meta.dart' show FileRef, GameSkinMeta;

const Set<String> kChessSkin12PieceKeys = {
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wp',
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bp',
};

const Set<String> kChessSkinKeys = kChessSkin12PieceKeys;

final RegExp kChessSkinIdPattern = g.kGameSkinIdPattern;

typedef ChessSkinMeta = g.GameSkinMeta;

extension ChessSkinMetaCheck on g.GameSkinMeta {
  bool get isComplete {
    if (pieces.length != 12) return false;
    for (final k in kChessSkin12PieceKeys) {
      if (!pieces.containsKey(k)) return false;
    }
    return true;
  }
}

const List<g.GameSkinMeta> kChessSkinsCatalog = [
  g.GameSkinMeta(
    id: '1',
    displayName: '皮肤 1',
    pieces: {
      'wK': g.FileRef(fileId: '0f6a7d9256a248309fa249e58724a351', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: '22b198f661754be988245eb6a5fc7bf1', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: '3fe1caad3c7e22c6fdbcdd14836d5ffc', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '99d7e2a9129684e8ea655ba26f51ffb0', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: 'e680f9902cbd213af70ccfb4065e604e', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: 'ab189290f2d9e7b5d0d90ac9301a048e', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '195c8d27a0ad87e74b0400f4725cbb9f', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: '2d9f1272fafcc7b47723d35caf4ef85f', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: '127b3f5a8c270e6cc87ee66d3ff5e168', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: 'b0f7107ff70ce0a90140c42a32fe0405', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: 'd679042d8831d5506d33bfcd002d670b', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '42e1eaa70750ff6237433fe17ff9071b', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '2',
    displayName: '皮肤 2',
    pieces: {
      'wK': g.FileRef(fileId: '5d221a17400d0c536f40aaa3f66768c6', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: '4ac7bb42c9e31bea25048ad7ca61cd64', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: '0965797ad13e370f8fe4919610dfa00a', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '84b6df8367b8c01dc37c8c9b3f8d1df8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: '6b2464e052d572d93b16bed2c6447078', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: 'ad65316e8cd7df6f571722878deb9401', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: 'c4f7cdefb9fe2bace7e13186a0db8602', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: 'c772253b521e7ffd2bbf82957accaef5', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: 'd3f95f6e5abb9f3134a797b5602e9d1b', fileName: '08_black_rook.webp', sizeBytes: 5416, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: '2cc158aea5125b686b08c46b4109a9a0', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: 'b488f7d7e93657b50755954483325ead', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '445eb1d6de6dfe68d4adb7b9feef4598', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '3',
    displayName: '皮肤 3',
    pieces: {
      'wK': g.FileRef(fileId: '5e319f064bcc5a3ac0b3ead595bf7c72', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: 'aac7c2e32f3f2e970737d3eba990cffb', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: '0058a7857dc80f9f59e3ec22e4173601', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '7ac7b201f00e8861d1150b4bf947e2a8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: 'cbcb61787db696dc3190533183fc4571', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: 'e939c5a2acfb816d980faeed30134574', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '1cb563689f86dda5fee64e75811a18b4', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: '695ef847610c8c47109c86708efd5020', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: '6b29c922261e39b037a47228bd5735fb', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: '28e179611ea718357375da4e70e5a6a6', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: '9422e02b78a74852ed4aa3448f096f06', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '40aa8c30216ccffef52198e88c9aee8d', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '4',
    displayName: '皮肤 4',
    pieces: {
      'wK': g.FileRef(fileId: '461229a4bbf46fdbad8df04126b253e2', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: 'af7e6ff199545fa262fb65edbf887806', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: '79ab736373b4f7788c9a26752218ae6d', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: 'd98b5d90d6b51b69ba332d0ab39a36b8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: '87b0290f4c31bf3e6240e98e65103659', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: '2f7e8f0bcad5a881f29dabd67b9bb058', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '6d5bcd59fcded32c5febf19dafa06e6c', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: 'c18a9c49a85a7d2e0652d139f92c8ffa', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: '832683276064d3571d0c8cc4cc0bf628', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: '3c942aae64829aeae9ecab44050fe1eb', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: 'ae2829cc18a99f1357f6aa93ddfebdc2', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '34e877d984e0bfb934190535265f0b4f', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '5',
    displayName: '皮肤 5',
    pieces: {
      'wK': g.FileRef(fileId: '65658614c08ea92765454ed543d64826', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: '6d5a1b27398005a152015b7db76499e6', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: '8691ff5e6c42415c640e8f2040b5fada', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '137d3f3eb5e3b528e1e02c609e7a277b', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: 'd6b6477c8aff5a1f843486735e2a76c5', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: '8f044832078da9804e3057d2249388a1', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '417d3b50c48c84629bd756fefdba2fb7', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: '5022e4d39c34ba374adc8f720d3f9fa8', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: 'b6e40d572ad59cb38742cdce99879e7f', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: '7ac48819e043a395aa88d17a61d438ed', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: '946fc646875077c790d6d9d161658b9e', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '7dcaab965fa3a1fc5ad5497550793b16', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '6',
    displayName: '皮肤 6',
    pieces: {
      'wK': g.FileRef(fileId: '10848d8d60e22949f7508e1afadb0fb2', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: '04748654d7dc1d6d329c17a1fd580506', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: 'a3cf6419600777d6e0fe41409d58c3f7', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '75b9009765a18e7fb6c2768946111f02', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: '36f78cf2843514326370334ab9c9d974', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: '61548c4e75214703be2c5bdd9cc21615', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '32d915121a8592fd95c7529c6de496d0', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: 'ec31bc62092e51322280fb589ad39fb5', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: '739b4c0f88db802fa85c96a3126b35e1', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: '62bad9ebcb1d2c3642f0a8e388570990', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: '3a945d379dee4808f252580ec521f423', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: 'ea9167d039156c04cf797dbdb2e33a84', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  g.GameSkinMeta(
    id: '7',
    displayName: '皮肤 7',
    pieces: {
      'wK': g.FileRef(fileId: '3fcfbaa46486f8538bba932b00454496', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': g.FileRef(fileId: 'fdb14b47151497bf53d63dac0a417b0e', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': g.FileRef(fileId: 'f8fe9cb32fd4e18b315a38c908eb4254', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': g.FileRef(fileId: '79454b419251b9917c03311f95387068', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': g.FileRef(fileId: 'ec2e34c067acb0aef9a38dc36222c251', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': g.FileRef(fileId: '09b2736d397e0f7e6ac117ab920b0a8e', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': g.FileRef(fileId: '8ce8e412dd39bddb90626eff64b16c6c', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': g.FileRef(fileId: 'daafee46793cd9cd3a7d015bea5291bd', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': g.FileRef(fileId: 'eeb2f17bee669c1c5615f1f9ed85361f', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': g.FileRef(fileId: 'b112fedafdd790fa07a0d126525274fb', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': g.FileRef(fileId: 'c9aaac2583c19d4686a43ba5e8fcca2d', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': g.FileRef(fileId: '4f5a96cda424b407e64ae30460c96990', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
];
