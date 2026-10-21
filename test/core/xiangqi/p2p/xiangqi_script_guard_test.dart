// test/core/xiangqi/p2p/xiangqi_script_guard_test.dart
//
// kXiangqiScript 静态守卫测试 —— 客户端无法嵌 Lua VM，对脚本源码做防回归断言。
//
// 与 chess_script_guard_test.dart / draughts 同款结构：
//   · on_leave 的 playing/ready 分支语义（暂时离线，不销毁房间）
//   · 悔棋（UNDO）三 handler 的注册 + 前置门 + pop 逻辑
//   · host_color 与 first_mover 解耦（象棋用 'r' / 'b'）
//   · SET_RULES 准备阶段改规则
//   · on_join 空房回收（防「幽灵满员」死锁）
//   · 求和（DRAW）/ 认输（RESIGN）/ 终局声明（CLAIM_END）三件套
//
// 象棋特有（有意为之，不算 divergence）：
//   · 颜色是红 / 黑（'r' / 'b'），红先
//   · FEN 轮次位是 'r' / 'b'
//   · 走法记号 `b0e2`（不是 UCI / PDN）
//   · 终局只有 checkmate / stalemate，都是判负

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/script/xiangqi_script.dart';

/// 归一化脚本（折叠所有连续空白）—— 让守卫断言不依赖源码对齐空格。
///
/// chess 的守卫断言写的是单空格对齐（`UNDO_OFFER = "any"`），
/// draughts / xiangqi 的 action_permissions 表是列对齐（`UNDO_OFFER   = "any"`）——
/// 两者语义相同、仅排版不同。归一化后断言与排版解耦。
final String _script = kXiangqiScript.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  _leaveGuards();
  _undoGuards();
  _drawGuards();
  _resignAndEndGuards();
  _hostColorGuards();
  _setRulesGuards();
  _emptyRoomReclaimGuards();
  _moveGuards();
}

/// 截取指定函数块（从定义起，到下一个顶层 `on_` 定义）。
///
/// 边界切分必须在**原始**脚本上做（靠换行识别顶层定义），切完再折叠空白，
/// 这样断言既不受源码对齐空格影响，也不受换行丢失影响。
String _functionBlock(String marker) {
  final start = kXiangqiScript.indexOf(marker);
  expect(start, isNot(-1), reason: '脚本体必须含 $marker');
  final next = RegExp(
    r'\non_(?:action|join|leave|init)_\w+ = function',
  ).allMatches(kXiangqiScript.substring(start + 1));
  final block = next.isEmpty
      ? kXiangqiScript.substring(start)
      : kXiangqiScript.substring(start, start + 1 + next.first.start);
  return block.replaceAll(RegExp(r'\s+'), ' ');
}

void _leaveGuards() {
  group('kXiangqiScript on_leave 静态守卫：playing/ready 退出不终止', () {
    test('playing/ready 分支不再按 reason 分流，也无 host 销毁分支', () {
      final onLeave = _functionBlock('on_leave = function');
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      final playingBody = onLeave.substring(0, lobbyIdx);
      expect(
        playingBody,
        isNot(contains('p.reason == "disconnect"')),
        reason: '主动退出与断线同等对待',
      );
      expect(
        playingBody,
        isNot(contains('p.device_id == c.host_id')),
        reason: 'playing/ready 无 host 销毁分支',
      );
      expect(
        onLeave,
        contains('c.disconnected[p.device_id] = true'),
        reason: '离开必须标 disconnected（房间 alive 的核心信号）',
      );
    });

    test('on_leave 不销毁对局：无 ended / 无 force_leave / 不清棋谱', () {
      final onLeave = _functionBlock('on_leave = function');
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      final playingBody = onLeave.substring(0, lobbyIdx);
      expect(playingBody, isNot(contains('state = "ended"')));
      expect(playingBody, isNot(contains('c.status = "ended"')));
      expect(playingBody, isNot(contains('end_reason')));
      expect(onLeave, isNot(contains('c.force_leave')));
      expect(onLeave, isNot(contains('c.fen = nil')));
      expect(onLeave, isNot(contains('c.moves = {}')));
    });

    test('lobby 分支：guest 清槽；host 离开 → host_left_lobby', () {
      final onLeave = _functionBlock('on_leave = function');
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      expect(lobbyIdx, isNot(-1));
      final lobbyBody = onLeave.substring(lobbyIdx);
      expect(lobbyBody, contains('c.guest_id = nil'));
      expect(lobbyBody, contains('end_reason = "host_left_lobby"'));
    });

    test('离开清自己的挂起 offer（悔棋 + 求和）', () {
      final onLeave = _functionBlock('on_leave = function');
      expect(onLeave, contains('c.undo_offers[p.device_id] = nil'));
      expect(onLeave, contains('c.draw_offers[p.device_id] = nil'));
    });
  });
}

