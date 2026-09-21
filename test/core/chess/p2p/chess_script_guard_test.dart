// test/core/chess/p2p/chess_script_guard_test.dart
//
// kChessScript 静态守卫测试 —— 客户端无法嵌 Lua VM，对脚本源码做防回归断言。
//
// 守卫对象：on_leave 的 playing/ready 分支，核心语义（v4 修订，id47）：
//   · playing/ready 内任何一方离开（无论 reason 是 disconnect 还是主动退出）
//     → 一律视为暂时离线：房间保持 alive（不销毁、不清槽位/局面），
//       只标 c.disconnected[id] = true，等同一 device_id 重连恢复
//       （on_join 清 disconnected 复用原玩家）。
//   · host 主动退出不再销毁房间（旧 v3 的 ended + force_leave guest 已废除）；
//     僵尸房由服务端房间 TTL（4404 room expired）回收。
//   · lobby 内 guest 离开 → 清 guest 槽；host 离开 → 空房销毁（host_left_lobby，
//     无对局进行，语义合理保留）。
//
// 回归目标：曾修过「host 短暂断网超过服务端 5s grace → on_leave(reason=
// "disconnect") 无条件销毁房间」的 bug（v3）；v4 进一步废除「host 主动退出
// 终止整局」（id47：退出按钮不得回调房间终止 action）。本守卫确保两者不再复现。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/script/chess_script.dart';

void main() {
  _undoGuards();
  _v5HostColorGuards();
  _v6FirstMoverGuards();
  _v7SetRulesGuards();
  group('kChessScript on_leave 静态守卫：playing/ready 退出不终止（v4, id47）', () {
    test('playing/ready 分支不再按 reason 分流，也无 host 销毁分支', () {
      final onLeave = _onLeaveBlock();
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      final playingBody = onLeave.substring(0, lobbyIdx);
      // v4：playing/ready 内 host/guest 一律按暂时离线处理，不再判 reason。
      expect(
        playingBody,
        isNot(contains('p.reason == "disconnect"')),
        reason: 'v4 废除 reason 分流 —— 主动退出与断线同等对待',
      );
      expect(
        playingBody,
        isNot(contains('p.device_id == c.host_id')),
        reason: 'v4 废除 playing/ready 的 host 销毁分支（id47；lobby 空房分支除外）',
      );
      // 暂时离线标记必须在（on_join 同 device_id 重连时清除 → 恢复在线）。
      expect(
        onLeave,
        contains('c.disconnected[p.device_id] = true'),
        reason: '离开必须标 disconnected（房间 alive 的核心信号）',
      );
    });

    test('on_leave 全函数不得销毁对局：无 ended（对局中）/ 无 force_leave', () {
      final onLeave = _onLeaveBlock();
      // playing/ready 不再出现 ended；唯一 ended 在 lobby 空房分支。
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      final playingBody = onLeave.substring(0, lobbyIdx);
      expect(
        playingBody,
        isNot(contains('state = "ended"')),
        reason: 'playing/ready 离开不得结束房间',
      );
      expect(
        playingBody,
        isNot(contains('c.status = "ended"')),
        reason: 'playing/ready 离开不得置 status=ended',
      );
      expect(
        playingBody,
        isNot(contains('end_reason')),
        reason: 'playing/ready 离开不产生任何终局原因（对局仍在进行）',
      );
      expect(
        onLeave,
        isNot(contains('c.force_leave')),
        reason: 'v4 废除踢人 —— 对方只看到「暂时离线」提示',
      );
      // 不清权威局面（断线/离开后重连可恢复）。
      expect(onLeave, isNot(contains('c.fen = nil')));
      expect(onLeave, isNot(contains('c.moves = {}')));
    });

    test('lobby 分支保留空房语义：guest 清槽；host 离开 → host_left_lobby', () {
      final onLeave = _onLeaveBlock();
      final lobbyIdx = onLeave.indexOf('elseif state == "lobby"');
      expect(lobbyIdx, isNot(-1), reason: 'lobby 分支保留');
      final lobbyBody = onLeave.substring(lobbyIdx);
      expect(lobbyBody, contains('c.guest_id = nil'),
          reason: 'lobby guest 离开清 guest 槽');
      expect(lobbyBody, contains('end_reason = "host_left_lobby"'),
          reason: 'lobby host 离开销毁空房（无对局，合理）');
    });

    test('ended 分支保留：离开标 disconnected、局面保留供回顾', () {
      final onLeave = _onLeaveBlock();
      final endedIdx = onLeave.indexOf('elseif state == "ended"');
      expect(endedIdx, isNot(-1), reason: 'ended 分支保留');
      final endedBody = onLeave.substring(endedIdx);
      expect(endedBody, contains('c.disconnected[p.device_id] = true'));
    });
  });
}

