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

  test('kSudokuScript 含 action handler（SET_PUZZLE / START / SUBMIT）', () {
    expect(kSudokuScript, contains('on_action_SET_PUZZLE = function'));
    expect(kSudokuScript, contains('on_action_START = function'));
    expect(kSudokuScript, contains('on_action_SUBMIT = function'));
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
    expect(tail, contains('on_action_SUBMIT'));
  });
}