void _undoGuards() {
  group('kXiangqiScript 悔棋（UNDO）静态守卫', () {
    test('三 handler 已注册（definition.functions + 导出表）', () {
      expect(_script, contains('"on_action_UNDO_OFFER"'));
      expect(_script, contains('"on_action_UNDO_ACCEPT"'));
      expect(_script, contains('"on_action_UNDO_DECLINE"'));
      expect(_script, contains('on_action_UNDO_OFFER = on_action_UNDO_OFFER'));
      expect(
          _script, contains('on_action_UNDO_ACCEPT = on_action_UNDO_ACCEPT'));
      expect(
          _script, contains('on_action_UNDO_DECLINE = on_action_UNDO_DECLINE'));
      expect(_script, contains('UNDO_OFFER = "any"'));
      expect(_script, contains('UNDO_ACCEPT = "any"'));
      expect(_script, contains('UNDO_DECLINE = "any"'));
      expect(_script, contains('c.undo_offers = {}'));
    });

    test('MOVE entry 存 fen（UNDO_ACCEPT 回退恢复 c.fen 的唯一来源）', () {
      final moveBlock = _functionBlock('on_action_MOVE = function');
      expect(
        moveBlock,
        contains('fen = p.fen'),
        reason: 'moves entry 必须存走后 fen —— 悔棋 pop 后无它无法恢复局面',
      );
      expect(
        moveBlock,
        contains('c.undo_offers = {}'),
        reason: '走子必须清 undo_offers',
      );
    });

    test('UNDO_OFFER 前置门：n==0 / 非对局方 / 后手方 n<2', () {
      final block = _functionBlock('on_action_UNDO_OFFER = function');
      expect(block, contains('if n == 0 then'));
      expect(block, contains('not is_host and not is_guest'));
      expect(
        block,
        contains('host_is_first = ((c.host_color or "r") == (c.initial_side or "r"))'),
        reason: '先手方必须由 host_color == initial_side 推',
      );
      expect(block, contains('requester_is_first = (is_host == host_is_first)'));
      expect(block, contains('if (not requester_is_first) and n < 2 then'));
      expect(
        block,
        isNot(contains('if is_guest and n < 2 then')),
        reason: '旧版 guest 硬编码门槛必须移除',
      );
      expect(block, contains('c.undo_offers[p.device_id] = true'));
    });

    test('UNDO_ACCEPT：offer 校验 + 双 offer 互斥 + pop + fen 恢复', () {
      final block = _functionBlock('on_action_UNDO_ACCEPT = function');
      expect(block, contains('if c.undo_offers[c.guest_id] == true'));
      expect(block, contains('if c.undo_offers[c.host_id] == true'));
      expect(
        block,
        contains('if c.undo_offers[p.device_id] == true'),
        reason: '双方同时挂 offer 必须互斥作废',
      );
      expect(
        block,
        contains('requester_is_first = ((requester == c.host_id) == host_is_first)'),
      );
      expect(
        block,
        isNot(contains('requester_is_first = (requester == c.host_id)')),
        reason: '旧版硬编码 host 先手判据必须移除',
      );
      expect(block, contains('table.remove(c.moves)'));
      expect(block, contains('c.fen = c.moves[#c.moves].fen'));
      expect(block, contains('c.undo_offers = {}'));
      expect(block, contains('c.draw_offers = {}'));
      expect(block, contains('c.status = "playing"'));
    });

    test('UNDO_DECLINE 清对方 offer；RESET 清表', () {
      final decline = _functionBlock('on_action_UNDO_DECLINE = function');
      expect(decline, contains('c.undo_offers[c.guest_id] = nil'));
      expect(decline, contains('c.undo_offers[c.host_id] = nil'));

      final reset = _functionBlock('on_action_RESET = function');
      expect(reset, contains('c.undo_offers = {}'));
    });
  });
}

void _drawGuards() {
  group('kXiangqiScript 求和（DRAW）静态守卫', () {
    test('三 handler 已注册且权限为 any', () {
      expect(_script, contains('"on_action_DRAW_OFFER"'));
      expect(_script, contains('"on_action_DRAW_ACCEPT"'));
      expect(_script, contains('"on_action_DRAW_DECLINE"'));
      expect(_script, contains('DRAW_OFFER = "any"'));
      expect(_script, contains('DRAW_ACCEPT = "any"'));
      expect(_script, contains('DRAW_DECLINE = "any"'));
    });

    test('DRAW_OFFER：双方都挂 → 和棋终局（winner = nil）', () {
      final block = _functionBlock('on_action_DRAW_OFFER = function');
      expect(block, contains('c.draw_offers[p.device_id] = true'));
      expect(block, contains('c.status = "draw"'));
      expect(block, contains('c.end_reason = "agreement"'));
      expect(block, contains('c.winner = nil'));
      expect(block, contains('state = "ended"'));
    });

    test('DRAW_ACCEPT：必须对方已挂 offer 才生效', () {
      final block = _functionBlock('on_action_DRAW_ACCEPT = function');
      expect(block, contains('opponent_offered'));
      expect(block, contains('if not opponent_offered then'));
      expect(block, contains('c.status = "draw"'));
      expect(block, contains('c.end_reason = "agreement"'));
    });

    test('DRAW_DECLINE 清对方 offer；RESET 清表', () {
      final decline = _functionBlock('on_action_DRAW_DECLINE = function');
      expect(decline, contains('c.draw_offers[c.guest_id] = nil'));
      expect(decline, contains('c.draw_offers[c.host_id] = nil'));

      final reset = _functionBlock('on_action_RESET = function');
      expect(reset, contains('c.draw_offers = {}'));
    });
  });
}

