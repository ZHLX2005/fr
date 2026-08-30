// lib/core/chess/skins/chess_skin_localizer.dart
//
// 皮肤本地化器 —— 把远端皮肤资源下载到本地磁盘并持久化，之后用本地文件渲染。
//
// 目标目录：<app documents>/chess_skins/<skinId>/
//   - 12 张棋子：wK.webp / wQ.webp / ... / bp.webp
//   - 可选棋盘底图：boardBackground.webp|png|jpg
//   - done 标记文件：`.done`（全量下载完成的哨兵）
//
// 流程：
//   isCached(skinId) → true  → fromCache(skinId)（零网络）
//                   → false → download(meta)（HTTP 下载 + 写盘 + 返回 LocalChessSkin）
//
// 幂等 / 失败语义：
//   · download 期间任何一张失败（非 200 / socket error / 超时）→ 删除全部部分文件
//     并 rethrow —— 绝不留下半缓存皮肤（isCached 永远为 false）。
//   · 断点续传不做（全套 13 张，量小，全量下载即可）。
//   · 磁盘写失败（IOError）同样清空目录后 rethrow。
//
// 超时语义（真机踩坑：网络黑洞 —— 不可达但不立刻拒绝时 http.get 永不完成，
// loading 转圈不结束）：
//   · 每张资源的 HTTP GET 都有 [ChessSkinLocalizer.defaultTimeout] 超时；
//     超时抛 TimeoutException → 走既有失败路径（清目录 + rethrow → UI 错误态 + 重试）。
//     绝不允许"挂着不完成"的未来。
//
// Web 平台：dart:io 不可用 → [isCached] 返回 false、[fromCache]/[download]
// 抛 [StateError]（调用方应预先用 [ChessSkinLocalizer.isSupported] 判断）。
//
// 测试注入：默认用 `getApplicationDocumentsDirectory()`（path_provider）；
// 测试可传 [dirProvider] 覆盖为临时目录，避免依赖 path_provider mock。
//
// 静态判存（Fix B）：[cachedPieceFile] / [ensureBaseDirInit] /
// [setBaseDirForTest] —— 供 RemoteChessSkin"本地文件优先渲染"同步查文件
// （`<documents>/chess_skins/<skinId>/<fileName>`），带 memo 防每帧 IO。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'chess_skin_meta.dart';
import 'file_resolver.dart';
import 'local_chess_skin.dart';

/// 皮肤本地化器 —— 下载皮肤资源到本地磁盘并持久化。
class ChessSkinLocalizer {
  /// 默认构造：用 path_provider 的 documents 目录 + 默认 http.Client。
  ///
  /// [metaById] 是 [isCached] / [fromCache] 解析 meta 的钩子：默认从
  /// `kChessSkinsCatalog` 按 id 查找；测试可注入自定义 meta（皮肤 id 不在 catalog）。
  ///
  /// [timeout] 每张资源 HTTP GET 的超时（默认 [defaultTimeout] 15s）。
  /// 网络黑洞（不可达但不拒绝）下 GET 永不完成 → 超时抛 TimeoutException
  /// 走失败路径；测试可注入短超时加速。
  ChessSkinLocalizer({
    required FileResolver resolver,
    http.Client? client,
    Future<Directory> Function()? dirProvider,
    ChessSkinMeta? Function(String id)? metaById,
    Duration? timeout,
  }) : _resolver = resolver,
       _client = client ?? http.Client(),
       _dirProvider = dirProvider ?? getApplicationDocumentsDirectory,
       _metaById = metaById ?? _catalogMetaById,
       _timeout = timeout ?? defaultTimeout;

  final FileResolver _resolver;
  final http.Client _client;
  final Future<Directory> Function() _dirProvider;
  final ChessSkinMeta? Function(String id) _metaById;

  /// 每张资源 HTTP GET 的默认超时。
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 每张资源 HTTP GET 的超时（构造注入；测试用短超时）。
  final Duration _timeout;

  /// 根目录名（`<documents>/chess_skins/`）。
  static const String kRootDirName = 'chess_skins';

  /// 全量下载完成的哨兵文件名。
  static const String kDoneMarker = '.done';

  /// Web 上 dart:io / FileImage 不可用 —— 返回 false。
  static bool get isSupported => !kIsWeb;

  // ─────────────────────────────────────────────────────────────
  // 静态同步判存（本地文件优先渲染 —— Fix B）
  //
  // RemoteChessSkin 每次 build 都会问"这个棋子本地有没有"，
  // 这里提供**同步**判存 + memo，避免每帧同步 IO。
  // ─────────────────────────────────────────────────────────────

