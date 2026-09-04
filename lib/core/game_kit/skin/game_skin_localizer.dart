// lib/core/game_kit/skin/game_skin_localizer.dart
//
// Generic skin localizer — download → disk + memo invalidation.
// Extracted from lib/core/chess/skins/chess_skin_localizer.dart,
// parameterized by GameSkinSpec (cacheDirName, assetKeys, board file name).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/painting.dart' show FileImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'file_resolver.dart';
import 'game_skin_meta.dart';
import 'game_skin_spec.dart';
import 'local_game_skin.dart';

/// Generic 皮肤本地化器 —— 下载皮肤资源到本地磁盘并持久化.
class GameSkinLocalizer {
  GameSkinLocalizer({
    required this.spec,
    required FileResolver resolver,
    http.Client? client,
    Future<Directory> Function()? dirProvider,
    GameSkinMeta? Function(String id)? metaById,
    Duration? timeout,
  })  : _resolver = resolver,
       _client = client ?? http.Client(),
       _dirProvider = dirProvider ?? getApplicationDocumentsDirectory,
       _metaById = metaById,
       _timeout = timeout ?? defaultTimeout;

  final GameSkinSpec spec;
  final FileResolver _resolver;
  final http.Client _client;
  final Future<Directory> Function() _dirProvider;
  final GameSkinMeta? Function(String id)? _metaById;
  final Duration _timeout;

  static const Duration defaultTimeout = Duration(seconds: 15);

  static const String kCachedMetaFileName = '.skin-meta.json';
  static const String kDoneMarker = '.done';

  static bool get isSupported => !kIsWeb;

  // ── 静态同步判存（per-game 分区） ──

  static Directory? _baseDir;
  static String? _baseGameId;
  static String? _baseCacheDirName;

  static final Map<String, File?> _cachedFileMemo = {};
  static final Map<String, Map<String, String>?> _cachedIndexMemo = {};

  static Future<void> ensureBaseDirInitFor(GameSkinSpec spec) async {
    if (kIsWeb) return;
    if (_baseDir != null &&
        _baseGameId == spec.gameId &&
        _baseCacheDirName == spec.cacheDirName) {
      return;
    }
    if (_baseGameId != spec.gameId || _baseCacheDirName != spec.cacheDirName) {
      _cachedFileMemo.clear();
      _cachedIndexMemo.clear();
    }
    try {
      _baseDir = await getApplicationDocumentsDirectory();
      _baseGameId = spec.gameId;
      _baseCacheDirName = spec.cacheDirName;
    } catch (_) {}
  }

  /// chess 兼容入口（旧代码无 spec 参数，默认 chess）.
  static Future<void> ensureBaseDirInit() =>
      ensureBaseDirInitFor(kChessSkinSpec);

  @visibleForTesting
  static void setBaseDirForTest(Directory? dir, {GameSkinSpec? spec}) {
    _baseDir = dir;
    if (spec != null) {
      _baseGameId = spec.gameId;
      _baseCacheDirName = spec.cacheDirName;
    } else if (dir == null) {
      _baseGameId = null;
      _baseCacheDirName = null;
    }
    _cachedFileMemo.clear();
    _cachedIndexMemo.clear();
  }

  /// chess 兼容：无 spec 参数时默认按 chess 分区.
  static File? cachedPieceFile(
    String skinId,
    String fileName, {
    required String expectedFileId,
  }) {
    return cachedPieceFileFor(
      kChessSkinSpec,
      skinId,
      fileName,
      expectedFileId: expectedFileId,
    );
  }

  static File? cachedPieceFileFor(
    GameSkinSpec spec,
    String skinId,
    String fileName, {
    required String expectedFileId,
  }) {
    if (kIsWeb) return null;
    final base = _baseDir;
    if (base == null) return null;
    if (_baseGameId != spec.gameId || _baseCacheDirName != spec.cacheDirName) {
      return null;
    }
    final memoKey = '${spec.gameId}|$skinId|$expectedFileId|$fileName';
    final file = _cachedFileMemo.putIfAbsent(memoKey, () {
      final f = File(
        '${base.path}${Platform.pathSeparator}${spec.cacheDirName}'
        '${Platform.pathSeparator}$skinId${Platform.pathSeparator}$fileName',
      );
      return f.existsSync() ? f : null;
    });
    if (file == null) return null;
    final index = _readCachedIndexSyncFor(spec, skinId);
    if (index == null) return null;
    final pieceKey = _pieceKeyFromFileName(fileName);
    if (index[pieceKey] != expectedFileId) return null;
    return file;
  }