void _resignAndEndGuards() {
  group('kXiangqiScript 认输 / 终局声明 静态守卫', () {
    test('RESIGN：认输方判负，winner = 对手，state = ended', () {
      final block = _functionBlock('on_action_RESIGN = function');
      expect(block, contains('c.status = "resigned"'));
      expect(block, contains('c.end_reason = "resign"'));
      expect(block, contains('c.winner = c.guest_id'));
      expect(block, contains('c.winner = c.host_id'));
      expect(block, contains('state = "ended"'));
      expect(
        _script,
        contains('RESIGN = "any"'),
        reason: '认输对任何一方开放',
      );
    });

    test('CLAIM_END：只接受 checkmate / stalemate，声明方获胜', () {
      final block = _functionBlock('on_action_CLAIM_END = function');
      expect(
        block,
        contains('reason == "checkmate" or reason == "stalemate"'),
        reason: '象棋终局只有将死 / 困毙两种',
      );
      expect(block, contains('c.status = "win"'));
      expect(block, contains('c.winner = p.device_id'));
      expect(block, contains('state = "ended"'));
      expect(
        _script,
        contains('CLAIM_END = "non_current_player"'),
        reason: '只有刚走完的一方能声明终局',
      );
    });

    test('RESET：仅 host、仅 ended、清空跨局状态', () {
      final block = _functionBlock('on_action_RESET = function');
      expect(block, contains('role_check(c, p, "RESET")'));
      expect(block, contains('if state ~= "ended" then'));
      expect(block, contains('c.moves = {}'));
      expect(block, contains('c.ready = {}'));
      expect(block, contains('c.chatRing = {}'));
      expect(block, contains('c.emojiRing = {}'));
      expect(block, contains('state = "lobby"'));
      expect(
        _script,
        contains('RESET = "host"'),
      );
    });
  });
}

void _hostColorGuards() {
  group('kXiangqiScript host_color 与 first_mover 解耦 静态守卫', () {
    test('on_init 读取 p.host_color 的 r / b / random 三分支', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('p.host_color'));
      expect(onInit, contains('p.host_color == "r"'));
      expect(onInit, contains('p.host_color == "b"'));
      expect(onInit, contains('p.host_color == "random"'));
      expect(onInit, contains('math.random(2)'));
      expect(onInit, contains('c.host_color = "r"'));
    });

    test('on_init 读取 p.first_mover（r / b）写入 c.initial_side', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('p.first_mover'));
      expect(onInit, contains('p.first_mover == "r"'));
      expect(onInit, contains('p.first_mover == "b"'));
      expect(onInit, contains('c.initial_side = p.first_mover'));
    });

    test('role_check 用 c.host_color 判 host（两处分支）', () {
      final roleCheck = _functionBlock('function role_check(c, p, action)');
      expect(roleCheck, contains('local host_side = c.host_color or "r"'));
      expect(
        RegExp('c\\.host_color or "r"').allMatches(roleCheck).length,
        greaterThanOrEqualTo(2),
        reason: 'current_player 与 non_current_player 分支都必须用 c.host_color',
      );
    });

    test('标准开局 FEN 常量一致（红先，轮次位 r）', () {
      final onInit = _functionBlock('on_init = function');
      expect(
        onInit,
        contains('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/'
            'RNBAKABNR r - - 0 1'),
      );
    });
  });
}

void _setRulesGuards() {
  group('kXiangqiScript SET_RULES 准备阶段改规则 静态守卫', () {
    test('on_action_SET_RULES 存在且仅 lobby/ready', () {
      final block = _functionBlock('on_action_SET_RULES = function');
      expect(block, contains('role_check(c, p, "SET_RULES")'));
      expect(block, contains('state ~= "lobby" and state ~= "ready"'));
      expect(block, contains('c.ready = {}'));
      expect(block, contains('state = "lobby"'));
    });

    test('on_init action_permissions 含 SET_RULES=host', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('SET_RULES = "host"'));
    });

    test('assembler 导出表含 on_action_SET_RULES', () {
      expect(_script, contains('on_action_SET_RULES'));
      expect(_script, contains('"on_action_SET_RULES"'));
    });
  });
}

