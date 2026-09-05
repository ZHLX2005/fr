// lib/core/game_kit/skin/game_skin_bundle.dart
//
// Generic skin bundle + GameSkin interface. Extracted from
// lib/core/chess/skins/chess_skin.dart but parameterized so each
// game owns its registry instance.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
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
    return true;
  }
}
