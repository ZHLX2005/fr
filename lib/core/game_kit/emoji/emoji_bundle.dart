// lib/core/game_kit\emoji\emoji_bundle.dart
//
// Emoji bundle — 合并 common + game 作用域的表情：
//   · KV 拉取（PublicKvReader，group 190）
//   · 本地文件缓存（emojis/common/）
//   · forGame(gameId)：common 先、game 后（后者覆盖同 id）
//
// 无 unicode 兜底 —— 只展示管理后台上传并发布到 KV 的表情。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart' show ImageProvider, NetworkImage, FileImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../skin/file_resolver.dart';
import '../skin/game_skin_meta.dart' show FileRef;
import '../skin/public_kv_reader.dart';
import 'emoji_pack_meta.dart';

/// 单条表情的运行时视图（id + 远端文件引用）。
class EmojiEntry {
  /// 稳定的 emoji id（发送时走 EMOJI 的 emoji_id 参数）。
  final String id;

  /// 远端文件引用（必有 —— 没发布的 id 不在 bundle.entries 里）。
  final FileRef fileRef;

  /// 解析到的本地文件（若已缓存）。
  final File? localFile;

  const EmojiEntry({required this.id, required this.fileRef, this.localFile});

  /// 构造渲染用的 [ImageProvider]（本机文件优先，回退网络）。
  ImageProvider? imageProvider(FileResolver? resolver) {
    final lf = localFile;
    if (lf != null && lf.existsSync()) return FileImage(lf);
    final r = resolver;
    if (r == null) return null;
    return NetworkImage(r.url(fileRef.fileId));
  }
}

/// Emoji 运行时 bundle（按 [gameId] 合并 common + game 作用域）。
class EmojiBundle {
  /// 当前生效的条目（已按 common 先、game 后合并且去重；game 同 id 覆盖 common）。
  final List<EmojiEntry> entries;

  /// id → entry 索引。
  final Map<String, EmojiEntry> byId;

  /// 已加载的 pack meta（调试用）。
  final List<EmojiPackMeta> packs;

  const EmojiBundle({
    required this.entries,
    required this.byId,
    this.packs = const [],
  });

  /// 空 bundle（KV 未就绪 / 失败时的占位）。
  factory EmojiBundle.empty() =>
      const EmojiBundle(entries: [], byId: {});

  /// 指定 [gameId] 的 bundle（common + game 作用域，game 覆盖 common）。
  static Future<EmojiBundle> forGame(
    String gameId, {
    PublicKvReader? reader,
    FileResolver? fileResolver,
    String? defaultBaseUrl,
    http.Client? httpClient,
    Future<Directory> Function()? dirProvider,
  }) async {
    final baseUrl = defaultBaseUrl ?? 'http://47.110.80.47:8988';
    final kv = reader ?? PublicKvReader(baseUrl: baseUrl, groupId: 190);
    // fileResolver 由调用方持有；此处仅保留参数签名兼容。
    final _ = fileResolver;

    final scopes = <String>['common', gameId];
    final allPacks = <EmojiPackMeta>[];
    for (final scope in scopes) {
      final key = EmojiPackMeta.kvIndexKeyForScope(scope);
      final jsonText = await kv.readString(key);
      if (jsonText == null) continue;
      try {
        allPacks.addAll(EmojiPackMeta.parseList(jsonText));
      } catch (_) {
        continue;
      }
    }

    // id → FileRef（后者覆盖前者：game 覆盖 common）
    final merged = <String, FileRef>{};
    for (final pack in allPacks) {
      for (final entry in pack.emojis.entries) {
        merged[entry.key] = entry.value;
      }
    }

    final cacheById = <String, File>{};
    if (!kIsWeb) {
      for (final entry in merged.entries) {
        final f = await _resolveCachedFileFor(
          entry.key,
          entry.value,
          dirProvider: dirProvider,
        );
        if (f != null) cacheById[entry.key] = f;
      }
    }

    final entries = <EmojiEntry>[
      for (final id in merged.keys)
        EmojiEntry(
          id: id,
          fileRef: merged[id]!,
          localFile: cacheById[id],
        ),
    ];
    final byId = {for (final e in entries) e.id: e};

    return EmojiBundle(entries: entries, byId: byId, packs: allPacks);
  }

  /// 预取并缓存当前 bundle 的远端文件到本地（best-effort）。
  Future<void> prefetchToCache({
    http.Client? httpClient,
    Future<Directory> Function()? dirProvider,
    FileResolver? resolver,
    String? baseUrl,
  }) async {
    if (kIsWeb) return;
    final client = httpClient ?? http.Client();
    final shouldClose = httpClient == null;
    final r = resolver ??
        (baseUrl != null ? PublicFileResolver(baseUrl: baseUrl) : null);
    try {
      for (final e in entries) {
        if (e.localFile != null && e.localFile!.existsSync()) continue;
        final dir = await _emojiDirForId(e.id, dirProvider: dirProvider);
        if (dir == null) continue;
        try {
          await dir.create(recursive: true);
          final url = r?.url(e.fileRef.fileId) ??
              'http://47.110.80.47:8988/files/${e.fileRef.fileId}';
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode != 200) continue;
          final ext = _extForContentType(e.fileRef.contentType);
          final f = File('${dir.path}/${e.id}$ext');
          await f.writeAsBytes(resp.bodyBytes, flush: true);
          final idxFile = File('${dir.path}/.emoji-index.json');
          Map<String, dynamic> idx = {};
          if (idxFile.existsSync()) {
            try {
              idx = jsonDecode(idxFile.readAsStringSync())
                  as Map<String, dynamic>;
            } catch (_) {}
          }
          idx[e.id] = e.fileRef.fileId;
          await idxFile.writeAsString(jsonEncode(idx), flush: true);
        } catch (_) {}
      }
    } finally {
      if (shouldClose) client.close();
    }
  }

  static Future<Directory?> _emojiDirForId(
    String emojiId, {
    Future<Directory> Function()? dirProvider,
  }) async {
    try {
      final root = await (dirProvider != null
          ? dirProvider()
          : getApplicationDocumentsDirectory());
      return Directory('${root.path}${Platform.pathSeparator}emojis'
          '${Platform.pathSeparator}common');
    } catch (_) {
      return null;
    }
  }

  static String _extForContentType(String ct) {
    final lower = ct.toLowerCase();
    if (lower.contains('png')) return '.png';
    if (lower.contains('jpeg') || lower.contains('jpg')) return '.jpg';
    if (lower.contains('gif')) return '.gif';
    if (lower.contains('svg')) return '.svg';
    return '.webp';
  }

  /// 解析已缓存的文件（若存在且 fileId 匹配 .emoji-index.json）。
  static Future<File?> _resolveCachedFileFor(
    String emojiId,
    FileRef ref, {
    Future<Directory> Function()? dirProvider,
  }) async {
    if (kIsWeb) return null;
    try {
      final dir = await _emojiDirForId(emojiId, dirProvider: dirProvider);
      if (dir == null || !dir.existsSync()) return null;
      final idxFile = File('${dir.path}/.emoji-index.json');
      if (idxFile.existsSync()) {
        try {
          final raw = jsonDecode(idxFile.readAsStringSync());
          if (raw is Map && raw[emojiId] is String) {
            if (raw[emojiId] != ref.fileId) return null;
          }
        } catch (_) {}
      }
      for (final ext in ['.webp', '.png', '.jpg', '.gif', '.svg']) {
        final f = File('${dir.path}/$emojiId$ext');
        if (f.existsSync()) return f;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetCacheForTest() {}
}
