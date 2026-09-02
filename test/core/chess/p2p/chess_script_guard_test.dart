// test/core/chess/p2p/chess_script_guard_test.dart
//
// kChessScript 静态守卫测试 —— 客户端无法嵌 Lua VM，对脚本源码做防回归断言。
//
// 守卫对象：on_leave 的 playing/ready 分支，核心语义（v3 修复）：
//   · p.reason == "disconnect"（host 或 guest，WS 5s grace 超时触发）
//     → 一律视为瞬态断线：房间保持 alive（不销毁、不清 host_id/guest_id/
//       fen/moves），只标 c.disconnected[id] = true，等同一 device_id 重连
//       （on_join 清 disconnected 复用原玩家）。
//   · host 非断线离开（graceful / kicked / room_evicted）→ 才销毁房间
//     （state="ended" + force_leave guest）。
//
// 回归目标：曾修过「host 短暂断网超过服务端 5s grace → 服务端触发
// on_leave(reason="disconnect") → 旧逻辑无条件销毁房间（host 分支不看
// reason），导致 host 想重连但房间已没」。本守卫确保该 bug 不再复现。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/script/chess_script.dart';

void main() {
  _undoGuards();
  _v5HostColorGuards();
  group('kChessScript on_leave 静态守卫：断线不销毁房间', () {
    test('playing/ready 分支存在 disconnect 判因，且先于 host 销毁分支', () {
      final onLeave = _onLeaveBlock();
      // 1. 判因分支存在（host/guest 一律按 reason 分流）。
      expect(
        onLeave,
        contains('p.reason == "disconnect"'),
        reason: 'playing/ready 必须先按 reason 分流：disconnect = 瞬态断线',
      );
      // 2. host 销毁分支仍在，且必须位于 disconnect 判因之后（被 gate 住）。
      final disconnectIdx = onLeave.indexOf('p.reason == "disconnect"');
      final hostIdx = onLeave.indexOf('elseif p.device_id == c.host_id');
      expect(disconnectIdx, isNot(-1), reason: 'disconnect 判因存在');
      expect(hostIdx, isNot(-1), reason: 'host 销毁分支仍存在（graceful/kicked 才触发）');
      expect(
        disconnectIdx,
        lessThan(hostIdx),
        reason: 'disconnect 分支必须先于 host 销毁分支 —— host 断线不得进入销毁路径',
      );
    });

    test('disconnect 分支内不销毁房间、不清槽位 / 局面', () {
      final onLeave = _onLeaveBlock();
      final disconnectIdx = onLeave.indexOf('p.reason == "disconnect"');
      final hostIdx = onLeave.indexOf('elseif p.device_id == c.host_id');
      final disconnectBody = onLeave.substring(disconnectIdx, hostIdx);

      // 不置 ended / status=ended（房间保持 alive 等重连）。
      expect(
        disconnectBody,
        isNot(contains('state = "ended"')),
        reason: '断线不得结束房间',
      );
      expect(
        disconnectBody,
        isNot(contains('c.status = "ended"')),
        reason: '断线不得置 status=ended',
      );
      // 不清 host/guest 槽，不清权威局面 fen/moves。
      expect(
        disconnectBody,
        isNot(contains('c.host_id = nil')),
        reason: 'host 断线不清 host 槽（否则同 device_id 重连会失去房主身份）',
      );
      expect(
        disconnectBody,
        isNot(contains('c.guest_id = nil')),
        reason: '断线不清 guest 槽',
      );
      expect(
        disconnectBody,
        isNot(contains('c.fen = nil')),
        reason: '断线不清棋局权威局面 fen',
      );
      expect(
        disconnectBody,
        isNot(contains('c.moves = {}')),
        reason: '断线不清走法记录 moves',
      );
      // 断线必须标 disconnected（on_join 同 device_id 重连时清除 → 恢复在线）。
      expect(
        disconnectBody,
        contains('c.disconnected[p.device_id] = true'),
        reason: '断线标记 disconnected（房间 alive 的核心信号）',
      );
    });

    test('host 非断线（graceful）仍销毁：state="ended" + force_leave guest 保留', () {
      final onLeave = _onLeaveBlock();
      final hostIdx = onLeave.indexOf('elseif p.device_id == c.host_id');
      final hostBody = onLeave.substring(hostIdx);
      expect(
        hostBody,
        contains('state = "ended"'),
        reason: 'host 显式离开（非断线）仍销毁房间 —— 与 v1 语义一致',
      );
      expect(
        hostBody,
        contains('c.force_leave'),
        reason: '销毁时踢走 guest（其 WS 收 4403 + on_leave("kicked")）',
      );
    });
  });
}

/// 截取 on_leave 函数块（从函数定义起），供上面的断言限定在本函数内。
String _onLeaveBlock() {
  final start = kChessScript.indexOf('on_leave = function');
  expect(start, isNot(-1), reason: '脚本体必须含 on_leave');
  return kChessScript.substring(start);
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

    test('UNDO_OFFER 前置门：n==0 拒绝 + 非对局方拒绝 + 黑方 n<2 拒绝', () {
      final block = _functionBlock('on_action_UNDO_OFFER = function');
      expect(block, contains('if n == 0 then'), reason: '零走法无从悔棋');
      expect(block, contains('if is_guest and n < 2 then'),
          reason: '黑方一手未走无从悔棋');
      expect(block, contains('not is_host and not is_guest'),
          reason: '只认对局双方');
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
