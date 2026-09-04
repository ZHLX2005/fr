// lib/core/game_kit/emoji/emoji_bundle.dart
//
// Emoji bundle — 合并 common + game 作用域的表情，并提供：
//   · KV 拉取（PublicKvReader，group 190）
//   · 本地文件缓存（复用 GameSkinLocalizer 的分区目录 emojis/<scope>/，
//     或 bundles 自己的简单文件缓存 —— 能复用就复用）
//   · 24 个 unicode 兜底（零 KV / 零文件也能用）
//   · forGame(gameId)：common 先、game 后（后者覆盖同 id）

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

/// 单条表情的运行时视图（id + 显示字符/图源）。
class EmojiEntry {
  /// 稳定的 emoji id（发送时走 EMOJI 的 emoji_id 参数）。
  final String id;

  /// 远端文件引用（null = unicode 兜底）。
  final FileRef? fileRef;

  /// unicode 字符（fileRef == null 时用于渲染）.
  final String? unicode;

  /// 解析到的本地文件（若已缓存）。
  final File? localFile;

  const EmojiEntry({
    required this.id,
    this.fileRef,
    this.unicode,
    this.localFile,
  });

  bool get isBuiltin => fileRef == null;

  /// 构造渲染用的 [ImageProvider]（本机文件优先，回退网络）。
  ///
  /// unicode 兜底不走这里（直接 Text）。
  ImageProvider? imageProvider(FileResolver? resolver) {
    if (isBuiltin) return null;
    final lf = localFile;
    if (lf != null && lf.existsSync()) return FileImage(lf);
    final ref = fileRef;
    if (ref == null) return null;
    final r = resolver;
    if (r == null) return null;
    return NetworkImage(r.url(ref.fileId));
  }
}

/// 24 个 unicode 兜底（零网络可用的共享表情）。
const List<({String id, String char})> kBuiltinEmoji24 = [
  (id: 'thumbs-up', char: '\u{1F44D}'),
  (id: 'clap', char: '\u{1F44F}'),
  (id: 'heart', char: '\u{2764}\u{FE0F}'),
  (id: 'fire', char: '\u{1F525}'),
  (id: 'star-struck', char: '\u{1F929}'),
  (id: 'laugh', char: '\u{1F602}'),
  (id: 'cry-laugh', char: '\u{1F639}'),
  (id: 'thinking', char: '\u{1F914}'),
  (id: 'sweat-smile', char: '\u{1F605}'),
  (id: 'sob', char: '\u{1F62D}'),
  (id: 'angry', char: '\u{1F620}'),
  (id: 'scream', char: '\u{1F631}'),
  (id: 'eyes', char: '\u{1F440}'),
  (id: 'party', char: '\u{1F389}'),
  (id: 'tada', char: '\u{1F38A}'),
  (id: 'trophy', char: '\u{1F3C6}'),
  (id: 'rose', char: '\u{1F339}'),
  (id: 'pray', char: '\u{1F64F}'),
  (id: 'muscle', char: '\u{1F4AA}'),
  (id: 'ok-hand', char: '\u{1F44C}'),
  (id: 'wave', char: '\u{1F44B}'),
  (id: 'eyes-heart', char: '\u{1F60D}'),
  (id: 'cool', char: '\u{1F60E}'),
  (id: 'sleep', char: '\u{1F634}'),
];

List<EmojiEntry> _builtinEntries() => [
      for (final e in kBuiltinEmoji24)
        EmojiEntry(id: e.id, unicode: e.char),
    ];

/// Emoji 运行时 bundle（按 [gameId] 合并 common + game 作用域）。
class EmojiBundle {
  /// 当前生效的条目（已按 common 先、game 后合并且去重；game 同 id 覆盖 common）。
  final List<EmojiEntry> entries;

  /// id → entry 索引（用于校验 + 快取文件命中）。
  final Map<String, EmojiEntry> byId;

  /// 已加载的 pack meta（调试用；含被覆盖的旧 id 的来源）。
  final List<EmojiPackMeta> packs;

  const EmojiBundle({
    required this.entries,
    required this.byId,
    this.packs = const [],
  });

  /// 仅兜底（无 KV 也能实例化）。
  factory EmojiBundle.builtin() {
    final entries = _builtinEntries();
    return EmojiBundle(
      entries: entries,
      byId: {for (final e in entries) e.id: e},
      packs: const [],
    );
  }

  /// 指定 [gameId] 的 bundle（common + game 作用域，game 覆盖 common）。
  ///
  /// - [reader] / [fileResolver] 可注入（测试用）。
  /// - [defaultBaseUrl] 当未注入 reader 时使用（通常 GoframeConfig.baseUrl）。
  /// - 本地缓存目录：优先复用 skin 的 emojis / 分区（GameSkinLocalizer
  ///   已初始化过的 baseDir + 子目录）；未初始化则走应用文档目录的 emojis /。
  /// - [httpClient] / [dirProvider] 仅测试注入。
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
    final _ = fileResolver ?? PublicFileResolver(baseUrl: kv.baseUrl);

