// test/core/xiangqi/p2p/xiangqi_can_perform_test.dart
//
// XiangqiRoom.canPerform —— 客户端按钮可点性的**唯一真相源**。
//
// 权限表由服务端 Lua 的 `c.action_permissions` 维护（服务端权威），
// 客户端只读不改；本测试锁死「规则词 → 按钮可点性」的映射，
// 防止与 Lua `role_check` 判反（v8 同款坑：host 未必先手时判反）。
//
// 与 chess / draughts 的同款 helper 保持同构（规则词词表一致）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/xiangqi_room.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot;

Snapshot _snap({
  String hostId = 'host',
  String? guestId = 'guest',
  String hostColor = 'r',
  String initialSide = 'r',
  int moves = 0,
  Map<String, String>? permissions,
}) {
  return Snapshot(
    roomCode: 'TEST',
    scriptHash: 'h',
    state: 'playing',
    version: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    history: const [],
    context: {
      'host_id': hostId,
      if (guestId != null) 'guest_id': guestId,
      'host_color': hostColor,
      'initial_side': initialSide,
      'status': 'playing',
      'moves': List.filled(moves, {'uci': 'b0e2'}),
      'action_permissions': permissions ??
          {
            'ACK': 'any',
            'DEAL': 'host',
            'SET_RULES': 'host',
            'MOVE': 'current_player',
            'RESIGN': 'any',
            'DRAW_OFFER': 'any',
            'UNDO_OFFER': 'any',
            'CLAIM_END': 'non_current_player',
            'RESET': 'host',
          },
    },
  );
}

void main() {
  group('XiangqiRoom.actionPermissions', () {
    test('从 snapshot.context 读服务端权限表', () {
      final s = _snap();
      final perms = XiangqiRoom.actionPermissions(s);
      expect(perms['DEAL'], 'host');
      expect(perms['MOVE'], 'current_player');
      expect(perms['RESIGN'], 'any');
    });

    test('没有权限表时返回空表（不崩）', () {
      final s = Snapshot(
        roomCode: 'T',
        scriptHash: 'h',
        state: 'lobby',
        version: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        history: const [],
        context: const {},
      );
      expect(XiangqiRoom.actionPermissions(s), isEmpty);
    });
  });

  group('XiangqiRoom.canPerform —— any / host', () {
    test('any：双方都能', () {
      final s = _snap();
      expect(XiangqiRoom.canPerform('RESIGN', s, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('RESIGN', s, isHost: false), isTrue);
    });

    test('host：仅房主', () {
      final s = _snap();
      expect(XiangqiRoom.canPerform('DEAL', s, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('DEAL', s, isHost: false), isFalse);
      expect(XiangqiRoom.canPerform('RESET', s, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('RESET', s, isHost: false), isFalse);
    });

    test('未知 action：放行（权限表里没有 = 服务端不拦）', () {
      final s = _snap();
      expect(XiangqiRoom.canPerform('WHATEVER', s, isHost: false), isTrue);
    });
  });

  group('XiangqiRoom.canPerform —— current_player / non_current_player', () {
    test('红先（host 执红 = 先手）：0 手 → 轮到 host', () {
      final s = _snap(moves: 0);
      expect(
        XiangqiRoom.canPerform('MOVE', s, isHost: true),
        isTrue,
        reason: 'host 是先手方 → 0 手时轮 host',
      );
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: false), isFalse);
      // 刚走完的一方 = 非当前走子方 → CLAIM_END 归 guest
      expect(XiangqiRoom.canPerform('CLAIM_END', s, isHost: true), isFalse);
      expect(XiangqiRoom.canPerform('CLAIM_END', s, isHost: false), isTrue);
    });

    test('1 手后 → 轮到 guest（CLAIM_END 归 host）', () {
      final s = _snap(moves: 1);
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: true), isFalse);
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: false), isTrue);
      expect(XiangqiRoom.canPerform('CLAIM_END', s, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('CLAIM_END', s, isHost: false), isFalse);
    });

    test('host 执黑（host_color=b）时先手方是 guest —— 判据必须翻转', () {
      // host_color = 'b'，initial_side = 'r' → 先手方是 guest，不是 host。
      // 0 手 → 轮先手方（guest）→ host 不能 MOVE。
      final s = _snap(hostColor: 'b', initialSide: 'r', moves: 0);
      expect(
        XiangqiRoom.canPerform('MOVE', s, isHost: true),
        isFalse,
        reason: 'host 执黑时先手方是 guest —— 硬编码「n 偶 → 轮 host」会判反',
      );
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: false), isTrue);
    });

    test('黑先残局（initial_side=b, host 执红）：先手方是 guest', () {
      // initial_side='b' → 黑先；host 执红 → host 是**后手方**。
      // 0 手 → 轮 guest（先手方）→ host 不能 MOVE。
      final s = _snap(hostColor: 'r', initialSide: 'b', moves: 0);
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: true), isFalse);
      expect(XiangqiRoom.canPerform('MOVE', s, isHost: false), isTrue);
      // 1 手后轮到 host（红）。
      final s1 = _snap(hostColor: 'r', initialSide: 'b', moves: 1);
      expect(XiangqiRoom.canPerform('MOVE', s1, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('MOVE', s1, isHost: false), isFalse);
    });
  });

  group('XiangqiRoom.isHost / isGuest', () {
    test('按 device_id 判别，未知 id 回退 false', () {
      final s = _snap();
      expect(XiangqiRoom.isHost(s, 'host'), isTrue);
      expect(XiangqiRoom.isHost(s, 'guest'), isFalse);
      expect(XiangqiRoom.isHost(s, 'nobody'), isFalse);
      expect(XiangqiRoom.isGuest(s, 'guest'), isTrue);
      expect(XiangqiRoom.isGuest(s, 'host'), isFalse);
    });

    test('null 快照 / 空 id → false（不抛）', () {
      expect(XiangqiRoom.isHost(null, 'host'), isFalse);
      expect(XiangqiRoom.isGuest(null, 'guest'), isFalse);
      expect(XiangqiRoom.isHost(_snap(guestId: null), 'guest'), isFalse);
    });
  });
}
