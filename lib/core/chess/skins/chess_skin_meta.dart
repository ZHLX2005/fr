// lib/core/chess/skins/chess_skin_meta.dart
//
// 国际象棋棋盘皮肤的 metadata 模型 + 7 套 hardcode catalog。
//
// 设计要点（参见 docs/superpowers/specs/2026-08-29-chess-skin-kv-design.md §2 §3）：
//   - ChessSkinMeta + FileRef 都是 const 模型（编译期常量）
//   - 12 个 piece key 固定：wK / wQ / wR / wB / wN / wp / bK / bQ / bR / bB / bN / bp
//   - kChessSkinsCatalog 是 const List<ChessSkinMeta>，含 7 套皮肤
//   - fileId 是 32-char hex（实测 server 端用 md5 风格命名）
//   - ChessSkinMeta.isComplete（extension）校验 12-key 完整性
//   - ChessSkinMeta.parseList(jsonText) 用于把将来可能扩展的 KV/网络载入流程统一入口
//     （v1 用 const catalog；此接口为以后热更新铺路）

import 'dart:convert';

/// 单张棋子 / 棋盘底图的远端资源引用
///
/// 通过 [fileId] 在 server 端拿到唯一资源，由 `PublicFileResolver`
/// 拼成 `http://<baseUrl>/files/<fileId>` 公开 URL 给 `CachedNetworkImage` 渲染。
///
/// 注：本项目惯例不在 chess 模块引入 `package:meta/meta.dart` 的 `@immutable`
/// （见 `lib/core/chess/models/board_state.dart`）—— 用 const 构造 + 全 final 字段
/// 保证等价 immutable 语义。
class FileRef {
  /// 32-char hex 字符串，对应 server 后端的 MD5 风格 file id。
  final String fileId;

  /// 原始文件名（debug / file list 显示用）。
  final String fileName;

  /// 字节数（客户端 cache key 校验）。
  final int sizeBytes;

  /// MIME（`image/webp` / `image/png` / `application/octet-stream`）。
  final String contentType;

