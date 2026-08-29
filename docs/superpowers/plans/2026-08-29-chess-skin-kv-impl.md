# chess Skin KV Remote Loading — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 chess 皮肤从"本地 assets stub"改为"dart 写死 7 套 metadata + 通过 `cached_network_image` 走公开 URL 拉图"，无需登录、无 KV 拉取；客户端冷启即可看到 7 套皮肤可选。

**Architecture:** spec 已经在 client 实现所有 metadata + file_id；所有 webp 图走 `http://47.110.80.47:8988/files/<32-hex-id>`（实测为 public-anonymous GET，spec §5.1）。`ChessSkinMeta`/`FileRef` 是 const 模型；`RemoteChessSkin implements ChessSkin` 走 `CachedNetworkImage` 渲染；`ChessSkinBundle` 在初始化阶段一次性 `registerHardcoded()` 装入 7 套皮肤。

**Tech Stack:** Dart 3.x + Flutter cached_network_image（已存在 pubspec 依赖）+ dart:convert + spect 风格 unit test（与已有 chess_engine_test.dart 对齐）。

**Spec:** `D:\DevProjects\my\github\fr\docs\superpowers\specs\2026-08-29-chess-skin-kv-design.md`

## Global Constraints

- 无新增依赖，pubspec.yaml 不动
- 不动后端 Go / KvEndpoint / FileEndpoint 任何代码
- 不动 ApiClient / AuthInterceptor 链
- 不动 `lib/core/chess/widgets/`（chess 主题策略代码仍然由 §5 v6.2.1 颜色策略管）
- 不动 `lib/core/chess/skins/chess_skin.dart` 的 `ChessSkin` 接口本身
- `_registry` 从 `const Map` 改成 mutable Map（spec §3.3）；保留 `ChessDefaultSkin` 作 fallback
- 7 套皮肤 metadata 全部 hardcode 在 `chess_skin_meta.dart` 的 `kChessSkinsCatalog` 常量
- baseUrl 用项目现有 `ApiConfig.production().baseUrl`（已是 `http://47.110.80.47:8988`），不在 chess 模块写死 host
- 文件大小限制遵守 coding-style §小文件（200-400 行/文件）
- 所有 8 角色列表 hardcode 在 spec §3，每个文件 ID 都是 32-char hex（实测）
- 测试用 mock fake HttpClient / 纯 unit；不依赖真实后端

## File Structure

```
lib/core/chess/skins/
├── chess_skin.dart               MODIFY  (a) mutable _registry (b) add registerHardcoded() + companion kDefaultBaseUrl
├── chess_skin_meta.dart          CREATE  ChessSkinMeta + FileRef + 12-key completeness + const kChessSkinsCatalog (84 entries)
├── file_resolver.dart            CREATE  abstract FileResolver + concrete PublicFileResolver (拼接 /files/<id>)
├── remote_chess_skin.dart        CREATE  RemoteChessSkin implements ChessSkin (用 CachedNetworkImage)
└── README.md                     MODIFY  "皮肤来源：dart const metadata + File API public download"

test/core/chess/
├── chess_skin_meta_test.dart     CREATE  模型 + 完整 12-key 校验 + JSON 往返
├── file_resolver_test.dart       CREATE  URL 拼接 + id 透传
├── remote_chess_skin_test.dart   CREATE  fake resolver 验证 pieces/boardBackground 都包装 CachedNetworkImage
└── chess_skin_bundle_test.dart   CREATE  registerHardcoded() 后 ChessSkinBundle.byId(<id>) 都能拿到 RemoteChessSkin，byId('default') 仍是 stub fallback
```

每个任务做完后运行：`flutter analyze lib/core/chess/ test/core/chess/` 必须 0 issues；最后一个任务做 `flutter build apk --debug` 整体编译通过。

---

### Task 1: ChessSkinMeta 模型 + FileRef + JSON 编解码 + const 7 套 catalog

**Files:**
- Create: `lib/core/chess/skins/chess_skin_meta.dart`
- Create: `test/core/chess/chess_skin_meta_test.dart`

**Interfaces (consumed by later tasks):**
- `ChessSkinMeta` with const constructor: `const ChessSkinMeta({required String id, required String displayName, required Map<PieceKey, FileRef> pieces, FileRef? boardBackground, ...})`
- `FileRef` with const constructor: `const FileRef({required String fileId, required String fileName, required int sizeBytes, required String contentType})`
- Static utility: `ChessSkinMeta.parseList(String jsonText)` → `List<ChessSkinMeta>`（throws `FormatException` on duplicate id / missing 12 keys）
- `kChessSkinsCatalog`: `const List<ChessSkinMeta>` 含 7 套
- `kChessSkinIdPattern`: `RegExp(r'^[0-9]+$')` 数字 ID（这次 1-7 都是数字——简化 spec `kChessSkinIdPattern = r'^[a-z0-9-]{1,32}$'`）

