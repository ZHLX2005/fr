// lib/core/sudoku/p2p/script/sudoku_script.dart
//
// kSudokuScript 入口 —— 经 LuaScriptAssembler 拼接 lifecycle + actions +
// 共享 emoji 段。
//
// 与 chess_script.dart 同样的三段拼接顺序约束（见 chess_script.dart 顶部注释）。

import '../../../game_kit/emoji/lua_script_assembler.dart';
import '../../../game_kit/emoji/emoji_script.dart';
import 'sudoku_script_lifecycle.dart';
import 'sudoku_script_actions.dart';

/// 数独联机 Lua 脚本（const 拼装）。
final String kSudokuScript = assembleLuaScript(
  lifecycle: kSudokuScriptLifecycle,
  actions: kSudokuScriptActions,
  extraSegments: [kEmojiScriptSegment],
);