    final scopes = <String>['common', gameId];
    final allPacks = <EmojiPackMeta>[];
    for (final scope in scopes) {
      final key = EmojiPackMeta.kvIndexKeyForScope(scope);
      final jsonText = await kv.readString(key);
      if (jsonText == null) continue;
      List<EmojiPackMeta>? parsed;
      try {
        parsed = EmojiPackMeta.parseList(jsonText);
      } catch (_) {
        continue;
      }
      allPacks.addAll(parsed);
    }

    // id → FileRef（后者覆盖前者：game 覆盖 common）
    final merged = <String, FileRef>{};
    for (final pack in allPacks) {
      for (final entry in pack.emojis.entries) {
        merged[entry.key] = entry.value;
      }
    }

    // 尝试关联本地缓存文件（若分区目录存在且 fileId 匹配）
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

    // 构造最终 entries：先兜底 24，再叠加远端（同 id 远端覆盖兜底位的图源）
    final builtinById = {for (final e in kBuiltinEmoji24) e.id: e.char};
    final entries = <EmojiEntry>[];
    final byId = <String, EmojiEntry>{};
    // 简化：直接以 merged 的最终值为准重建（保证"game 覆盖 common"）
    for (final id in merged.keys) {
      final ref = merged[id]!;
      entries.add(EmojiEntry(
        id: id,
        fileRef: ref,
        localFile: cacheById[id],
      ));
    }
    // 补齐未被远端覆盖的 builtin（远端未提供的 id 仍可用 unicode）
    for (final b in kBuiltinEmoji24) {
      if (!merged.containsKey(b.id)) {
        entries.add(EmojiEntry(id: b.id, unicode: b.char));
      }
    }
    // 去重后的 byId（entries 已是去重后的顺序）
    for (final e in entries) {
      byId[e.id] = e;
    }

    // 若远端八字没一撇（KV 全空），entries 仍为 24 兜底，调用方无需判空
    // 若没有任何远端，仍返回 builtin（保持 packs 为空）
    if (merged.isEmpty) {
      final builtin = _builtinEntries();
      return EmojiBundle(
        entries: builtin,
        byId: {for (final e in builtin) e.id: e},
        packs: const [],
      );
    }

    // 兜底 id 的 unicode 已在 EmojiEntry.unicode 上保留（远端未覆盖时可见）
    // 已覆盖的远端条目若将来文件丢失，回退到 builtin unicode（由调用方决定）
    // 这里保留 builtinById 以便 panel 在 FileImage 失败时回退字符
    // （panel 读取 EmojiEntry.unicode ?? builtinById[id]）
    // 为让该回退可用，给远端条目也补上 unicode 映射（若存在）
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.fileRef != null && e.unicode == null) {
        final ch = builtinById[e.id];
        if (ch != null) {
          entries[i] = EmojiEntry(
            id: e.id,
            fileRef: e.fileRef,
            unicode: ch,
            localFile: e.localFile,
          );
        }
      }
    }
    final rebuiltById = {for (final e in entries) e.id: e};

    return EmojiBundle(entries: entries, byId: rebuiltById, packs: allPacks);
  }

  /// 预取并缓存当前 bundle 的远端文件到本地（best-effort）。
  ///
  /// 复用 emojis / 目录（scope 取 id 分区的首段或默认 common），
  /// 与 skin 管线互不干扰；失败静默。
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
        final ref = e.fileRef;
        if (ref == null) continue;
        if (e.localFile != null && e.localFile!.existsSync()) continue;
        final dir = await _emojiDirForId(e.id, dirProvider: dirProvider);
        if (dir == null) continue;
        try {
          await dir.create(recursive: true);
          final url = r?.url(ref.fileId) ??
              'http://47.110.80.47:8988/files/${ref.fileId}';
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode != 200) continue;
          final ext = _extForContentType(ref.contentType);
          final f = File('${dir.path}/${e.id}$ext');
          await f.writeAsBytes(resp.bodyBytes, flush: true);
          final idxFile = File('${dir.path}/.emoji-index.json');
          Map<String, dynamic> idx = {};
          if (idxFile.existsSync()) {
            try {
              idx = jsonDecode(idxFile.readAsStringSync()) as Map<String, dynamic>;
            } catch (_) {}
          }
          idx[e.id] = ref.fileId;
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
      // 分区：复用 emojis / 语义，scope 按 emojiId 首段 hash 到子目录
      // 简化：统一 emojis/common/ 与 emojis/<game>/ 的扁平隔离，当前阶段
      // 仅需一个分区，统一落 emojis/ 下的 id 子目录的父级
      // 实际路径：<docs>/emojis/<emojiId>/ 形式中的 <docs>/emojis/
      // 为与 skin 的 emojis / 约定对齐，统一为 <docs>/emojis/common/
      // （game 作用域的覆盖已在内存 merge 完成，磁盘缓存不需按 scope 二级分区）
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
      // 先尝试读取索引校验 fileId（防旧缓存不失效）
      final idxFile = File('${dir.path}/.emoji-index.json');
      if (idxFile.existsSync()) {
        try {
          final raw = jsonDecode(idxFile.readAsStringSync());
          if (raw is Map && raw[emojiId] is String) {
            if (raw[emojiId] != ref.fileId) return null;
          }
        } catch (_) {}
      }
      // 尝试常见扩展名
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