  static String _pieceKeyFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static Map<String, String>? _readCachedIndexSyncFor(
    GameSkinSpec spec,
    String skinId,
  ) {
    final key = '${spec.gameId}|$skinId';
    return _cachedIndexMemo.putIfAbsent(key, () {
      if (kIsWeb) return null;
      final base = _baseDir;
      if (base == null) return null;
      final f = File(
        '${base.path}${Platform.pathSeparator}${spec.cacheDirName}'
        '${Platform.pathSeparator}$skinId${Platform.pathSeparator}$kCachedMetaFileName',
      );
      if (!f.existsSync()) return null;
      try {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is! Map) return null;
        final out = <String, String>{};
        for (final entry in raw.entries) {
          final k = entry.key;
          final v = entry.value;
          if (k is String && v is String) out[k] = v;
        }
        return out.isEmpty ? null : out;
      } catch (_) {
        return null;
      }
    });
  }

  static void _invalidateMemoFor(GameSkinSpec spec, String skinId) {
    _cachedFileMemo.removeWhere((k, _) => k.startsWith('${spec.gameId}|$skinId|'));
    _cachedIndexMemo.remove('${spec.gameId}|$skinId');
  }

  Future<Directory> dirFor(String skinId) async {
    final root = await _dirProvider();
    return Directory(
      '${root.path}${Platform.pathSeparator}${spec.cacheDirName}'
      '${Platform.pathSeparator}$skinId',
    );
  }

  Future<bool> isCached(String skinId) async {
    if (!isSupported) return false;
    final dir = await dirFor(skinId);
    if (!dir.existsSync()) return false;
    final meta = _resolveMeta(skinId);
    if (meta == null) return false;
    final indexFile = File(
      '${dir.path}${Platform.pathSeparator}$kCachedMetaFileName',
    );
    if (!indexFile.existsSync()) return false;
    final Map<String, String> index;
    try {
      final raw = jsonDecode(indexFile.readAsStringSync());
      if (raw is! Map) return false;
      index = {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return false;
    }
    for (final key in spec.assetKeys) {
      final piece = meta.pieces[key];
      if (piece == null) continue;
      if (!File('${dir.path}${Platform.pathSeparator}$key.webp').existsSync()) {
        return false;
      }
      if (index[key] != piece.fileId) return false;
    }
    final bg = meta.boardBackground;
    if (bg != null) {
      final bgFile = File(
        '${dir.path}${Platform.pathSeparator}'
        '${LocalGameSkin.boardBackgroundFileName(bg)}',
      );
      if (!bgFile.existsSync()) return false;
      if (index['boardBackground'] != bg.fileId) return false;
    }
    if (!File('${dir.path}${Platform.pathSeparator}$kDoneMarker').existsSync()) {
      return false;
    }
    return true;
  }

  Future<LocalGameSkin?> fromCache(String skinId) async {
    if (!isSupported) return null;
    final dir = await dirFor(skinId);
    final meta = _resolveMeta(skinId);
    if (meta == null) return null;
    return LocalGameSkin.tryCreate(
      meta: meta,
      dir: dir,
      assetKeys: spec.assetKeys,
      boardBackgroundFileNameOf: LocalGameSkin.boardBackgroundFileName,
    );
  }

  Future<LocalGameSkin> ensureLocal(GameSkinMeta meta) async {
    if (await isCached(meta.id)) {
      final cached = await fromCache(meta.id);
      if (cached != null) return cached;
    }
    return download(meta);
  }

  Future<LocalGameSkin> download(GameSkinMeta meta) async {
    if (!isSupported) {
      throw StateError('GameSkinLocalizer 不支持 Web（无 dart:io）');
    }
    await ensureBaseDirInitFor(spec);
    final dir = await dirFor(meta.id);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    try {
      for (final entry in meta.pieces.entries) {
        await _downloadTo(entry.value, dir, '${entry.key}.webp');
      }
      final bg = meta.boardBackground;
      if (bg != null) {
        await _downloadTo(bg, dir, LocalGameSkin.boardBackgroundFileName(bg));
      }
      final index = <String, String>{
        for (final entry in meta.pieces.entries) entry.key: entry.value.fileId,
      };
      if (meta.boardBackground != null) {
        index['boardBackground'] = meta.boardBackground!.fileId;
      }
      index['version'] = meta.version.toString();
      await File(
        '${dir.path}${Platform.pathSeparator}$kCachedMetaFileName',
      ).writeAsString(jsonEncode(index), flush: true);
      await File(
        '${dir.path}${Platform.pathSeparator}$kDoneMarker',
      ).writeAsString('ok\n', flush: true);
    } catch (e) {
      try {
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
    _invalidateMemoFor(spec, meta.id);
    _evictImageCache(dir, [
      for (final key in meta.pieces.keys) '$key.webp',
      if (meta.boardBackground != null)
        LocalGameSkin.boardBackgroundFileName(meta.boardBackground!),
    ]);
    final skin = LocalGameSkin.tryCreate(
      meta: meta,
      dir: dir,
      assetKeys: spec.assetKeys,
      boardBackgroundFileNameOf: LocalGameSkin.boardBackgroundFileName,
    );
    if (skin == null) throw StateError('皮肤下载完成但无法构造本地皮肤: ${meta.id}');
    return skin;
  }

  static void _evictImageCache(Directory dir, List<String> fileNames) {
    if (kIsWeb) return;
    for (final name in fileNames) {
      try {
        FileImage(File('${dir.path}${Platform.pathSeparator}$name')).evict();
      } catch (_) {}
    }
  }

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

  GameSkinMeta? _resolveMeta(String skinId) {
    final fn = _metaById;
    if (fn != null) return fn(skinId);
    return null;
  }
}