void _emptyRoomReclaimGuards() {
  group('kXiangqiScript on_join 空房回收 静态守卫', () {
    test('三序：重连 → 空房回收 → 真满员拒绝', () {
      final block = _functionBlock('on_join = function');
      final reconnectIdx = block.indexOf('c.disconnected[p.device_id] = nil');
      final reclaimIdx = block.indexOf('local has_live = false');
      final rejectIdx = block.indexOf('c.rejected_join[p.device_id] = true');
      expect(reconnectIdx, isNot(-1));
      expect(reclaimIdx, isNot(-1));
      expect(rejectIdx, isNot(-1));
      expect(reconnectIdx, lessThan(reclaimIdx));
      expect(reclaimIdx, lessThan(rejectIdx));
    });

    test('回收仅限非对局态，playing/ready 座位留给断线重连', () {
      final block = _functionBlock('on_join = function');
      expect(
        block,
        contains('not has_live and (state == "lobby" or state == "ended")'),
      );
    });

    test('回收后新房主接管且清空幽灵座位 / 棋谱 / 跨局状态', () {
      final block = _functionBlock('on_join = function');
      expect(block, contains('c.host_id = p.device_id'));
      expect(block, contains('c.guest_id = nil'));
      expect(block, contains('c.moves = {}'));
      expect(block, contains('c.status = "playing"'));
      expect(block, contains('c.chatRing = {}'));
      expect(block, contains('state = "lobby"'));
    });
  });
}

void _moveGuards() {
  group('kXiangqiScript 服务端不变量 静态守卫', () {
    test('is_valid_xiangqi_fen 校验棋子数量与双方各一个将', () {
      final helper = _functionBlock('function is_valid_xiangqi_fen(fen)');
      expect(helper, contains('local caps = { K = 1, A = 2, B = 2, N = 2, R = 2, C = 2, P = 5 }'),
          reason: '数量上限表必须与服务端 is_valid_xiangqi_fen 一致');
      expect(helper, contains('if (counts["K"] or 0) ~= 1 then return false end'),
          reason: '红方必须恰好一个将（缺将 → 客户端立刻判 noGeneral → 秒判负）');
      expect(helper, contains('if (counts["k"] or 0) ~= 1 then return false end'),
          reason: '黑方必须恰好一个将');
      expect(
        helper,
        contains('if upper > cap or lower > cap then return false end'),
        reason: '数量上限是**每方**的（大写红 / 小写黑）必须分别比',
      );
    });

    test('CLAIM_END 要求至少走过一手（0 手不能宣布终局）', () {
      final block = _functionBlock('on_action_CLAIM_END = function');
      expect(
        block,
        contains('if #c.moves < 1 then'),
        reason: 'Lua 5.1 的 -1 % 2 == 1 会让 0 手时的 non_current_player 判给对侧，'
            '导致未走一步即可自称获胜',
      );
    });
  });

  group('kXiangqiScript MOVE 校验 静态守卫', () {
    test('MOVE 校验记号结构 + FEN 结构 + 轮次反证', () {
      final block = _functionBlock('on_action_MOVE = function');
      expect(block, contains('role_check(c, p, "MOVE")'));
      expect(block, contains('is_valid_xiangqi_move(p.uci)'));
      expect(block, contains('is_valid_xiangqi_fen(p.fen)'));
      expect(block, contains('local expect_side = side_to_move(c, #c.moves + 1)'));
      expect(
        block,
        contains('if fen_turn ~= expect_side then'),
        reason: '走完后 FEN 轮次位必须等于推定的下一手方',
      );
      expect(block, contains('uci = p.uci'));
      expect(block, contains('by = p.device_id'));
    });

    test('MOVE 权限表含 current_player', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('MOVE = "current_player"'));
    });

    test('is_valid_xiangqi_move 只接受 a-i + 0-9 的两段记号', () {
      final helper = _functionBlock('function is_valid_xiangqi_move(uci)');
      expect(helper, contains(r'^[a-i][0-9][a-i][0-9]$'));
      expect(
        helper,
        contains('uci:sub(1, 2) == uci:sub(3, 4)'),
        reason: '起点与终点不能相同',
      );
    });

    test('is_valid_xiangqi_fen 校验 10 段 + 每段 9 格 + 轮次 r/b', () {
      final helper = _functionBlock('function is_valid_xiangqi_fen(fen)');
      expect(helper, contains('#ranks ~= 10'));
      expect(helper, contains('width ~= 9'));
      expect(helper, contains('turn ~= "r" and turn ~= "b"'));
    });
  });
}