/// 截取 on_leave 函数块（从函数定义起，到下一个顶层 `on_` 定义为止），
/// 供上面的断言限定在本函数内。
String _onLeaveBlock() {
  return _functionBlock('on_leave = function');
}

void _undoGuards() {
  group('kChessScript 悔棋（UNDO）静态守卫', () {
    test('三 handler 已注册（definition.functions + 导出表）', () {
      expect(
        kChessScript,
        contains('"on_action_UNDO_OFFER"'),
        reason: 'definition.functions 必须注册 UNDO_OFFER（服务端按表派发）',
      );
      expect(kChessScript, contains('"on_action_UNDO_ACCEPT"'));
      expect(kChessScript, contains('"on_action_UNDO_DECLINE"'));
      expect(kChessScript, contains('on_action_UNDO_OFFER = on_action_UNDO_OFFER'));
      expect(kChessScript, contains('on_action_UNDO_ACCEPT = on_action_UNDO_ACCEPT'));
      expect(kChessScript, contains('on_action_UNDO_DECLINE = on_action_UNDO_DECLINE'));
      // action_permissions 声明为 any（对局双方均可发起）。
      expect(kChessScript, contains('UNDO_OFFER = "any"'));
      expect(kChessScript, contains('UNDO_ACCEPT = "any"'));
      expect(kChessScript, contains('UNDO_DECLINE = "any"'));
      expect(kChessScript, contains('c.undo_offers = {}'),
          reason: 'on_init 必须初始化 undo_offers');
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
        reason: '走子必须清 undo_offers（offer 挂起时对方走子 → 请求失效）',
      );
    });

    test('UNDO_OFFER 前置门：n==0 拒绝 + 非对局方拒绝 + 后手方 n<2 拒绝（v8 先手方修正）', () {
      final block = _functionBlock('on_action_UNDO_OFFER = function');
      expect(block, contains('if n == 0 then'), reason: '零走法无从悔棋');
      expect(block, contains('not is_host and not is_guest'),
          reason: '只认对局双方');
      // v8：先手方判据 = host_color == initial_side（host 未必先手）。
      // 旧版 `if is_guest and n < 2` 硬编码 guest 后手，guest 先手时第一手
      // 悔棋被误挡 —— 守卫确保新判据存在且旧写法不再回归。
      expect(block, contains('host_is_first = ((c.host_color or "w") == (c.initial_side or "w"))'),
          reason: '先手方必须由 host_color == initial_side 推（v5 解耦语义）');
      expect(block, contains('requester_is_first = (is_host == host_is_first)'),
          reason: '请求方先手身份 = 是否 host ⊕ host 是否先手方');
      expect(block, contains('if (not requester_is_first) and n < 2 then'),
          reason: '仅后手方要求 n>=2（先手方 n>=1 即可悔棋）');
      expect(block, isNot(contains('if is_guest and n < 2 then')),
          reason: '旧版 guest 硬编码门槛必须移除（guest 先手时误挡）');
      expect(block, contains('c.undo_offers[p.device_id] = true'),
          reason: '校验通过才挂 offer');
    });

    test('UNDO_ACCEPT：显式 offer 校验 + 双 offer 互斥 + pop 循环 + fen 恢复', () {
      final block = _functionBlock('on_action_UNDO_ACCEPT = function');
      expect(block, contains('if c.undo_offers[c.guest_id] == true'),
          reason: 'host 接受 → 校验 guest 挂的 offer');
      expect(block, contains('if c.undo_offers[c.host_id] == true'),
          reason: 'guest 接受 → 校验 host 挂的 offer');
      expect(
        block,
        contains('if c.undo_offers[p.device_id] == true'),
        reason: '双方同时挂 offer 必须互斥作废（回退手数取决于请求方，歧义不回退）',
      );
      // v8：pop 数量必须按"host_color == initial_side 推先手方"，不得硬编码
      // `requester == c.host_id` 为先手（host 执黑时 pop 数算反，悔棋回退错局面）。
      expect(
        block,
        contains('host_is_first = ((c.host_color or "w") == (c.initial_side or "w"))'),
        reason: '先手方判据必须由 host_color == initial_side 推',
      );
      expect(
        block,
        contains('requester_is_first = ((requester == c.host_id) == host_is_first)'),
        reason: '请求方先手身份 = 是否 host ⊕ host 是否先手方',
      );
      expect(
        block,
        isNot(contains('requester_is_first = (requester == c.host_id)')),
        reason: '旧版硬编码 host 先手判据必须移除',
      );
      expect(block, contains('table.remove(c.moves)'),
          reason: '必须 pop moves（悔棋核心动作）');
      expect(
        block,
        contains('c.fen = c.moves[#c.moves].fen'),
        reason: 'fen 从 pop 后最后一手的走后快照恢复',
      );
      expect(block, contains('c.undo_offers = {}'), reason: '生效后清 undo_offers');
      expect(block, contains('c.draw_offers = {}'), reason: '生效后清 draw_offers');
      expect(block, contains('c.status = "playing"'), reason: '回退后状态复位');
    });

    test('UNDO_DECLINE 清对方 offer；on_leave 清自己的 offer；RESET 清表', () {
      final decline = _functionBlock('on_action_UNDO_DECLINE = function');
      expect(decline, contains('c.undo_offers[c.guest_id] = nil'));
      expect(decline, contains('c.undo_offers[c.host_id] = nil'));

      final onLeave = _onLeaveBlock();
      expect(
        onLeave,
        contains('c.undo_offers[p.device_id] = nil'),
        reason: '离开必须清自己的悔棋 offer（与 draw_offers 同款）',
      );

      final reset = _functionBlock('on_action_RESET = function');
      expect(reset, contains('c.undo_offers = {}'),
          reason: '重开必须清悔棋 offers');
    });
  });
}

