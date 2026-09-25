// lib/core/sudoku/p2p/sudoku_net.dart
//
// 数独联机的 action 编码与快照解码辅助。
//
// 编码：把 Dart 对象 → Lua 端可接收的 payload（通过 relay_v3 transport 的
// applyAction 机制）。
// 解码：从快照 context 提取 puzzle / solution / state 等。

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

class SudokuNet {
  static const String kActionSetPuzzle = 'SET_PUZZLE';
  static const String kActionAck = 'ACK';
  static const String kActionStart = 'START';
  static const String kActionProgress = 'PROGRESS';
  static const String kActionSubmit = 'SUBMIT';

  /// Host 推送题目（SET_PUZZLE）。服务端校验 puzzle/solution 长度 + 值域 +
  /// 兼容性后写入 ctx；后续 START 需要 puzzle != nil。
  static Future<Snapshot> sendSetPuzzle(
    RoomHandle handle, {
    required List<int> puzzle,
    required List<int> solution,
    required int seed,
    required String difficulty,
  }) {
    return handle.applyAction(
      type: kActionSetPuzzle,
      params: {
        'puzzle': puzzle,
        'solution': solution,
        'seed': seed,
        'difficulty': difficulty,
      },
    );
  }

  /// 准备 ACK（对齐 chess）：lobby 阶段点"准备好了"。
  /// 双方都 ACK 后服务端把 state 推到 ready，host 才能 START。
  static Future<Snapshot> sendAck(RoomHandle handle) {
    return handle.applyAction(type: kActionAck, params: const {});
  }

  /// Host 通知双方开始（START）。前提：双方已 ACK（ready）+ puzzle 已推送。
  static Future<Snapshot> sendStart(RoomHandle handle) {
    return handle.applyAction(type: kActionStart, params: const {});
  }

  /// 实时进度上报（PROGRESS）。playing 状态下填数/擦除后 fire-and-forget，
  /// 服务端写 ctx.progress[device_id] = {filled, errors}，对手进度条据此渲染。
  /// 失败不影响本地对局（调用方自行吞异常）。
  static Future<Snapshot> sendProgress(
    RoomHandle handle, {
    required int filled,
    required int errors,
  }) {
    return handle.applyAction(
      type: kActionProgress,
      params: {'filled': filled, 'errors': errors},
    );
  }

  /// 任意一方提交答案（SUBMIT）。服务端对照 solution 全 81 格校验；
  /// 全对 → 记录 elapsed_ms/errors + 第一个提交的作为 winner + 切 ended。
  static Future<Snapshot> sendSubmit(
    RoomHandle handle, {
    required List<int> values,
    required int elapsedMs,
    required int errors,
  }) {
    return handle.applyAction(
      type: kActionSubmit,
      params: {
        'values': values,
        'elapsed_ms': elapsedMs,
        'errors': errors,
      },
    );
  }
}
