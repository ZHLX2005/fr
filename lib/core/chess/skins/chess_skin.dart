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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show ImageProvider;

import '../models/piece.dart';
import 'chess_skin_meta.dart';
import 'file_resolver.dart';
import 'remote_chess_skin.dart';

/// 内置 skin 远端 baseUrl 默认值。
///
/// equals ApiConfig.production().baseUrl default; future: read from ApiConfig
const String kDefaultChessSkinBaseUrl = 'http://47.110.80.47:8988';

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
          baseUrl: kDefaultChessSkinBaseUrl,
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