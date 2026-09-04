// lib/core/gomoku/skins/gomoku_skin.dart
//
// 五子棋皮肤合约 + Bundle 注册表（对齐 lib/core/chess/skins/chess_skin.dart 模式）。

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show ImageProvider;

import '../../chess/skins/chess_skin_localizer.dart';
import '../../chess/skins/file_resolver.dart';
import 'gomoku_skin_meta.dart';
import 'remote_gomoku_skin.dart';

const String kDefaultGomokuSkinBaseUrl = 'http://47.110.80.47:8988';

/// 五子棋皮肤接口（UI 仅依赖此抽象）。
abstract class GomokuSkin {
  String get id;
  String get displayName;
  /// 棋盘底图（null → 走 BoardColorStrategy.background）
  ImageProvider? get boardBackground;
  /// 黑白两子贴图（key ∈ {black, white}；缺 key → UI 回退彩色圆棋子）
  Map<String, ImageProvider> get pieces;
}

/// 默认皮肤：pieces == {} → 回退彩色圆落子（board.dart 旧行为）
class GomokuDefaultSkin implements GomokuSkin {
  const GomokuDefaultSkin();
  @override
  String get id => 'default';
  @override
  String get displayName => '默认（彩色回退）';
  @override
  ImageProvider? get boardBackground => null;
  @override
  Map<String, ImageProvider> get pieces => const {};
}

abstract class GomokuSkinBundle {
  static final Map<String, GomokuSkin> _registry = <String, GomokuSkin>{
    'default': const GomokuDefaultSkin(),
  };

  static final Map<String, GomokuSkinMeta> _metas = <String, GomokuSkinMeta>{};

  static Map<String, GomokuSkin> get all => Map.unmodifiable(_registry);
  static List<GomokuSkinMeta> get metas => List.unmodifiable(_metas.values);
  static int get metaCount => _metas.length;

  static GomokuSkin byId(String id) => _registry[id] ?? _registry['default']!;

  /// 把 hardcode catalog 装入注册表（main 启动期一次，幂等）。
  static void registerHardcoded() {
    unawaited(ChessSkinLocalizer.ensureBaseDirInit());
    _metas
      ..clear()
      ..addAll({for (final m in kGomokuSkinsCatalog) m.id: m});
    for (final meta in kGomokuSkinsCatalog) {
      _registry[meta.id] = RemoteGomokuSkin(
        meta: meta,
        fileResolver: const PublicFileResolver(baseUrl: kDefaultGomokuSkinBaseUrl),
      );
    }
  }

  /// KV 追加/覆盖（换肤免发版，与 ChessSkinBundle.registerRemoteSkins 同语义）。
  static void registerRemoteSkins(
    List<GomokuSkinMeta> metas, {
    required FileResolver fileResolver,
  }) {
    for (final meta in metas) {
      _metas[meta.id] = meta;
      _registry[meta.id] = RemoteGomokuSkin(meta: meta, fileResolver: fileResolver);
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _registry.clear();
    _registry['default'] = const GomokuDefaultSkin();
    _metas.clear();
  }
}
