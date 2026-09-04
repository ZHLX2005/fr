// lib/core/gomoku/skins/gomoku_skin_localizer.dart
//
// 五子棋皮肤本地化器 —— <documents>/gomoku_skins/<skinId>/ 下的下载与判存。
//
// 对齐 ChessSkinLocalizer 的目录/哨兵/memo 设计，但抽出 game 维度的
// 参量化（rootDirName / stoneKeys / metaById）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show FileImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../chess/skins/chess_skin_localizer.dart' show ChessSkinLocalizer;
import '../../chess/skins/chess_skin_meta.dart' show FileRef;
import '../../chess/skins/file_resolver.dart';
import 'gomoku_skin_meta.dart';
import 'local_gomoku_skin.dart';

class GomokuSkinLocalizer {
  GomokuSkinLocalizer({
    required FileResolver resolver,
    http.Client? client,
    Future<Directory> Function()? dirProvider,
    GomokuSkinMeta? Function(String id)? metaById,
    Duration? timeout,
  })  : _resolver = resolver,
        _client = client ?? http.Client(),
        _dirProvider = dirProvider ?? getApplicationDocumentsDirectory,
        _metaById = metaById ?? _catalogMetaById,
        _timeout = timeout ?? ChessSkinLocalizer.defaultTimeout;

  final FileResolver _resolver;
  final http.Client _client;
  final Future<Directory> Function() _dirProvider;
  final GomokuSkinMeta? Function(String id) _metaById;
  final Duration _timeout;

  static const String kRootDirName = 'gomoku_skins';
  static const String kCachedMetaFileName = '.skin-meta.json';
  static const String kDoneMarker = '.done';

  static bool get isSupported => !kIsWeb;

  Future<Directory> dirFor(String skinId) async {
    final root = await _dirProvider();
    return Directory('${root.path}${Platform.pathSeparator}$kRootDirName${Platform.pathSeparator}$skinId');
  }

  Future<bool> isCached(String skinId) async {
    if (!isSupported) return false;
    final dir = await dirFor(skinId);
    if (!dir.existsSync()) return false;
    final meta = _metaById(skinId);
    if (meta == null) return false;
    final indexFile = File('${dir.path}${Platform.pathSeparator}$kCachedMetaFileName');
    if (!indexFile.existsSync()) return false;
    Map<String, String>? index;
    try {
      final raw = jsonDecode(indexFile.readAsStringSync());
      if (raw is! Map) return false;
      index = {for (final e in raw.entries) if (e.key is String && e.value is String) e.key as String: e.value as String};
    } catch (_) {
      return false;
    }
    for (final key in kGomokuStoneKeys) {
      final ref = meta.assets[key];
      if (ref == null) continue;
      if (!File('${dir.path}${Platform.pathSeparator}$key.webp').existsSync()) return false;
      if (index[key] != ref.fileId) return false;
    }
    final bg = meta.boardBackground;
    if (bg != null) {
      final bgFile = File('${dir.path}${Platform.pathSeparator}${LocalGomokuSkin.boardBackgroundFileName(bg)}');
      if (!bgFile.existsSync()) return false;
      if (index['board'] != bg.fileId) return false;
    }
    if (!File('${dir.path}${Platform.pathSeparator}$kDoneMarker').existsSync()) return false;
    return true;
  }

  Future<LocalGomokuSkin?> fromCache(String skinId) async {
    if (!isSupported) return null;
    final dir = await dirFor(skinId);
    final meta = _metaById(skinId);
    if (meta == null) return null;
    return LocalGomokuSkin.tryCreate(meta: meta, dir: dir);
  }

  Future<LocalGomokuSkin> ensureLocal(GomokuSkinMeta meta) async {
    if (await isCached(meta.id)) {
      final cached = await fromCache(meta.id);
      if (cached != null) return cached;
    }
    return download(meta);
  }

  Future<LocalGomokuSkin> download(GomokuSkinMeta meta) async {
    if (!isSupported) throw StateError('GomokuSkinLocalizer 不支持 Web');
    await ChessSkinLocalizer.ensureBaseDirInit();
    final dir = await dirFor(meta.id);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    try {
      for (final key in kGomokuStoneKeys) {
        final ref = meta.assets[key];
        if (ref == null) continue;
        await _downloadTo(ref, dir, '$key.webp');
      }
      final bg = meta.boardBackground;
      if (bg != null) {
        await _downloadTo(bg, dir, LocalGomokuSkin.boardBackgroundFileName(bg));
      }
      final index = <String, String>{
        for (final e in meta.assets.entries) e.key: e.value.fileId,
        'version': meta.version.toString(),
      };
      await File('${dir.path}${Platform.pathSeparator}$kCachedMetaFileName').writeAsString(jsonEncode(index), flush: true);
      await File('${dir.path}${Platform.pathSeparator}$kDoneMarker').writeAsString('ok\n', flush: true);
    } catch (e) {
      try {
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
    _evictImageCache(dir, [
      for (final k in kGomokuStoneKeys) '$k.webp',
      if (meta.boardBackground != null) LocalGomokuSkin.boardBackgroundFileName(meta.boardBackground!),
    ]);
    final skin = LocalGomokuSkin.tryCreate(meta: meta, dir: dir);
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
    if (resp.statusCode != 200) throw HttpException('下载失败 ${resp.statusCode}: $url', uri: Uri.parse(url));
    await File('${dir.path}${Platform.pathSeparator}$fileName').writeAsBytes(resp.bodyBytes, flush: true);
  }

  static GomokuSkinMeta? _catalogMetaById(String id) {
    for (final m in kGomokuSkinsCatalog) {
      if (m.id == id) return m;
    }
    return null;
  }
}
