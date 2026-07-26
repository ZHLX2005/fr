// lib/lab/demos/tetris_lua/constants.dart
// 俄罗斯方块 Lua 版 — 常量 + 持久化 + 方块/颜色/速度/计分表
//
// 方块类型用整数 1..7，与服务端共享序列 c.piece_sequence 的取值一致。
// 这样 Dart/Lua 两侧无需结构体对齐，序列就是一串 int。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 ──

const String kTetrisRelayUrl = 'http://47.110.80.47:8988';
const String kTetrisAliasKey = 'tetris_lua.alias';

class TetrisAliasPrefs {
  static Future<String> load() => SharedPreferences.getInstance().then(
    (p) => p.getString(kTetrisAliasKey) ?? '',
  );
  static Future<void> save(String alias) => SharedPreferences.getInstance()
      .then((p) => p.setString(kTetrisAliasKey, alias));
}

// ── 棋盘 ──

const int kTetrisCols = 10;
const int kTetrisRows = 20;

// ── 方块类型（1..7，与服务端序列一致）──
//   1=I  2=O  3=T  4=S  5=Z  6=J  7=L
const int kPieceI = 1, kPieceO = 2, kPieceT = 3;
const int kPieceS = 4, kPieceZ = 5, kPieceJ = 6, kPieceL = 7;

/// spawn 矩阵（行优先，1=填充）。旋转 = 矩阵顺时针转，无需手写 4 态。
/// 尺寸不统一：I=4x4，O=2x2（不旋转），其余=3x3。
const Map<int, List<List<int>>> kPieceMatrices = {
  kPieceI: [
    [0, 0, 0, 0],
    [1, 1, 1, 1],
    [0, 0, 0, 0],
    [0, 0, 0, 0],
  ],
  kPieceO: [
    [1, 1],
    [1, 1],
  ],
  kPieceT: [
    [0, 1, 0],
    [1, 1, 1],
    [0, 0, 0],
  ],
  kPieceS: [
    [0, 1, 1],
    [1, 1, 0],
    [0, 0, 0],
  ],
  kPieceZ: [
    [1, 1, 0],
    [0, 1, 1],
    [0, 0, 0],
  ],
  kPieceJ: [
    [1, 0, 0],
    [1, 1, 1],
    [0, 0, 0],
  ],
  kPieceL: [
    [0, 0, 1],
    [1, 1, 1],
    [0, 0, 0],
  ],
};

/// 7 种方块的现代色（堆积格与下落块共用）。
const Map<int, Color> kPieceColors = {
  kPieceI: Color(0xFF22D3EE), // cyan
  kPieceO: Color(0xFFFACC15), // yellow
  kPieceT: Color(0xFFA855F7), // purple
  kPieceS: Color(0xFF22C55E), // green
  kPieceZ: Color(0xFFEF4444), // red
  kPieceJ: Color(0xFF3B82F6), // blue
  kPieceL: Color(0xFFF97316), // orange
};

/// 强调色（与 I 块同色青），用于建房/加入表单的焦点色与标题图标。
const Color kTetrisAccent = Color(0xFF22D3EE);

/// 空格颜色码（grid 里 0 = 空）。
const int kEmptyCell = 0;

// ── 速度 / 计分 ──

/// 重力间隔表（毫秒/格）。level 越高越快，level≥表长取末值。
const List<int> kGravityTableMs = [
  1000, 850, 700, 600, 500, // level 0-4
  420, 350, 280, 200, 130, // level 5-9
  90, 80, 70, 60, 50, 40, // level 10+
];

int gravityMs(int level) =>
    kGravityTableMs[level.clamp(0, kGravityTableMs.length - 1)];

/// 软降按下时的间隔（ms）—— 比最低重力更快的手感。
const int kSoftDropMs = 40;

/// 一次消 N 行的得分（不含 level 倍率）。
const List<int> kLineScores = [0, 100, 300, 500, 800];

/// 软降每格加分 / 硬降每格加分。
const int kSoftDropScore = 1;
const int kHardDropScore = 2;

/// 每消多少行升一级。
const int kLinesPerLevel = 10;

// ── 同步节流 ──

/// 落定 SYNC 的最小间隔：避免极端手速连点导致刷屏。落定本身是事件驱动
/// （几秒一次），此值仅作兜底。
const Duration kSyncMinInterval = Duration(milliseconds: 120);

/// 对方迷你预览面板的宽度（格子数，与主棋盘同列）。
const int kMiniCols = kTetrisCols;
const int kMiniRows = kTetrisRows;
