// lib/core/game_kit/skin/game_skin_bundle.dart
//
// Generic skin bundle + GameSkin interface. Extracted from
// lib/core/chess/skins/chess_skin.dart but parameterized so each
// game owns its registry instance.

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart' show ImageProvider;

import 'file_resolver.dart';
import 'game_skin_localizer.dart';
import 'game_skin_meta.dart';
import 'game_skin_spec.dart';
import 'local_game_skin.dart';
import 'public_kv_reader.dart';
import 'remote_game_skin.dart';

/// 一套皮肤的 UI 接口（抽象；与来源解耦）.
abstract class GameSkin {
  String get id;
  String get displayName;
  ImageProvider? get boardBackground;
  Map<String, ImageProvider> get pieces;
}

/// 默认 fallback 皮肤（`pieces == {}` → unicode / 主题回退）.
class GameDefaultSkin implements GameSkin {
  const GameDefaultSkin();
  @override
  String get id => 'default';
  @override
  String get displayName => '默认（回退）';
  @override
  ImageProvider? get boardBackground => null;
  @override
  Map<String, ImageProvider> get pieces => const {};
}

/// Per-game 的皮肤注册表（generic；chess / gomoku 各自一份实例）.
class GameSkinBundle {
  GameSkinBundle(this.spec);

  final GameSkinSpec spec;

  final Map<String, GameSkin> _registry = <String, GameSkin>{
    'default': const GameDefaultSkin(),
  };
  final Map<String, GameSkinMeta> _metas = <String, GameSkinMeta>{};

  Map<String, GameSkin> get all => Map.unmodifiable(_registry);
  List<GameSkinMeta> get metas => List.unmodifiable(_metas.values);
  int get metaCount => _metas.length;

  GameSkin byId(String id) => _registry[id] ?? _registry['default']!;

  /// 解析 [jsonText] 为 [List<GameSkinMeta>]，失败返回 null.
  List<GameSkinMeta>? parseAndValidate(String jsonText) {
    try {
      return GameSkinMeta.parseList(jsonText);
    } catch (_) {
      return null;
    }
  }

  void registerHardcoded(
    List<GameSkinMeta> catalog, {
    required FileResolver fileResolver,
  }) {
    unawaited(GameSkinLocalizer.ensureBaseDirInitFor(spec));
    _metas
      ..clear()
      ..addAll({for (final m in catalog) m.id: m});
    for (final meta in catalog) {
      _registry[meta.id] = RemoteGameSkin(
        meta: meta,
        fileResolver: fileResolver,
        boardBackgroundFileNameOf: LocalGameSkin.boardBackgroundFileName,
        spec: spec,
      );
    }
  }

  void registerRemoteSkins(
    List<GameSkinMeta> metas, {
    required FileResolver fileResolver,
  }) {
    for (final meta in metas) {
      _metas[meta.id] = meta;
      _registry[meta.id] = RemoteGameSkin(
        meta: meta,
        fileResolver: fileResolver,
        boardBackgroundFileNameOf: LocalGameSkin.boardBackgroundFileName,
        spec: spec,
      );
    }
  }

  @visibleForTesting
  void resetForTest() {
    _registry.clear();
    _registry['default'] = const GameDefaultSkin();
    _metas.clear();
  }

  // ── KV index 持久化（id58 / 皮肤线上化：拉取成功落盘，下次启动离线恢复） ──

  /// KV index 落盘文件名（存于 `<docs>/<cacheDirName>/skin-index.json`）。
  static const String kIndexCacheFileName = 'skin-index.json';

  /// 把 KV index 原文持久化到磁盘（best-effort：任何失败静默返回 false）。
  ///
  /// 文件内容为 wrapper：`{"baseUrl": <file host>, "index": <KV 原始 JSON 文本>}`，
  /// baseUrl 一并保存以便恢复时用同一文件 host 构造 resolver。
  Future<bool> persistIndexJson(
    String rawJsonText, {
    required String baseUrl,
  }) async {
    try {
      final root = await GameSkinLocalizer.ensureCacheRootFor(spec);
      if (root == null) return false;
      final f = File(
        '${root.path}${Platform.pathSeparator}$kIndexCacheFileName',
      );
      await f.writeAsString(
        jsonEncode({'baseUrl': baseUrl, 'index': rawJsonText}),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 从磁盘恢复上次持久化的 KV index（离线首屏 / 离线皮肤清单）。
  ///
  /// 恢复 = 解析 + registerRemoteSkins（upsert 语义，同 id 覆盖）。
  /// 无文件 / 损坏 / 解析失败 / web → 返回 false（调用方走强拉或兜底）。
  Future<bool> restorePersistedIndex() async {
    try {
      if (kIsWeb) return false;
      final root = await GameSkinLocalizer.ensureCacheRootFor(spec);
      if (root == null) return false;
      final f = File(
        '${root.path}${Platform.pathSeparator}$kIndexCacheFileName',
      );
      if (!f.existsSync()) return false;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return false;
      final baseUrl = raw['baseUrl'];
      final index = raw['index'];
      if (baseUrl is! String || baseUrl.isEmpty || index is! String) {
        return false;
      }
      final metas = parseAndValidate(index);
      if (metas == null || metas.isEmpty) return false;
      registerRemoteSkins(
        metas,
        fileResolver: PublicFileResolver(baseUrl: baseUrl),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 拉取 KV 并合入注册表（generic fetchAndMerge）.
  Future<bool> fetchAndMerge({
    PublicKvReader? reader,
    FileResolver? resolver,
    required String defaultBaseUrl,
  }) async {
    unawaited(GameSkinLocalizer.ensureBaseDirInitFor(spec));
    final kv = reader ?? PublicKvReader(baseUrl: defaultBaseUrl, groupId: spec.groupId);
    final fileResolver = resolver ?? PublicFileResolver(baseUrl: kv.baseUrl);
    final jsonText = await kv.readString(spec.kvIndexKey);
    if (jsonText == null) return false;
    final parsed = parseAndValidate(jsonText);
    if (parsed == null) return false;
    registerRemoteSkins(parsed, fileResolver: fileResolver);
    // 拉取成功 → 落盘 index（fire-and-forget；下次启动离线恢复，id58）。
    unawaited(persistIndexJson(jsonText, baseUrl: kv.baseUrl));
    return true;
  }
}
