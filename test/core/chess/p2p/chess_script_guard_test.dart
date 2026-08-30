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
import 'package:xiaodouzi_fr/core/chess/p2p/chess_script.dart';

void main() {
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