  /// 静态解析的缓存根目录（`<documents>`；[ensureBaseDirInit] 一次性缓存）。
  ///
  /// null = 尚未初始化 / Web / path_provider 失败 —— 此时 [cachedPieceFile]
  /// 一律返回 null，渲染退化为纯网络行为（与旧版一致，绝不少图）。
  static Directory? _baseDir;

  /// (skinId, 文件名) → 存在性 memo（值可为 null = 已确认不存在）。
  ///
  /// 文件只会经 [download] 落盘 → download 成功后按 skinId 前缀清除即可，
  /// 无需全量失效。
  static final Map<String, File?> _cachedFileMemo = {};

  /// 异步初始化静态根目录（幂等；path_provider 失败静默保持 null）。
  ///
  /// 调用时机：`ChessSkinBundle.registerHardcoded()` /
  /// `fetchAndMergeSkins()` / [download] —— 保证之后 [cachedPieceFile]
  /// 的同步判存可用。
  static Future<void> ensureBaseDirInit() async {
    if (kIsWeb) return;
    if (_baseDir != null) return;
    try {
      _baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      // 插件不可用（早期启动 / 测试环境）→ 保持 null，判存退化为网络行为。
    }
  }

  /// 测试注入静态根目录（绕过 path_provider）；传 null = 复位。
  @visibleForTesting
  static void setBaseDirForTest(Directory? dir) {
    _baseDir = dir;
    _cachedFileMemo.clear();
  }

  /// 同步判存：`<documents>/chess_skins/<skinId>/<fileName>` 存在返回 [File]，
  /// 否则 null（带 memo，不产生每帧 IO）。
  ///
  /// [fileName] 是精确叶子名（棋子 `'wK.webp'`、棋盘底图
  /// `'boardBackground.webp'|'png'|'jpg'`）。根目录未知（[_baseDir] 为 null）
  /// 时恒返回 null —— 行为等同未下载，走网络。
  static File? cachedPieceFile(String skinId, String fileName) {
    if (kIsWeb) return null;
    final base = _baseDir;
    if (base == null) return null;
    final memoKey = '$skinId/$fileName';
    return _cachedFileMemo.putIfAbsent(memoKey, () {
      final f = File(
        '${base.path}${Platform.pathSeparator}$kRootDirName'
        '${Platform.pathSeparator}$skinId${Platform.pathSeparator}$fileName',
      );
      return f.existsSync() ? f : null;
    });
  }

  /// 按 [skinId] 前缀清掉判存 memo（[download] 落盘后调用，让新文件立即可见）。
  static void _invalidateMemo(String skinId) {
    _cachedFileMemo.removeWhere((k, _) => k.startsWith('$skinId/'));
  }