  const FileRef({
    required this.fileId,
    required this.fileName,
    required this.sizeBytes,
    required this.contentType,
  });

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'contentType': contentType,
      };

  factory FileRef.fromJson(Map<String, dynamic> j) => FileRef(
        fileId: j['fileId'] as String,
        fileName: j['fileName'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        contentType: j['contentType'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is FileRef &&
      fileId == other.fileId &&
      fileName == other.fileName &&
      sizeBytes == other.sizeBytes &&
      contentType == other.contentType;

  @override
  int get hashCode => Object.hash(fileId, fileName, sizeBytes, contentType);
}

/// 12 个 piece key 集合（顺序无关）
const Set<String> kChessSkin12PieceKeys = {
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wp',
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bp',
};

/// skin id 正则（KCartesian kebab-case 数字/小写字母/横线）
final RegExp kChessSkinIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// 一套皮肤的 metadata（immutable value 类型）
///
/// v1 用 `const` catalog；将来热更新路径（见 spec §0 修订说明）
/// 可换为运行时载入的相同结构。
class ChessSkinMeta {
  /// 唯一 skin id（如 `staunty`、`classic-wood`、`1`、`2`...）。
  final String id;

  /// UI 显示名（i18n 留给上层翻译）。
  final String displayName;

  /// 12 个 piece 的资源引用（key 见 [kChessSkin12PieceKeys]）。
  final Map<String, FileRef> pieces;

  /// 棋盘底图（可选）。null 时 UI 走默认 `context.chessColors` 双色格。
  final FileRef? boardBackground;

  /// 作者署名（可空）
  final String? author;

  /// 描述（可空）
  final String? description;

  /// 单调递增版本号，UI 不强制校验
  final int version;

  /// 颜色风格：`warm`/`cool`/`mono`/`vivid`（可空）
  final String? colorStyle;

  /// ISO 8601（可空）
  final String? createdAt;

  /// ISO 8601（可空）
  final String? updatedAt;

  const ChessSkinMeta({
    required this.id,
    required this.displayName,
    required this.pieces,
    this.boardBackground,
    this.author,
    this.description,
    this.version = 1,
    this.colorStyle,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (author != null) 'author': author,
        if (description != null) 'description': description,
        'version': version,
        if (colorStyle != null) 'colorStyle': colorStyle,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (boardBackground != null) 'boardBackground': boardBackground!.toJson(),
        'pieces': {
          for (final entry in pieces.entries)
            entry.key: entry.value.toJson(),
        },
      };

  factory ChessSkinMeta.fromJson(Map<String, dynamic> j) {
    final rawPieces = j['pieces'] as Map<String, dynamic>;
    final pieces = <String, FileRef>{
      for (final entry in rawPieces.entries)
        entry.key: FileRef.fromJson(entry.value as Map<String, dynamic>),
    };
    return ChessSkinMeta(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      pieces: pieces,
      boardBackground: j['boardBackground'] != null
          ? FileRef.fromJson(j['boardBackground'] as Map<String, dynamic>)
          : null,
      author: j['author'] as String?,
      description: j['description'] as String?,
      version: (j['version'] as num?)?.toInt() ?? 1,
      colorStyle: j['colorStyle'] as String?,
      createdAt: j['createdAt'] as String?,
      updatedAt: j['updatedAt'] as String?,
    );
  }

  /// 解析 [jsonText]（一个 JSON array）成 [List<ChessSkinMeta>]。
  ///
  /// 错误：duplicate id 抛 [FormatException]；id 不符合正则抛 [FormatException]。
  static List<ChessSkinMeta> parseList(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! List) throw const FormatException('expected JSON array');
    final seen = <String>{};
    final out = <ChessSkinMeta>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('expected object in array');
      }
      final s = ChessSkinMeta.fromJson(e);
      if (!kChessSkinIdPattern.hasMatch(s.id)) {
        throw FormatException('invalid skin id: ${s.id}');
      }
      if (!seen.add(s.id)) {
        throw FormatException('duplicate skin id: ${s.id}');
      }
      out.add(s);
    }
    return out;
  }
}

/// 完整性校验：完整 12-piece（每侧各 6 棋子）+ boardBackground 可选。
///
/// 作为 extension 而不是顶层 `chessSkinIsComplete` 是为了避免和
/// `lib/core/chess/skins/chess_skin.dart` 已有的同名顶层函数冲突
/// （那里签名为 `(ChessSkin)`，这里是 `(ChessSkinMeta)`）。
extension ChessSkinMetaCheck on ChessSkinMeta {
  /// 完整 12-piece 校验（每侧各 6 棋子）+ boardBackground 可选
  bool get isComplete {
    if (pieces.length != 12) return false;
    for (final k in kChessSkin12PieceKeys) {
      if (!pieces.containsKey(k)) return false;
    }
    return true;
  }
}

