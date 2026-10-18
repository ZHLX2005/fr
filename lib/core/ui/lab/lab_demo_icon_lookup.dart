// Lab 演示 SVG 图标的 slug → asset 名映射表。
//
// 设计：所有 demo 共享同一份 48 个 SVG（来自 Ardot 设计稿，按数字序号命名）。
// 这里维护「demoSlug → SVG basename」查找，未登记返回 null——
// 调用方负责兜底（用 LabIconKind.fallback 显示通用图标，或保留原 Icons.widgets）。
//
// 维护规则：
//   - 仅登记 Lab 中真实存在的 demo slug（详见 lib/lab/demos/* 的 `String get slug`）。
//   - slug 与 DemoPage.slug 完全一致（纯 ASCII 小写连字符）。
//   - 新增 demo 时：有对应 SVG → 加一行；没有 → 暂用 `LabIconKind.fallback`。

import 'package:flutter/foundation.dart';

class LabIconKind {
  const LabIconKind._(this._value);
  final String _value;

  /// 未登记 / 没有专属 SVG 的 demo，由调用方决定兜底。
  static const LabIconKind fallback = LabIconKind._('');

  /// SVG basename；空串 = fallback。
  String get assetBaseName => _value;

  @override
  String toString() => _value.isEmpty ? '__fallback__' : _value;

  /// 是否未登记。
  bool get isFallback => _value.isEmpty;
}

/// 把 demo slug 映射到 SVG basename（不含 `.svg` 后缀）。
///
/// 返回 [LabIconKind.fallback] 时调用方按各自约定兜底（demo card 用通用图标）。
LabIconKind labIconForDemoSlug(String demoSlug) {
  final mapped = _slugToAsset[demoSlug];
  if (mapped == null) return LabIconKind.fallback;
  return LabIconKind._(mapped);
}

/// 当前 demo 用到的全部 SVG basename（不重复），用 [LabDemoIcon.prewarm] 一次性预热。
List<String> get allLabIconAssetBaseNames => _slugToAsset.values.toSet().toList()
  ..sort();

const Map<String, String> _slugToAsset = {
  // ── 效率 · 系统 ─────────────────────────────────────────
  'clock': '01-clock',
  'calendar': '02-calendar-todo',
  'torch': '03-flashlight',
  'recorder': '04-recorder',
  'volume-decay': '05-volume-fade',
  'metronome': '06-metronome',
  'sensor': '07-sensor',
  'network': '08-network',
  'message_net': '09-message-net',
  'storage-analyze': '10-storage-analysis',
  'gallery': '11-gallery-manage',
  'pigment-palette': '12-palette',
  'overlay': '13-floating-capture',
  'word-drag': '14-word-drag',
  'price-compare': '15-price-calc',
  'body-map': '16-body-record',
  'bottom-bar': '17-bottom-nav',
  'block-editor': '18-block-editor',
  'api-test': '19-api-test',
  'schema': '20-schema-link',
  'kvcli-todo': '21-kv-list',
  'notion-image-host': '22-notion-image-host',
  'github': '23-github',
  'web-bookmark': '24-web-bookmarks',
  'novel-reader': '25-novel-reader',
  'remotetype': '26-remote-input',
  'relation-calc': '27-relation-calc',
  'rive-demo': '28-rive-demo',
  'crash-log': '29-crash-log',
  'double-time': '30-double-time',
  'auth-login': '31-auth-login',
  'line': '32-line',

  // ── 协作 ─────────────────────────────────────────────────
  'cowrite-lua': '33-collab-note',
  'reaction-test': '34-reaction-test',

  // ── 游戏 ─────────────────────────────────────────────────
  'game-2048': '35-2048',
  'tetris-lua': '36-tetris',
  'snake': '37-snake',
  'gomoku-lua': '38-gomoku',
  'go-lua': '39-go',
  'chess-online': '40-chess',
  'jungle-chess': '41-animal-chess',
  'reversi-lua': '42-reversi',
  'coup-lua': '43-coup',
  'surround-game': '44-blockade',
  'sudoku-lua': '45-sudoku',
  'team-card-lua': '46-team-cards',
  'jungle-chess-lua': '47-animal-chess-online',
  'surround-game-lua': '48-blockade-online',
};

/// 测试与 lint 用：覆盖率提示。所有 48 个 asset 都应至少被一个 demo slug 引用。
@visibleForTesting
Map<String, String> debugLabIconMapping() => Map.unmodifiable(_slugToAsset);