  /// 目标目录：`<documents>/chess_skins/<skinId>/`。
  Future<Directory> dirFor(String skinId) async {
    final root = await _dirProvider();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}$kRootDirName'
      '${Platform.pathSeparator}$skinId',
    );
    return dir;
  }

  /// 检查 [skinId] 是否已完整本地缓存（12 张棋子都在 + done 标记 + boardBackground 若声明）。
  ///
  /// Web 恒 false（不支持本地文件）。
  Future<bool> isCached(String skinId) async {
    if (!isSupported) return false;
    final dir = await dirFor(skinId);
    if (!dir.existsSync()) return false;
    final meta = _metaById(skinId);
    if (meta == null) return false;
    // 12 张棋子必须全部存在
    for (final key in kChessSkin12PieceKeys) {
      final piece = meta.pieces[key];
      if (piece == null) continue; // 防御：meta 缺 key 时跳过
      if (!File('${dir.path}${Platform.pathSeparator}$key.webp').existsSync()) {
        return false;
      }
    }
    // done 标记必须存在（下载完成哨兵）
    if (!File(
      '${dir.path}${Platform.pathSeparator}$kDoneMarker',
    ).existsSync()) {
      return false;
    }
    return true;
  }

  /// 从本地缓存构造 [LocalChessSkin]（不触发网络）。未缓存返回 null。
  ///
  /// 注意：`isCached == true` 是调用方判断（含 done 标记 / 12 棋子齐全）；
  /// 这里更宽松 —— 只要目录存在且 meta 可解析就构造（缺文件由
  /// LocalChessSkin 内部省略 → unicode 回退）。Web / 目录缺失返回 null。
  Future<LocalChessSkin?> fromCache(String skinId) async {
    if (!isSupported) return null;
    final dir = await dirFor(skinId);
    final meta = _metaById(skinId);
    if (meta == null) return null;
    return LocalChessSkin.tryCreate(meta: meta, dir: dir);
  }

  /// 缓存优先确保 [meta] 已本地化（"下载前先查缓存"，Fix）。
  ///
  /// 语义（设置页 / 对弈页点选皮肤时的默认路径）：
  ///   · `isCached(meta.id)` 命中（12 棋子 + done 齐全）→ `fromCache` 直接返回
  ///     —— **零网络、不删缓存**；
  ///   · 未命中 / `fromCache` 构造失败 → `download(meta)` 全量下载补齐。
  ///
  /// 与 [download] 的区别：`download` 无条件清目录重下（用于 KV 换图等强刷场景）；
  /// `ensureLocal` 尊重已有缓存 —— 已下载的皮肤再次选中时**绝不删除重下**，
  /// 也不触发 loading（调用方应在命中缓存时跳过 loading 态）。
  ///
  /// 失败语义与 [download] 一致（网络/IO 错误 → 清目录 + rethrow）。
  Future<LocalChessSkin> ensureLocal(ChessSkinMeta meta) async {
    if (await isCached(meta.id)) {
      final cached = await fromCache(meta.id);
      if (cached != null) return cached;
    }
    return download(meta);
  }

  /// 下载 [meta] 的全部资源到本地并返回 [LocalChessSkin]。
  ///
  /// 失败（网络不可达 / 非 200 / IO 错误）→ 删除部分文件 + rethrow，
  /// 由调用方决定重试或回退网络皮肤 / unicode。
  Future<LocalChessSkin> download(ChessSkinMeta meta) async {
    if (!isSupported) {
      throw StateError('ChessSkinLocalizer 不支持 Web（无 dart:io）');
    }
    // 静态判存根目录尽早可用（下载完成后 RemoteChessSkin 立即转本地文件渲染）。
    await ensureBaseDirInit();
    final dir = await dirFor(meta.id);
    // 目录可能残留上次失败的部分文件 → 先清空（幂等）。
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    try {
      // 1. 12 张棋子
      for (final entry in meta.pieces.entries) {
        await _downloadTo(entry.value, dir, '${entry.key}.webp');
      }
      // 2. 可选棋盘底图（扩展名由 contentType 推导）
      final bg = meta.boardBackground;
      if (bg != null) {
        await _downloadTo(bg, dir, LocalChessSkin.boardBackgroundFileName(bg));
      }
      // 3. 下载完成哨兵（先写内容后写哨兵：避免半缓存被误判为完成）
      await File(
        '${dir.path}${Platform.pathSeparator}$kDoneMarker',
      ).writeAsString('ok\n', flush: true);
    } catch (e) {
      // 任一步失败 → 清空整个目录，绝不留下半缓存皮肤。
      try {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // 清理失败不掩盖原始错误。
      }
      rethrow;
    }
    // 判存 memo 失效：本次落盘的文件对 cachedPieceFile 立即可见
    // （RemoteChessSkin 本地文件优先渲染随之生效，零网络）。
    _invalidateMemo(meta.id);
    final skin = LocalChessSkin.tryCreate(meta: meta, dir: dir);
    if (skin == null) {
      throw StateError('皮肤下载完成但无法构造本地皮肤: ${meta.id}');
    }
    return skin;
  }

  /// 下载单个 [FileRef] 写到 [dir]/[fileName]，校验 HTTP 200 后写盘。
  ///
  /// GET 带 [_timeout] 超时：网络黑洞（连接挂起不完成）→ TimeoutException
  /// 抛给上层（清目录 + 错误态），绝不挂死 UI。
  Future<void> _downloadTo(FileRef ref, Directory dir, String fileName) async {
    final url = _resolver.url(ref.fileId);
    final http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url)).timeout(_timeout);
    } on http.ClientException {
      rethrow;
    } on TimeoutException {
      throw TimeoutException('下载超时（${_timeout.inSeconds}s）: $url', _timeout);
    }
    if (resp.statusCode != 200) {
      throw HttpException('下载失败 ${resp.statusCode}: $url', uri: Uri.parse(url));
    }
    final target = File('${dir.path}${Platform.pathSeparator}$fileName');
    await target.writeAsBytes(resp.bodyBytes, flush: true);
  }

  /// 从 const catalog 按 id 找 [ChessSkinMeta]（默认 [isCached]/[fromCache] 用）。
  static ChessSkinMeta? _catalogMetaById(String skinId) {
    for (final meta in kChessSkinsCatalog) {
      if (meta.id == skinId) return meta;
    }
    return null;
  }
}
