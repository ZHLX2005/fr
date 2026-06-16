// Session 同步路径的 GamePage 测试
//
// 验证：
//   - LanHostGamePage / LanClientGamePage 不再持有 ViewModel 状态机（静态契约）
//   - GameState 初始 currentPlayerIsTop 为 true（host 是 top player）
//   - switchTurn 后 currentPlayerIsTop 反转
//
// 注：直接 pump Widget 会触发 LanServiceAdapter.createGameSession → LanFramework
// 实例方法，在 widget test 环境（无 UDP socket）下抛 FrameworkNotRunningException。
// 因此 page 的"无 VM 状态机"语义改为源码契约检查。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';

void main() {
  test('LanHostGamePage 不持有 ViewModel 状态机（源码契约）', () {
    final src = File(
      'lib/core/surround_game/lan/lan_host_game_page.dart',
    ).readAsStringSync();
    expect(
      src.contains('LanHostViewModel'),
      isFalse,
      reason: '重构后 LanHostGamePage 应改用 Session，不应再引用 LanHostViewModel',
    );
  });

  test('LanClientGamePage 不持有 ViewModel 状态机（源码契约）', () {
    final src = File(
      'lib/core/surround_game/lan/lan_client_game_page.dart',
    ).readAsStringSync();
    expect(
      src.contains('LanClientViewModel'),
      isFalse,
      reason: '重构后 LanClientGamePage 应改用 Session，不应再引用 LanClientViewModel',
    );
  });

  test('isMyTurn 在初始空棋盘上为 true（host 是 top）', () {
    final gs = QuoridorEngine.initialize();
    expect(gs.currentPlayerIsTop, isTrue);
  });

  test('switchTurn 后 currentPlayerIsTop 反转', () {
    final s0 = QuoridorEngine.initialize();
    final s1 = QuoridorEngine.movePiece(s0, 13)!;
    final s2 = QuoridorEngine.switchTurn(s1);
    expect(s2.currentPlayerIsTop, isFalse);
  });
}