/// 7 套皮肤 catalog（hardcode 在 dart 源）。
///
/// 文件 ID 从 `tool/upload_chess_skins/chess_skins_file_ids.json` 固化。
/// 上传时间：2026-08-29，13 / 13 OK + 84 / 84 md5 一致（task #39）。
///
/// 注意：directory 命名 `chess/2/{1..7}/` → skin id "1"-"7" 是数字；
/// 这里为了和未来 kebab-case 兼容仍走同一个正则校验（数字允许）。
const List<ChessSkinMeta> kChessSkinsCatalog = [
  // ─── Skin 1 (chess/2/1/, 不含 boardBackground) ───
  ChessSkinMeta(
    id: '1',
    displayName: '皮肤 1',
    pieces: {
      'wK': FileRef(fileId: '0f6a7d9256a248309fa249e58724a351', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: '22b198f661754be988245eb6a5fc7bf1', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: '3fe1caad3c7e22c6fdbcdd14836d5ffc', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '99d7e2a9129684e8ea655ba26f51ffb0', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: 'e680f9902cbd213af70ccfb4065e604e', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: 'ab189290f2d9e7b5d0d90ac9301a048e', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '195c8d27a0ad87e74b0400f4725cbb9f', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: '2d9f1272fafcc7b47723d35caf4ef85f', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: '127b3f5a8c270e6cc87ee66d3ff5e168', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: 'b0f7107ff70ce0a90140c42a32fe0405', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: 'd679042d8831d5506d33bfcd002d670b', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '42e1eaa70750ff6237433fe17ff9071b', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 2 (chess/2/2/) ───
  ChessSkinMeta(
    id: '2',
    displayName: '皮肤 2',
    pieces: {
      'wK': FileRef(fileId: '5d221a17400d0c536f40aaa3f66768c6', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: '4ac7bb42c9e31bea25048ad7ca61cd64', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: '0965797ad13e370f8fe4919610dfa00a', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '84b6df8367b8c01dc37c8c9b3f8d1df8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: '6b2464e052d572d93b16bed2c6447078', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: 'ad65316e8cd7df6f571722878deb9401', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: 'c4f7cdefb9fe2bace7e13186a0db8602', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: 'c772253b521e7ffd2bbf82957accaef5', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: 'd3f95f6e5abb9f3134a797b5602e9d1b', fileName: '08_black_rook.webp', sizeBytes: 5416, contentType: 'image/webp'),
      'bB': FileRef(fileId: '2cc158aea5125b686b08c46b4109a9a0', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: 'b488f7d7e93657b50755954483325ead', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '445eb1d6de6dfe68d4adb7b9feef4598', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 3 (chess/2/3/) ───
  ChessSkinMeta(
    id: '3',
    displayName: '皮肤 3',
    pieces: {
      'wK': FileRef(fileId: '5e319f064bcc5a3ac0b3ead595bf7c72', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: 'aac7c2e32f3f2e970737d3eba990cffb', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: '0058a7857dc80f9f59e3ec22e4173601', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '7ac7b201f00e8861d1150b4bf947e2a8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: 'cbcb61787db696dc3190533183fc4571', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: 'e939c5a2acfb816d980faeed30134574', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '1cb563689f86dda5fee64e75811a18b4', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: '695ef847610c8c47109c86708efd5020', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: '6b29c922261e39b037a47228bd5735fb', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: '28e179611ea718357375da4e70e5a6a6', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: '9422e02b78a74852ed4aa3448f096f06', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '40aa8c30216ccffef52198e88c9aee8d', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 4 (chess/2/4/) ───
  ChessSkinMeta(
    id: '4',
    displayName: '皮肤 4',
    pieces: {
      'wK': FileRef(fileId: '461229a4bbf46fdbad8df04126b253e2', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: 'af7e6ff199545fa262fb65edbf887806', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: '79ab736373b4f7788c9a26752218ae6d', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: 'd98b5d90d6b51b69ba332d0ab39a36b8', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: '87b0290f4c31bf3e6240e98e65103659', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: '2f7e8f0bcad5a881f29dabd67b9bb058', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '6d5bcd59fcded32c5febf19dafa06e6c', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: 'c18a9c49a85a7d2e0652d139f92c8ffa', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: '832683276064d3571d0c8cc4cc0bf628', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: '3c942aae64829aeae9ecab44050fe1eb', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: 'ae2829cc18a99f1357f6aa93ddfebdc2', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '34e877d984e0bfb934190535265f0b4f', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 5 (chess/2/5/) ───
  ChessSkinMeta(
    id: '5',
    displayName: '皮肤 5',
    pieces: {
      'wK': FileRef(fileId: '65658614c08ea92765454ed543d64826', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: '6d5a1b27398005a152015b7db76499e6', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: '8691ff5e6c42415c640e8f2040b5fada', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '137d3f3eb5e3b528e1e02c609e7a277b', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: 'd6b6477c8aff5a1f843486735e2a76c5', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: '8f044832078da9804e3057d2249388a1', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '417d3b50c48c84629bd756fefdba2fb7', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: '5022e4d39c34ba374adc8f720d3f9fa8', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: 'b6e40d572ad59cb38742cdce99879e7f', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: '7ac48819e043a395aa88d17a61d438ed', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: '946fc646875077c790d6d9d161658b9e', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '7dcaab965fa3a1fc5ad5497550793b16', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 6 (chess/2/6/) ───
  ChessSkinMeta(
    id: '6',
    displayName: '皮肤 6',
    pieces: {
      'wK': FileRef(fileId: '10848d8d60e22949f7508e1afadb0fb2', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: '04748654d7dc1d6d329c17a1fd580506', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: 'a3cf6419600777d6e0fe41409d58c3f7', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '75b9009765a18e7fb6c2768946111f02', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: '36f78cf2843514326370334ab9c9d974', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: '61548c4e75214703be2c5bdd9cc21615', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '32d915121a8592fd95c7529c6de496d0', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: 'ec31bc62092e51322280fb589ad39fb5', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: '739b4c0f88db802fa85c96a3126b35e1', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: '62bad9ebcb1d2c3642f0a8e388570990', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: '3a945d379dee4808f252580ec521f423', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: 'ea9167d039156c04cf797dbdb2e33a84', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
  // ─── Skin 7 (chess/2/7/) ───
  ChessSkinMeta(
    id: '7',
    displayName: '皮肤 7',
    pieces: {
      'wK': FileRef(fileId: '3fcfbaa46486f8538bba932b00454496', fileName: '00_white_king.webp', sizeBytes: 10396, contentType: 'image/webp'),
      'wQ': FileRef(fileId: 'fdb14b47151497bf53d63dac0a417b0e', fileName: '01_white_queen.webp', sizeBytes: 10174, contentType: 'image/webp'),
      'wR': FileRef(fileId: 'f8fe9cb32fd4e18b315a38c908eb4254', fileName: '02_white_rook.webp', sizeBytes: 8132, contentType: 'image/webp'),
      'wB': FileRef(fileId: '79454b419251b9917c03311f95387068', fileName: '03_white_bishop.webp', sizeBytes: 9060, contentType: 'image/webp'),
      'wN': FileRef(fileId: 'ec2e34c067acb0aef9a38dc36222c251', fileName: '04_white_knight.webp', sizeBytes: 9926, contentType: 'image/webp'),
      'wp': FileRef(fileId: '09b2736d397e0f7e6ac117ab920b0a8e', fileName: '05_white_pawn.webp', sizeBytes: 7128, contentType: 'image/webp'),
      'bK': FileRef(fileId: '8ce8e412dd39bddb90626eff64b16c6c', fileName: '06_black_king.webp', sizeBytes: 9228, contentType: 'image/webp'),
      'bQ': FileRef(fileId: 'daafee46793cd9cd3a7d015bea5291bd', fileName: '07_black_queen.webp', sizeBytes: 9174, contentType: 'image/webp'),
      'bR': FileRef(fileId: 'eeb2f17bee669c1c5615f1f9ed85361f', fileName: '08_black_rook.webp', sizeBytes: 6948, contentType: 'image/webp'),
      'bB': FileRef(fileId: 'b112fedafdd790fa07a0d126525274fb', fileName: '09_black_bishop.webp', sizeBytes: 7992, contentType: 'image/webp'),
      'bN': FileRef(fileId: 'c9aaac2583c19d4686a43ba5e8fcca2d', fileName: '10_black_knight.webp', sizeBytes: 9058, contentType: 'image/webp'),
      'bp': FileRef(fileId: '4f5a96cda424b407e64ae30460c96990', fileName: '11_black_pawn.webp', sizeBytes: 6570, contentType: 'image/webp'),
    },
  ),
];