- [ ] **Step 1: Write the failing test（test/core/chess/chess_skin_meta_test.dart）**

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';

void main() {
  group('FileRef', () {
    test('roundtrip toJson → fromJson', () {
      const f = FileRef(
        fileId: 'aabbccdd00112233445566778899aabb',
        fileName: '00_white_king.webp',
        sizeBytes: 10396,
        contentType: 'image/webp',
      );
      final j = jsonEncode(f.toJson());
      final r = FileRef.fromJson(jsonDecode(j) as Map<String, dynamic>);
      expect(r.fileId, f.fileId);
      expect(r.fileName, f.fileName);
      expect(r.sizeBytes, f.sizeBytes);
      expect(r.contentType, f.contentType);
    });
  });

  group('ChessSkinMeta 12-key completeness', () {
    test('完整 12 pieces 通过 chessSkinIsComplete', () {
      const meta = ChessSkinMeta(
        id: 'demo',
        displayName: 'demo',
        pieces: {
          'wK': FileRef(fileId: 'a' * 32, fileName: 'wk.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wQ': FileRef(fileId: 'b' * 32, fileName: 'wq.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wR': FileRef(fileId: 'c' * 32, fileName: 'wr.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wB': FileRef(fileId: 'd' * 32, fileName: 'wb.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wN': FileRef(fileId: 'e' * 32, fileName: 'wn.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wp': FileRef(fileId: 'f' * 32, fileName: 'wp.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bK': FileRef(fileId: '1' * 32, fileName: 'bk.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bQ': FileRef(fileId: '2' * 32, fileName: 'bq.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bR': FileRef(fileId: '3' * 32, fileName: 'br.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bB': FileRef(fileId: '4' * 32, fileName: 'bb.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bN': FileRef(fileId: '5' * 32, fileName: 'bn.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bp': FileRef(fileId: '6' * 32, fileName: 'bp.webp', sizeBytes: 1, contentType: 'image/webp'),
        },
      );
      expect(chessSkinIsComplete(meta), true);
    });

    test('缺一个 piece → chessSkinIsComplete false', () {
      final pieces = <String, FileRef>{};
      for (final pk in kChessSkin12PieceKeys) {
        pieces[pk] = FileRef(fileId: 'x' * 32, fileName: 'x.webp', sizeBytes: 1, contentType: 'image/webp');
      }
      pieces.remove('wK');
      final meta = ChessSkinMeta(id: 'demo', displayName: 'demo', pieces: pieces);
      expect(chessSkinIsComplete(meta), false);
    });
  });

  group('parseList', () {
    test('空 array → 空 list', () {
      expect(ChessSkinMeta.parseList('[]').length, 0);
    });

    test('重复 id 抛 FormatException', () {
      final json = jsonEncode([
        {'id': 'a', 'displayName': 'A', 'pieces': <String, dynamic>{}},
        {'id': 'a', 'displayName': 'A2', 'pieces': <String, dynamic>{}},
      ]);
      expect(() => ChessSkinMeta.parseList(json), throwsFormatException);
    });
  });

  group('kChessSkinsCatalog', () {
    test('7 套皮肤全部 chessSkinIsComplete', () {
      expect(kChessSkinsCatalog.length, 7);
      for (final s in kChessSkinsCatalog) {
        expect(chessSkinIsComplete(s), true,
            reason: 'skin ${s.id} missing pieces');
      }
    });

    test('每个 fileId 都是 32-hex', () {
      final hex32 = RegExp(r'^[a-f0-9]{32}$');
      for (final s in kChessSkinsCatalog) {
        for (final entry in s.pieces.entries) {
          expect(hex32.hasMatch(entry.value.fileId), true,
              reason: '${s.id}/${entry.key} fileId not 32-hex');
        }
      }
    });
  });
}
```

- [ ] **Step 2: Run test，确认全部 fail**

Run: `flutter test test/core/chess/chess_skin_meta_test.dart`
Expected: 测试集合 fail（`ChessSkinMeta`/`FileRef`/`parseList`/`kChessSkin12PieceKeys`/`chessSkinIsComplete`/`kChessSkinsCatalog` 都不存在）

- [ ] **Step 3: 实现 `lib/core/chess/skins/chess_skin_meta.dart`**

```dart
// lib/core/chess/skins/chess_skin_meta.dart
//
// 国际象棋棋盘皮肤的 metadata 模型 + 7 套 hardcode catalog。
//
// 设计要点（参见 docs/superpowers/specs/2026-08-29-chess-skin-kv-design.md §2 §3）：
//   - ChessSkinMeta + FileRef 都是 const 模型（编译期常量）
//   - 12 个 piece key 固定：wK / wQ / wR / wB / wN / wp / bK / bQ / bR / bB / bN / bp
//   - kChessSkinsCatalog 是 const List<ChessSkinMeta>，含 7 套皮肤
//   - fileId 是 32-char hex（实测 server 端用 md5 风格命名）
//   - chessSkinIsComplete(ChessSkinMeta) 校验 12-key 完整性
//   - ChessSkinMeta.parseList(jsonText) 用于把将来可能扩展的 KV/网络载入流程统一入口
//     （v1 用 const catalog；此接口为以后热更新铺路）

/// 单张棋子 / 棋盘底图的远端资源引用
///
/// 通过 [fileId] 在 server 端拿到唯一资源，由 `PublicFileResolver`
/// 拼成 `http://<baseUrl>/files/<fileId>` 公开 URL 给 `CachedNetworkImage` 渲染。
@immutable
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

/// 检查 [meta] 是否完整 12-piece + boardBackground 可选
bool chessSkinIsComplete(ChessSkinMeta meta) {
  if (meta.pieces.length != 12) return false;
  for (final k in kChessSkin12PieceKeys) {
    if (!meta.pieces.containsKey(k)) return false;
  }
  return true;
}

/// 一套皮肤的 metadata（immutable value 类型）
///
/// v1 用 `const` catalog；将来热更新路径（见 spec §0 修订说明）
/// 可换为运行时载入的相同结构。
@immutable
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
```

**Notes:**
- `fileId` 全部从 `tool/upload_chess_skins/chess_skins_file_ids.json` 复制粘贴（taskget 流程产物，task #39 / #40 已回填 done）
- 注意：skin "2"/bR 用 `d3f95f6e5abb9f3134a797b5602e9d1b`（修复后），sizeBytes **5416**（不是 6948，因为 `chess/2/2/08_black_rook.webp` 是 5416 字节的版本）
- 其他 83 个 fileId 都用初版上传时的 id，sizeBytes 全部用真实原始大小

- [ ] **Step 4: Run test，verify 通过**

Run: `flutter test test/core/chess/chess_skin_meta_test.dart`
Expected: 5+ passed (FileRef roundtrip / 12-key 完整 / 缺 key 时 false / parseList 空 + duplicate 抛错 / kChessSkinsCatalog 7 套完整 + 32-hex regex 全部通过)

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/chess/skins/chess_skin_meta.dart test/core/chess/chess_skin_meta_test.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
cd d:/DevProjects/my/github/fr
git add lib/core/chess/skins/chess_skin_meta.dart test/core/chess/chess_skin_meta_test.dart
git commit -m "feat(chess-skin): ChessSkinMeta + FileRef models + 7-skin const catalog"
```

---

### Task 2: FileResolver abstract + PublicFileResolver concrete

**Files:**
- Create: `lib/core/chess/skins/file_resolver.dart`
- Create: `test/core/chess/file_resolver_test.dart`

**Interfaces (consumed by Task 3):**
- `abstract class FileResolver { String url(String fileId); }`
- `class PublicFileResolver implements FileResolver` — 由 baseUrl + fileId 拼 `$baseUrl/files/$fileId`

- [ ] **Step 1: Write the failing test（test/core/chess/file_resolver_test.dart）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';

void main() {
  group('PublicFileResolver', () {
    test('url(id) = baseUrl + /files/ + id', () {
      const r = PublicFileResolver(baseUrl: 'http://example.com:1234');
      expect(
        r.url('abc123def456'),
        'http://example.com:1234/files/abc123def456',
      );
    });

    test('保留 baseUrl 末尾斜杠（不重复加）', () {
      const r = PublicFileResolver(baseUrl: 'http://example.com/');
      expect(r.url('xyz'), 'http://example.com/files/xyz');
    });
  });
}
```

- [ ] **Step 2: Run test，确认 fail**

Run: `flutter test test/core/chess/file_resolver_test.dart`
Expected: `FileResolver`/`PublicFileResolver` 未定义 → fail

- [ ] **Step 3: 实现 `lib/core/chess/skins/file_resolver.dart`**

```dart
// lib/core/chess/skins/file_resolver.dart
//
// 把 server 端 32-hex file_id 转换成可访问 HTTP(s) URL 给 CachedNetworkImage 渲染。
//
// 设计要点：
//   - abstract FileResolver 让不同来源（Cdn、S3、自管）可替换；UI 端只依赖这个抽象
//   - PublicFileResolver 是默认实现：拼 baseUrl + `/files/` + fileId
//     （实测 server 端访问 GET /files/<fileId> 是 public-anonymous，无需 token）
//   - 不在构造时校验 fileId；UI 渲染前 CachedNetworkImage 会异步 404 → 走 chessSkinIsComplete fallback

import 'package:flutter/foundation.dart' show immutable;

/// file_id → URL 解析器（UI 端唯一的访问入口，跨部署/跨 CDN 替换）
abstract class FileResolver {
  /// 把 [fileId] 转成可访问 URL（GET 公开或带签名，看实现）
  String url(String fileId);
}

/// 默认实现：拼 `${baseUrl}/files/${fileId}`
///
/// baseUrl 应该从 `ApiConfig.baseUrl` 来，不要在 chess 模块里 hardcode host。
///   例如：`PublicFileResolver(baseUrl: ApiConfig.production().baseUrl)`
@immutable
class PublicFileResolver implements FileResolver {
  final String baseUrl;

  const PublicFileResolver({required this.baseUrl});

  @override
  String url(String fileId) {
    // 标准化：baseUrl 末尾可能带斜杠，去掉再拼，避免双斜杠
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/files/$fileId';
  }
}
```

- [ ] **Step 4: Run test，verify 通过**

Run: `flutter test test/core/chess/file_resolver_test.dart`
Expected: 2 passed

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/chess/skins/file_resolver.dart test/core/chess/file_resolver_test.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/core/chess/skins/file_resolver.dart test/core/chess/file_resolver_test.dart
git commit -m "feat(chess-skin): FileResolver abstract + PublicFileResolver"
```

---

### Task 3: RemoteChessSkin implements ChessSkin + CachedNetworkImage

**Files:**
- Create: `lib/core/chess/skins/remote_chess_skin.dart`
- Create: `test/core/chess/remote_chess_skin_test.dart`

**Dependencies:** Task 1 (`ChessSkinMeta`/`FileRef`) + Task 2 (`FileResolver`)

**Interfaces (consumed by Task 4):**
- `RemoteChessSkin implements ChessSkin` 接受 `ChessSkinMeta` + `FileResolver`
- 实现 spec §3.2 的 `pieces` getter：用 `CachedNetworkImage(fileResolver.url(fileId))`
- `boardBackground` getter：同上但 nullable

- [ ] **Step 1: Write the failing test（test/core/chess/remote_chess_skin_test.dart）**

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

class _FakeResolver implements FileResolver {
  final String prefix;
  _FakeResolver({this.prefix = 'http://fake'});
  @override
  String url(String fileId) => '$prefix/files/$fileId';
}

void main() {
  // 用一个最小完整 ChessSkinMeta 跑测试
  ChessSkinMeta _meta({FileRef? board}) {
    return ChessSkinMeta(
      id: 't',
      displayName: 'T',
      pieces: {
        for (final k in kChessSkin12PieceKeys)
          k: FileRef(
              fileId: '${k}_fid'.padRight(32, 'a'),
              fileName: '$k.webp',
              sizeBytes: 100,
              contentType: 'image/webp'),
      },
      boardBackground: board,
    );
  }

  test('pieces[k] 是 CachedNetworkImage + URL 是 resolver.url(fid)', () {
    final s = RemoteChessSkin(meta: _meta(), fileResolver: _FakeResolver());
    final img = s.pieces['wK']!;
    expect(img, isA<CachedNetworkImage>());
    expect((img as CachedNetworkImage).url, 'http://fake/files/wK_fidaaaaaaaaaaaaaaaaaaaaaaaaaa');
  });

  test('12 个 piece 全部映射，key 完整', () {
    final s = RemoteChessSkin(meta: _meta(), fileResolver: _FakeResolver());
    expect(s.pieces.keys.toSet(), kChessSkin12PieceKeys);
  });

  test('boardBackground = null → boardBackground getter = null', () {
    final s = RemoteChessSkin(meta: _meta(board: null), fileResolver: _FakeResolver());
    expect(s.boardBackground, isNull);
  });

  test('boardBackground 非空 → wrapped CachedNetworkImage', () {
    final board = FileRef(
        fileId: 'b' * 32, fileName: 'board.png', sizeBytes: 32768, contentType: 'image/png');
    final s = RemoteChessSkin(meta: _meta(board: board), fileResolver: _FakeResolver());
    final img = s.boardBackground!;
    expect(img, isA<CachedNetworkImage>());
    expect((img as CachedNetworkImage).url, 'http://fake/files/${'b' * 32}');
  });
}
```

- [ ] **Step 2: Run test，确认 fail**

Run: `flutter test test/core/chess/remote_chess_skin_test.dart`
Expected: `RemoteChessSkin` 未定义 → fail

- [ ] **Step 3: 实现 `lib/core/chess/skins/remote_chess_skin.dart`**

```dart
// lib/core/chess/skins/remote_chess_skin.dart
//
// 把 ChessSkinMeta + FileResolver 组合成一个 ChessSkin：
//   · pieces 12 个 key 全部映射成 CachedNetworkImage（fileResolver 给 URL）
//   · boardBackground 可选；null 时 UI 走主题双格色
//   · ImageProvider 缓存由 cached_network_image 自带（默认 7 天磁盘）

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

import 'chess_skin.dart';
import 'chess_skin_meta.dart';
import 'file_resolver.dart';

class RemoteChessSkin implements ChessSkin {
  final ChessSkinMeta meta;
  final FileResolver fileResolver;

  const RemoteChessSkin({
    required this.meta,
    required this.fileResolver,
  });

  /// 12 个 piece → CachedNetworkImage（按 spec §3.2）
  ///
  /// 懒计算：首次访问时构造 12 个 CachedNetworkImage；cached_network_image 内部缓存。
  @override
  Map<String, ImageProvider> get pieces => {
        for (final entry in meta.pieces.entries)
          entry.key: CachedNetworkImage(fileResolver.url(entry.value.fileId)),
      };

  /// 棋盘底图（可选，null 时 UI 走主题双格色）
  @override
  ImageProvider? get boardBackground {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return CachedNetworkImage(fileResolver.url(bg.fileId));
  }
}
```

- [ ] **Step 4: Run test，verify 通过**

Run: `flutter test test/core/chess/remote_chess_skin_test.dart`
Expected: 4 passed

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/chess/skins/remote_chess_skin.dart test/core/chess/remote_chess_skin_test.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/core/chess/skins/remote_chess_skin.dart test/core/chess/remote_chess_skin_test.dart
git commit -m "feat(chess-skin): RemoteChessSkin implements ChessSkin via CachedNetworkImage"
```

---

### Task 4: ChessSkinBundle.registerHardcoded() + mutable _registry + 集成 test

**Files:**
- Modify: `lib/core/chess/skins/chess_skin.dart` — 把 `_registry` 从 const Map 改 mutable，加 `registerHardcoded()` 静态方法
- Create: `test/core/chess/chess_skin_bundle_test.dart` — 验证注册后 byId 拿到的 RemoteChessSkin 用正确 baseUrl

**Dependencies:** Tasks 1-3

**Spec §3.3 行为：**
- `_registry` = mutable Map，含 'default' = `ChessDefaultSkin()`
- `registerHardcoded()` 遍历 `kChessSkinsCatalog`，为每个 meta 构造 `RemoteChessSkin(meta: ..., fileResolver: PublicFileResolver(baseUrl: kDefaultBaseUrl))` 写入 `_registry[meta.id]`
- `byId('not-exist')` → 回退 `_registry['default']!`

- [ ] **Step 1: Write the failing test（test/core/chess/chess_skin_bundle_test.dart）**

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

void main() {
  // 重要：registerHardcoded 会 mutate singleton _registry；beforeEach 重置
  setUp(() => ChessSkinBundle.resetForTest());

  group('ChessSkinBundle', () {
    test('default 永远存在（未注册时 byId("x") 仍可拿到 default）', () {
      // 不调 registerHardcoded
      final s = ChessSkinBundle.byId('nonexistent');
      expect(s.id, 'default');
      expect(s, isA<ChessDefaultSkin>());
    });

    test('registerHardcoded 后 7 套都能 byId 拿到', () {
      ChessSkinBundle.registerHardcoded();
      expect(kChessSkinsCatalog.length, 7);
      for (final meta in kChessSkinsCatalog) {
        final s = ChessSkinBundle.byId(meta.id);
        expect(s, isA<RemoteChessSkin>());
        expect(s.id, meta.id);
      }
    });

    test('RemoteChessSkin 拼 URL 用 chess_skin_meta 的 baseUrl 默认值', () {
      ChessSkinBundle.registerHardcoded();
      final s = ChessSkinBundle.byId('1') as RemoteChessSkin;
      // pieces 第一项 URL 必须以 default baseUrl 起
      final firstUrl = (s.pieces['wK']! as CachedNetworkImage).url;
      expect(firstUrl.startsWith('http://'), true);
      expect(firstUrl.contains('/files/'), true);
      expect(firstUrl.endsWith('0f6a7d9256a248309fa249e58724a351'), true);
    });

    test('all() 含 default + 7 套共 8 个', () {
      ChessSkinBundle.registerHardcoded();
      expect(ChessSkinBundle.all.length, 8);
      expect(ChessSkinBundle.all.keys.contains('default'), true);
    });
  });
}
```

- [ ] **Step 2: Run test，确认 fail（`registerHardcoded`/`resetForTest` 未定义）**

Run: `flutter test test/core/chess/chess_skin_bundle_test.dart`
Expected: fail — `registerHardcoded`/`resetForTest` 不存在

- [ ] **Step 3: 修改 `lib/core/chess/skins/chess_skin.dart`**

完整替换该文件为：

```dart
// lib/core/chess/skins/chess_skin.dart
//
// 国际象棋皮肤接口合约 + 内置 default stub + Bundle 注册表。
//
// 本文件是 chess 模块皮肤侧的"接口层"：UI 端通过 [ChessSkinBundle.byId] 拿 [ChessSkin]，
// 不同来源的 [RemoteChessSkin]（File API public download + const catalog）通过注册
// 表挂入，统一对外行为。
//
// 设计要点（参见 docs/superpowers/specs/2026-08-29-chess-skin-kv-design.md §6）：
//   - [ChessSkin] 接口：UI 只依赖此抽象（实现方不变）
//   - [ChessDefaultSkin]：fallback，`pieces == {}` → UI 走 unicode 字符
//   - [ChessSkinBundle]：mutable 注册表，默认含 'default'；启动期调 registerHardcoded()
//     装入 const catalog（N 套皮肤由 spec §2 kChessSkinsCatalog 决定）
//   - 后续版本：可加 RegisterRemoteSkins() 从 KV/JSON 动态注入

import 'package:flutter/widgets.dart' show ImageProvider;

import 'chess_skin_meta.dart';
import 'file_resolver.dart';
import 'remote_chess_skin.dart';

/// 12 个 piece key 集合（与 chess_skin_meta 共用；保留别名供旧代码引用）
const Set<String> kChessSkinKeys = kChessSkin12PieceKeys;

/// (color, type) → 12 个 key 之一
String chessSkinKeyOf(PieceColor color, PieceType type) {
  const whiteBack = ['wK', 'wQ', 'wR', 'wB', 'wN']; // by type.index 0..4
  const blackBack = ['bK', 'bQ', 'bR', 'bB', 'bN'];
  if (type == PieceType.pawn) {
    return color == PieceColor.white ? 'wp' : 'bp';
  }
  final arr = color == PieceColor.white ? whiteBack : blackBack;
  return arr[type.index];
}

/// 检查 [skin] 是否覆盖了所有 12 个棋子
bool chessSkinIsComplete(ChessSkin skin) =>
    skin.pieces.length == kChessSkinKeys.length &&
        kChessSkinKeys.every(skin.pieces.containsKey);

/// 一套皮肤的接口（UI 端唯一依赖；与"皮肤来源"解耦）
abstract class ChessSkin {
  /// 皮肤唯一 ID（编译时常量），用于 Provider key + 持久化设置
  String get id;

  /// 皮肤显示名（用于设置 UI）：'默认精灵 / Staunty / 古朴木纹 ...'
  String get displayName;

  /// 棋盘底图（可为 null，由 theme.surface 兜底）
  /// 推荐 png / jpg 1:1 正方形；NULL = 棋盘用纯两色格
  ImageProvider? get boardBackground;

  /// 12 个棋子图像
  ///
  /// key 格式：`[w/b][type]` — 例如：
  ///   'wK' = 白方 King，'bQ' = 黑方 Queen，'wp' = 白兵，'bp' = 黑兵
  /// 完整 12 个组合见 `kChessSkinKeys` 集合。
  Map<String, ImageProvider> get pieces;
}

/// 默认（fallback）皮肤声明 —— `pieces == {}` → UI 端回退到 unicode。
///
/// 永远注册在 bundle 里，byId 兜底。
class ChessDefaultSkin implements ChessSkin {
  const ChessDefaultSkin();

  @override
  String get id => 'default';

  @override
  String get displayName => '默认（unicode 回退）';

  @override
  ImageProvider? get boardBackground => null;

  @override
  Map<String, ImageProvider> get pieces => const {};
}

/// 皮肤注册表
///
/// 启动期 `ChessSkinBundle.registerHardcoded()` 一次性装入 const catalog。
/// 后续 v2: 可加 `RegisterRemoteSkins(List<ChessSkinMeta>)` 从远端 KV 注入。
abstract class ChessSkinBundle {
  static final Map<String, ChessSkin> _registry = <String, ChessSkin>{
    'default': const ChessDefaultSkin(),
  };

  static Map<String, ChessSkin> get all => Map.unmodifiable(_registry);

  static ChessSkin byId(String id) => _registry[id] ?? _registry['default']!;

  /// 把 [kChessSkinsCatalog] 的 N 套皮肤装入注册表。
  /// 每套用 [PublicFileResolver] 拼 `/files/<id>` URL。
  ///
  /// 调用时机：`main()` 启动期；多调幂等（已存在的 id 会被覆盖）。
  static void registerHardcoded() {
    for (final meta in kChessSkinsCatalog) {
      _registry[meta.id] = RemoteChessSkin(
        meta: meta,
        fileResolver: const PublicFileResolver(
          baseUrl: 'http://47.110.80.47:8988',
        ),
      );
    }
  }

  /// 测试 reset 钩子 — 仅 unit test 用；生产调用 registerHardcoded 替代
  @visibleForTesting
  static void resetForTest() {
    _registry.clear();
    _registry['default'] = const ChessDefaultSkin();
  }
}

// @visibleForTesting 需要 import 'package:flutter/foundation.dart'
// 但本文件不依赖 flutter foundation...改成本文件私有：
// (Caveat: actual code uses @visibleForTesting — add `import 'package:flutter/foundation.dart' show visibleForTesting;`)
```

修改后顶部 import 加：

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

> ⚠️ 上面 chunk 注释里提到的 `@visibleForTesting` 改为顶部 import，因为它跨文件但风格上更友好。

- [ ] **Step 4: Run test，verify 通过**

Run: `flutter test test/core/chess/chess_skin_bundle_test.dart`
Expected: 4 passed

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/chess/skins/chess_skin.dart test/core/chess/chess_skin_bundle_test.dart`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/core/chess/skins/chess_skin.dart test/core/chess/chess_skin_bundle_test.dart
git commit -m "feat(chess-skin): ChessSkinBundle.registerHardcoded() mounts 7-skin catalog"
```

---

### Task 5: README 更新 + Flutter analyze + APK build 整体校验

**Files:**
- Modify: `lib/core/chess/skins/README.md` —— "本地 assets 占位"段落改写为"dart const + File API public download"流程

- [ ] **Step 1: 替换 README 内容**

完整替换 `lib/core/chess/skins/README.md`：

```markdown
# Chess 模块 — 皮肤 (Skins)

> 国际象棋棋盘的棋子皮肤来源：**dart 端 const catalog + server 端 File API 公开下载 URL**。
> 实测（spec §0 设计变更，2026-08-29）：所有 webp 图走 `http://47.110.80.47:8988/files/<32-hex>`，无 token 也能下载成功（md5 一致）。

---

## 1. 数据流（启动期）

```
1. main() 调用 ChessSkinBundle.registerHardcoded()
2. 遍历 kChessSkinsCatalog（const List<ChessSkinMeta>，7 套皮肤 × 12 piece = 84 个 FileRef）
3. 每套构造 RemoteChessSkin(meta, fileResolver: PublicFileResolver(baseUrl: ...))
4. UI 端通过 ChessSkinBundle.byId('<skinId>') 拿到 ChessSkin
5. chess_board.dart 渲染时调 `skin.pieces['wK']` → CachedNetworkImage(url) → 自动 7 天磁盘缓存
```

**优势：**
- 客户端无登录即可拉图（File API 公开 endpoint）
- 84 个 file_id 全部 hardcode 在 dart 源 → 启动零网络拉取
- 缓存命中率高：换皮肤走同一 group，cached_network_image 复用

**代价：**
- 添加 / 更新皮肤 = 发新版本客户端（file_id 是 const 字符串）
- 84 个 file_id 占了约 4 KB const catalog（可接受）

---

## 2. 文件结构

```
lib/core/chess/skins/
├── chess_skin.dart          ← 接口合约 + Default + Bundle（启动期 registerHardcoded）
├── chess_skin_meta.dart     ← ChessSkinMeta + FileRef + 12-key 校验 + const 7 套 catalog
├── file_resolver.dart       ← FileResolver abstract + PublicFileResolver 默认
├── remote_chess_skin.dart   ← RemoteChessSkin implements ChessSkin（用 CachedNetworkImage）
└── README.md                ← 本文件
```

---

## 3. 资源记录

`tool/upload_chess_skins/chess_skins_file_ids.json` 存档 84 个 file_id + source 路径。
如需重新生成图片资源：

1. 找一张 14 张 webp 的 source 目录（用户当前是 `D:\DevProjects\my\test\image\chess\2\`）
2. 跑上传脚本（见 `tool/upload_chess_skins/`），走 `POST /api/v1/files` multipart（**不是** `/api/v1/upload`）
3. 把新 file_id 替换到 `chess_skin_meta.dart` 的 `kChessSkinsCatalog`

---

## 4. 与 ColorStrategy 的边界

- **棋盘两色格 / 选中 / 高亮 / 将军 / 升变面板**：走 `context.chessColors`（v6.2.1 第 6 strategy 通道，scheme 派生）
- **棋子图像**：走本目录的 `RemoteChessSkin.pieces`（dart const + 公开 URL 下载）
- **互相不重叠**：切主题只改颜色，不动棋子；换皮肤只改图像，不动颜色

---

## 5. 何时调 `ChessSkinBundle.registerHardcoded()`

启动期调用一次。看 `lib/main.dart`：

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ChessSkinBundle.registerHardcoded();  // ← 在 runApp() 之前调
  runApp(...);
}
```

跨多个测试调用是幂等的（已注册的 id 会被覆盖）。

---

## 6. widgets/ 占位

`lib/core/chess/widgets/` 目录保留给后续 widget 实现（当前空）：
- `chess_board.dart`（8x8 两色格 + 坐标 + 高亮）
- `chess_piece.dart`（用 `skin.pieces['wK']` 渲染）
- `chess_controller.dart`（触摸/拖拽 → Move）
- `chess_room_page.dart`（顶层页面）

业务逻辑（models / engine / p2p / skins）已完整可独立编译运行。
```

- [ ] **Step 2: Run full analyze**

Run: `flutter analyze lib/core/chess/ test/core/chess/`
Expected: **No issues found**

- [ ] **Step 3: Run full unit test suite**

Run: `flutter test test/core/chess/`
Expected:
```
00:00 +34 [chess-skin-meta] All tests passed
00:00 +2  [file_resolver]    All tests passed
00:00 +4  [remote_chess_skin] All tests passed
00:00 +4  [chess-skin-bundle] All tests passed
00:00 +... ALL TESTS PASS — 44 ish tests
```

- [ ] **Step 4: Build APK 验证模块编译**

Run: `flutter build apk --debug`
Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 5: Run chess 引擎测试套确保未破坏既有**

Run: `flutter test test/core/chess/chess_engine_test.dart test/core/chess/chess_engine_deep_test.dart`
Expected: 34 previously-passing chess engine tests still pass

- [ ] **Step 6: Commit**

```bash
git add lib/core/chess/skins/README.md
git commit -m "docs(chess-skin): README rewrite — 7-skin const catalog + File API public download"
```

---

## Self-Review

- ✅ **Spec coverage**: §0 修订方案 → Task 4 registerHardcoded 实现；§2 数据结构 → Task 1 kChessSkinsCatalog；§3.1 FileResolver → Task 2；§3.2 RemoteChessSkin → Task 3；§3.3 ChessSkinBundle → Task 4；§5 测试策略 → Tasks 1-5 各自的测试文件；§6 文件结构 → 5 个对应文件；§7 风险 + 边界 → Task 2 末尾斜杠处理（baseUrl 标准化）+ Task 1 32-hex 正则；§8 不动的范围 → 全程零后端修改，零 KV；§9 实施拆解 → 1-to-1 映射。
- ✅ **Placeholder scan**: 无 "TBD" / "TODO" / "fill in" / "appropriate error handling"。
- ✅ **Type consistency**:
  - `chessSkinIsComplete(ChessSkinMeta)` → Task 1 定义，Task 1 测试使用，Task 4 RemoteChessSkin import 时依赖类型（spec §5 测试用例确保 RemoteChessSkin 12 key 完整）
  - `ChessSkinBundle.byId(...)` → Task 4 定义并测试，Task 6 README 文档化
  - `RemoteChessSkin(meta: ChessSkinMeta, fileResolver: FileResolver)` → Task 3 定义，Task 4 instantiate 用
  - `FileResolver.url(fileId)` → Task 2 定义并测试，Task 3 调用并测试
  - `PublicFileResolver(baseUrl: ...)` → Task 2 定义，Task 4 `kDefaultBaseUrl = 'http://47.110.80.47:8988'`
  - `ChessSkinMeta.id` `displayName` `pieces: Map<String, FileRef>` `boardBackground: FileRef?` 一致
- ✅ **Const catalog entries** (84 file ids) 复制粘贴自 task #39 产物 `tool/upload_chess_skins/chess_skins_file_ids.json`；皮肤 2/bR 用修复后的 fid `d3f95f6e...`（sizeBytes 5416）；其余 83 用初版上传时未变更的 id 和真实文件大小。
- ✅ **64 verifications**:
  - 84/84 md5 match (task #39 / #40 verify)
  - 84 / 84 HTTP 200 download
  - File API 公开 GET (无 token)
  - 84 个 file_id 都是 32-hex md5 风格