/// 截取指定函数块（从定义起，到下一个顶层 `on_` 定义或脚本尾部 export 表）。
/// 守卫测试用：限定断言不跨函数误伤。
String _functionBlock(String marker) {
  final start = kChessScript.indexOf(marker);
  expect(start, isNot(-1), reason: '脚本体必须含 $marker');
  final next = RegExp(
    r'\non_(?:action|join|leave|init)_\w+ = function',
  ).allMatches(kChessScript.substring(start + 1));
  if (next.isEmpty) {
    return kChessScript.substring(start);
  }
  return kChessScript.substring(start, start + 1 + next.first.start);
}

void _v5HostColorGuards() {
  group('kChessScript v5 host_color 与 first_moker 解耦 静态守卫', () {
    test('on_init 必须读取 p.host_color 并写入 c.host_color（不再写 c.initial_side）', () {
      final onInit = _functionBlock('on_init = function');
      // host_color 读取分支（'w' / 'b' / 'random'）。
      expect(onInit, contains('p.host_color'),
          reason: 'on_init 必须读取 initial_params.host_color');
      expect(onInit, contains('p.host_color == "w"'),
          reason: 'white 分支必须存在');
      expect(onInit, contains('p.host_color == "b"'),
          reason: 'black 分支必须存在');
      expect(onInit, contains('p.host_color == "random"'),
          reason: 'random 分支必须存在');
      expect(onInit, contains('math.random(2)'),
          reason: 'random 必须靠 math.random(2) 建房瞬间掷筛');
      // v5 关键：host_color 与 first_moker 解耦 —— c.host_color 是独立字段，
      // c.initial_side 不再被 requested 覆盖。
      expect(onInit, contains('c.host_color = "w"'),
          reason: 'c.host_color 字段必须存在并默认 "w"');
      expect(
        onInit,
        isNot(contains('c.initial_side = requested')),
        reason: 'v5 已废弃把 host_color 当 initial_side 的写法',
      );
    });

    test('initial_side 必须从 FEN 第 2 字段推（first_moker = 棋规），不再被 host_color 翻转', () {
      final onInit = _functionBlock('on_init = function');
      expect(
        onInit,
        contains('fields[2] == "b"'),
        reason: '原 FEN side 推导从 6 字段第 2 字段取（c.initial_side 来源）',
      );
      expect(
        onInit,
        isNot(contains('c.initial_fen = fen_flip(c.initial_fen)')),
        reason: 'v5 不再因 host_color 强翻转残局 FEN —— host 可执后手',
      );
      expect(
        onInit,
        isNot(contains('if requested == "b" then')),
        reason: 'v5 fallback FEN 不再镜像 —— 标准开局无论 host_color 是什么都保持白先',
      );
    });

    test('fallback FEN：标准开局保留 "w KQkq"，不再镜像黑方先手', () {
      final onInit = _functionBlock('on_init = function');
      expect(
        onInit,
        contains('"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"'),
        reason: 'fallback 标准开局字符串保留（白先，与 v3/v4 一致）',
      );
    });

    test('role_check current_player 必须用 c.host_color 而非 c.initial_side 判 host', () {
      final roleCheck = _functionBlock('function role_check(c, p, action)');
      expect(roleCheck, contains('local host_side = c.host_color or "w"'),
          reason: 'role_check 必须从 c.host_color 读 host 执子色（v5 关键修复）');
      expect(
        roleCheck,
        isNot(contains('c.initial_side or "w"')),
        reason: 'v5 已废弃 role_check 用 c.initial_side 判 host',
      );
    });

    test('role_check non_current_player 同样用 c.host_color 判 host', () {
      final roleCheck = _functionBlock('function role_check(c, p, action)');
      // 两处 c.host_color or "w" —— current_player + non_current_player 各一次
      expect(
        RegExp('c\\.host_color or "w"').allMatches(roleCheck).length,
        greaterThanOrEqualTo(2),
        reason: 'current_player 与 non_current_player 分支都必须用 c.host_color',
      );
    });

    test('fen_flip helper 仍存在（备用），但不调用', () {
      expect(kChessScript, contains('function fen_flip(fen)'),
          reason: 'fen_flip helper 保留供未来扩展（v5 当前不调用）');
    });
  });
}

