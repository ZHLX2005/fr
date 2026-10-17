// test/core/draughts/p2p/draughts_script_guard_test.dart
//
// kDraughtsScript 静态守卫测试 —— 客户端无法嵌 Lua VM，对脚本源码做防回归断言。
//
// 守卫对象（对齐 chess_script_guard_test 的方法，断言换成本游戏的不变量）：
//   · 装配正确性：handlers 必须是**顶层全局**，导出表由 assembler 统一生成
//     （写在 return 表里会触发 CreateRoom 400）。
//   · action_permissions 声明齐全（服务端按表派发 + 把守角色）。
//   · MOVE 存 fen（PDN 走子后局面的唯一权威快照）。
//   · CLAIM_END 只认 5 个 reason，且只由刚走完的一方发起。
//   · on_leave 的 playing/ready 分支只标 disconnected、不销毁房间（id47 语义）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/draughts/p2p/script/draughts_script.dart';

void main() {
  group('kDraughtsScript 装配正确性', () {
    test('三个生命周期 handler 存在且被导出表引用', () {
      for (final name in const ['on_init', 'on_join', 'on_leave']) {
        expect(kDraughtsScript, contains('$name = function'),
            reason: '$name 必须是顶层全局函数');
        expect(kDraughtsScript, contains('$name = $name,'),
            reason: '$name 必须被导出表按名引用（服务端按表派发）');
      }
    });

    test('所有动作 handler 存在且被导出表引用', () {
      const actions = [
        'ACK', 'DEAL', 'START', 'SET_RULES', 'MOVE', 'CLAIM_END',
        'RESIGN', 'DRAW_OFFER', 'DRAW_ACCEPT', 'DRAW_DECLINE',
        'UNDO_OFFER', 'UNDO_ACCEPT', 'UNDO_DECLINE', 'RESET',
      ];
      for (final a in actions) {
        expect(kDraughtsScript, contains('on_action_$a = function'),
            reason: 'on_action_$a 必须是顶层全局');
        expect(kDraughtsScript, contains('"on_action_$a"'),
            reason: 'on_action_$a 必须登记进 definition.functions');
      }
    });

    test('共享段 emoji / chat 已并入', () {
      expect(kDraughtsScript, contains('"on_action_EMOJI"'));
      expect(kDraughtsScript, contains('"on_action_CHAT"'));
    });

    test('导出表由 assembler 生成在脚本最末（return 出现在 handler 之后）', () {
      final returnIdx = kDraughtsScript.lastIndexOf('return {');
      expect(returnIdx, isNot(-1));
      final moveIdx = kDraughtsScript.indexOf('on_action_MOVE = function');
      expect(returnIdx, greaterThan(moveIdx),
          reason: '导出表必须在全部 handler 定义之后');
    });

    test('definition.functions 声明了全部 handler', () {
      expect(kDraughtsScript, contains('functions = {'));
      for (final a in const ['MOVE', 'CLAIM_END', 'RESIGN', 'RESET']) {
        expect(kDraughtsScript, contains('"on_action_$a"'));
      }
    });
  });

  group('kDraughtsScript 角色权限', () {
    test('action_permissions 声明齐全', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('ACK          = "any"'));
      expect(onInit, contains('DEAL         = "host"'));
      expect(onInit, contains('SET_RULES    = "host"'));
      expect(onInit, contains('MOVE         = "current_player"'));
      expect(onInit, contains('RESIGN       = "any"'));
      expect(onInit, contains('UNDO_OFFER   = "any"'));
      expect(onInit, contains('UNDO_ACCEPT  = "any"'));
      expect(onInit, contains('UNDO_DECLINE = "any"'));
      expect(onInit, contains('CLAIM_END    = "non_current_player"'));
      expect(onInit, contains('RESET        = "host"'));
    });

    test('role_check 按 host_color 判"走子方是不是 host"', () {
      final roleCheck = _functionBlock('function role_check(c, p, action)');
      expect(roleCheck, contains('local host_side = c.host_color or "w"'));
      expect(
        RegExp('c\\.host_color or "w"').allMatches(roleCheck).length,
        greaterThanOrEqualTo(2),
        reason: 'current_player 与 non_current_player 都须用 c.host_color',
      );
    });

    test('side_to_move 由 initial_side + 手数奇偶推', () {
      final fn = _functionBlock('function side_to_move(c, n)');
      expect(fn, contains('local first = c.initial_side or "w"'));
      expect(fn, contains('n % 2 == 0'));
    });
  });

  group('kDraughtsScript 走子与终局', () {
    test('MOVE 存 fen 并做轮次反证', () {
      final block = _functionBlock('on_action_MOVE = function');
      expect(block, contains('fen = p.fen'),
          reason: 'moves entry 必须存走后 fen（重连/重放恢复局面）');
      expect(block, contains('side_to_move(c, #c.moves + 1)'),
          reason: '必须用 side_to_move 推期望轮次做反证');
      expect(block, contains('if fen_turn ~= expect_side then'),
          reason: 'FEN 首字符轮次不符必须拒绝该手');
      expect(block, contains('is_valid_pdn_move(p.pdn)'));
      expect(block, contains('is_valid_draughts_fen(p.fen)'));
    });

    test('CLAIM_END 只认 5 个 reason，胜/和分流且由刚落子方发起', () {
      final block = _functionBlock('on_action_CLAIM_END = function');
      expect(block, contains('reason == "noPieces"'));
      expect(block, contains('reason == "noMoves"'));
      expect(block, contains('reason == "threefold"'));
      expect(block, contains('reason == "kingVsKing"'));
      expect(block, contains('reason == "kingMoveLimit"'));
      expect(block, contains('c.winner = p.device_id'),
          reason: '胜局 winner = 声明方（刚走完的一方）');
      expect(block, contains('c.status = "draw"'));
      expect(block, contains('role_check(c, p, "CLAIM_END")'));
    });

    test('RESIGN 分派 winner 给对手', () {
      final block = _functionBlock('on_action_RESIGN = function');
      expect(block, contains('c.winner = c.guest_id'));
      expect(block, contains('c.winner = c.host_id'));
      expect(block, contains('c.status = "resigned"'));
    });

    test('RESET 仅 host、仅终局后，清 history 回 lobby', () {
      final block = _functionBlock('on_action_RESET = function');
      expect(block, contains('role_check(c, p, "RESET")'));
      expect(block, contains('if state ~= "ended" then'));
      expect(block, contains('c.moves = {}'));
      expect(block, contains('c.status = "playing"'));
      expect(block, contains('state = "lobby"'));
    });
  });

  group('kDraughtsScript 悔棋（UNDO，对齐 chess）', () {
    test('UNDO_OFFER：零手拒绝 + 后手方不足两手拒绝 + 先手方按 host_color 推', () {
      final block = _functionBlock('on_action_UNDO_OFFER = function');
      expect(block, contains('if state ~= "playing" then'));
      expect(block, contains('local n = #c.moves'));
      expect(block, contains('if n == 0 then'),
          reason: '零手棋没有可悔的一手');
      expect(block, contains('(c.host_color or "w") == (c.initial_side or "w")'),
          reason: '先手方判定必须用 host_color == initial_side'
              '（host 执黑 / 黑先残局时 host 未必先手，chess v8 同坑）');
      expect(block, contains('(not requester_is_first) and n < 2'),
          reason: '后手方需 ≥2 手才够 pop 2');
      expect(block, contains('c.undo_offers[p.device_id] = true'));
    });

    test('UNDO_ACCEPT：pop 数按先手方奇偶推，回滚 fen，重算吃子空着数', () {
      final block = _functionBlock('on_action_UNDO_ACCEPT = function');
      expect(block, contains('if c.undo_offers[p.device_id] == true then'),
          reason: '双方都挂 offer → 只清 offer（互相取消）');
      expect(block, contains('pops = (n % 2 == 1) and 1 or 2'));
      expect(block, contains('pops = (n % 2 == 1) and 2 or 1'));
      expect(block, contains('table.remove(c.moves)'));
      expect(block, contains('c.fen = c.moves[#c.moves].fen'),
          reason: '回滚到末手记录的走后 fen（跳棋每手都存 fen）');
      expect(block, contains('c.ply_since_capture = ply'),
          reason: '跳棋特有：悔棋后必须重算距上次吃子的空着数');
      expect(block, contains('c.undo_offers = {}'));
      expect(block, contains('c.draw_offers = {}'));
      expect(block, contains('c.status = "playing"'));
    });

    test('UNDO_DECLINE：清对方的 offer', () {
      final block = _functionBlock('on_action_UNDO_DECLINE = function');
      expect(block, contains('c.undo_offers[c.guest_id] = nil'));
      expect(block, contains('c.undo_offers[c.host_id] = nil'));
    });

    test('MOVE 后清残留 offer（防带 offer 走子），RESET / on_leave 同清', () {
      final moveBlock = _functionBlock('on_action_MOVE = function');
      expect(moveBlock, contains('c.undo_offers = {}'),
          reason: '新的一手让挂起的悔棋 offer 过期');
      final resetBlock = _functionBlock('on_action_RESET = function');
      expect(resetBlock, contains('c.undo_offers = {}'));
      expect(resetBlock, contains('c.disconnected = {}'),
          reason: 'RESET 清断线标记（chess RESET 同款卫生）');
      expect(resetBlock, contains('c.emojiRing = {}'),
          reason: 'RESET 清 emoji 历史（跨局不泄漏）');
      expect(resetBlock, contains('c.chatRing = {}'),
          reason: 'RESET 清 chat 历史（跨局不泄漏）');
      final onLeave = _functionBlock('on_leave = function');
      expect(onLeave, contains('c.undo_offers[p.device_id] = nil'));
    });

    test('on_init 初始化 undo_offers 并登记权限', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('c.undo_offers = {}'));
    });
  });

  group('kDraughtsScript on_leave：对局中离开不销毁房间', () {
    test('playing/ready 只标 disconnected、不置 ended', () {
      final onLeave = _functionBlock('on_leave = function');
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      expect(lobbyIdx, isNot(-1));
      final playingBody = onLeave.substring(0, lobbyIdx);
      expect(playingBody, contains('c.disconnected[p.device_id] = true'));
      expect(playingBody, isNot(contains('state = "ended"')),
          reason: '对局中离开不得结束房间（同 device_id 重连恢复）');
      expect(onLeave, isNot(contains('c.force_leave')));
      expect(onLeave, isNot(contains('c.moves = {}')),
          reason: '离开不清权威棋谱');
    });

    test('lobby 分支保留空房语义', () {
      final onLeave = _functionBlock('on_leave = function');
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      final lobbyBody = onLeave.substring(lobbyIdx);
      expect(lobbyBody, contains('c.guest_id = nil'));
      expect(lobbyBody, contains('end_reason = "host_left_lobby"'));
    });
  });

  group('kDraughtsScript PDN / FEN 校验 helper', () {
    test('is_valid_pdn_move 存在且限 1..50', () {
      final fn = _functionBlock('function is_valid_pdn_move(pdn)');
      expect(fn, contains('n < 1 or n > 50'));
      expect(fn, contains('[x%-]'));
    });

    test('全部 Lua pattern 禁用捕获组后接量词（VM 恒返回 nil → 全拒）', () {
      // 2026-10-17 e2e 实锤：服务端 Lua 5.1 VM 上 `(...)*` 形式的 pattern
      // 会让 match 返回零值，`match(...) == nil` 恒真 → 所有 PDN 被拒
      // （「无法落子」根因）。回归守卫：任何 handler / helper 不得再引入。
      final groupPattern = RegExp(r'\)[+*-?]');
      for (final match in groupPattern.allMatches(kDraughtsScript)) {
        final lineStart = kDraughtsScript.lastIndexOf('\n', match.start) + 1;
        final lineEnd = kDraughtsScript.indexOf('\n', match.start);
        final line = kDraughtsScript.substring(
            lineStart, lineEnd == -1 ? kDraughtsScript.length : lineEnd);
        final isLuaMatchCall = line.contains(':match(') ||
            line.contains(':gmatch(') ||
            line.contains(':gsub(');
        expect(isLuaMatchCall, isFalse,
            reason: 'Lua pattern 疑似捕获组量词（VM 不支持）→ $line');
      }
    });

    test('is_valid_draughts_fen 存在且匹配 X:W…:B… 结构', () {
      final fn = _functionBlock('function is_valid_draughts_fen(fen)');
      expect(fn, contains('^[WB]:[WB]'));
    });

    test('默认开局 FEN 是跳棋起点', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('"W:W31-50:B1-20"'));
    });
  });
}

/// 截取指定函数块（从定义起，到下一个顶层 `on_` 定义为止）。
/// 守卫测试用：限定断言不跨函数误伤。
String _functionBlock(String marker) {
  final start = kDraughtsScript.indexOf(marker);
  expect(start, isNot(-1), reason: '脚本体必须含 $marker');
  final next = RegExp(
    r'\non_(?:action|join|leave|init)_\w+ = function',
  ).allMatches(kDraughtsScript.substring(start + 1));
  if (next.isEmpty) {
    return kDraughtsScript.substring(start);
  }
  return kDraughtsScript.substring(start, start + 1 + next.first.start);
}
