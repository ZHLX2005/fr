// test/core/sudoku/p2p/sudoku_script_guard_test.dart
//
// kSudokuScript 静态守卫：脚本含生命周期 + action handler，且导出表末尾
// 由 assembler 生成并注册全部 handler。
//
// 命名约定：handler 用 chess 风格的 `on_X = function(...)` 顶层全局
// 赋值（assembler `_collectActionNames` 正则仅识别该模式）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/sudoku/p2p/script/sudoku_script.dart';

void main() {
  test('kSudokuScript 含生命周期 handler（on_init/on_join/on_leave）', () {
    expect(kSudokuScript, contains('on_init = function'));
    expect(kSudokuScript, contains('on_join = function'));
    expect(kSudokuScript, contains('on_leave = function'));
  });

  test('kSudokuScript 含 action handler（SET_PUZZLE / START / PROGRESS / SUBMIT）', () {
    expect(kSudokuScript, contains('on_action_SET_PUZZLE = function'));
    expect(kSudokuScript, contains('on_action_START = function'));
    expect(kSudokuScript, contains('on_action_PROGRESS = function'));
    expect(kSudokuScript, contains('on_action_SUBMIT = function'));
  });

  test('身份字段用 device_id（relay 契约），禁止 payload.uid 回归', () {
    // v1 bug：读 payload.uid（永远 nil）→ players[nil]=true 抛 Lua 运行时错、
    // host_id/guest_id 永远为空 → 房间卡死无法开始。
    expect(kSudokuScript, isNot(contains('payload.uid')));
    expect(kSudokuScript, isNot(contains('p.uid')));
    expect(kSudokuScript, contains('p.device_id'));
  });

  test('状态机走全局 state（snapshot state 字段来源），禁止 ctx.state 回归', () {
    // v1 bug：写 ctx.state —— snapshot 的 state 来自全局变量，ctx.state
    // 永远不会反映到快照，客户端永远收不到 'playing'。
    expect(kSudokuScript, contains('state = "playing"'));
    expect(kSudokuScript, contains('state = "ready"'));
    expect(kSudokuScript, contains('state = "ended"'));
    expect(kSudokuScript, isNot(contains('ctx.state')));
  });

  test('导出表最后由 assembler 生成，含全部 handler 绑定', () {
    final idx = kSudokuScript.lastIndexOf('return {');
    expect(idx, greaterThan(0));
    final tail = kSudokuScript.substring(idx);
    expect(tail, contains('on_init'));
    expect(tail, contains('on_join'));
    expect(tail, contains('on_leave'));
    expect(tail, contains('on_action_SET_PUZZLE'));
    expect(tail, contains('on_action_START'));
    expect(tail, contains('on_action_PROGRESS'));
    expect(tail, contains('on_action_SUBMIT'));
  });
}