void _v6FirstMoverGuards() {
  group('kChessScript v6 first_mover 显式参数 静态守卫', () {
    test('on_init 必须读取 p.first_mover 并写入 c.initial_side（残局强制覆盖）', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('p.first_mover'),
          reason: 'on_init 必须读取 initial_params.first_mover');
      expect(onInit, contains('p.first_mover == "w"'),
          reason: 'first_mover 白先分支必须存在');
      expect(onInit, contains('p.first_mover == "b"'),
          reason: 'first_mover 黑先分支必须存在');
      expect(
        onInit,
        contains('c.initial_side = p.first_mover'),
        reason: '服务端信任 client 显式 first_mover → 写入 c.initial_side',
      );
    });

    test('未传 first_mover 时（向后兼容）从 FEN 第 2 字段推', () {
      final onInit = _functionBlock('on_init = function');
      // p.first_mover 缺省时仍走 FEN 推导路径
      expect(onInit, contains('fields[2] == "b"'),
          reason: 'first_mover 缺省兑底路径：FEN 第 2 字段推导');
    });
  });
}

void _v7SetRulesGuards() {
  group('kChessScript v7 SET_RULES 准备阶段改规则 静态守卫', () {
    test('on_action_SET_RULES 存在且仅 lobby/ready', () {
      final block = _functionBlock('on_action_SET_RULES = function');
      expect(block, contains('role_check(c, p, "SET_RULES")'));
      expect(block, contains('state ~= "lobby" and state ~= "ready"'));
      expect(block, contains('c.ready = {}'));
      expect(block, contains('state = "lobby"'));
    });

    test('on_init action_permissions 含 SET_RULES=host', () {
      final onInit = _functionBlock('on_init = function');
      expect(onInit, contains('SET_RULES  = "host"'));
    });

    test('assembler 导出表含 on_action_SET_RULES', () {
      expect(kChessScript, contains('on_action_SET_RULES'));
      expect(kChessScript, contains('"on_action_SET_RULES"'));
    });
  });
}
