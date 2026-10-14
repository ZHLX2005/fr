// lib/core/game_kit/lobby/game_enter_transition.dart
//
// 游戏页「进入对局界面」刷子过渡控制器。
//
// 时机规范（v2）：刷子不在「匹配完成 / push 对局页」时播 —— 那时双方还在
// 准备链里（等待对手 → host 配置 → 双方准备）。真正的进入时刻是页面内
// 准备态（lobby/ready/…）首次切到 playing：
//   匹配完成 → host 配置完成 → 双方准备好 → 进入游戏界面，刷子在此刻出现。
//
// 用法：游戏页持有实例，**每份快照到达后**调用 [update]：
//   · 准备态 → 对局：根 Overlay 播一次刷子（铺满 → 揭开），返回门控 Future
//     （揭开完成后 resolve）。实时游戏（俄罗斯方块等）用它推迟引擎/计时
//     —— 「完成 transition 再开始」，双端都等同一过渡，起跑线一致。
//   · 对局 → 准备态（RESET 再来一局）：重新武装，下次进入再播。
//   · 对局 → 对局（对局中快照刷新 / 断线恢复）：不重播。
//   · 首次 update 即在对局（断线后重进进行中的房间）：不播 —— 准备链没有
//     发生过，此时盖屏只会白罚实时游戏一次起跑。
//   · keepArmed（斗兽棋 waiting = 对局中等待重连）：离开对局视图但不重新
//     武装，重连回 playing 不重播；若 ready 阶段就掉线进 waiting，武装保留，
//     真正 playing 时仍会播。
//
// Overlay 插入被推迟到微任务：快照回调可能在 initState 里同步应用首份
// latest 快照（sudoku/chess），Overlay.of 的祖先查找必须等本次同步 build
// 结束才安全；快照回调路径上微任务先于下一帧排空，盖罩不会漏帧。

import 'dart:async';

import 'package:flutter/material.dart';

import 'brush_wipe_overlay.dart';

final class GameEnterTransition {
  bool _seenFirst = false;
  bool _wasInGame = false;
  bool _armed = true;

  /// 页面级切换控制器（team_card/cowrite：只在切入口调 [update]，不走
  /// 快照流）在 initState 调用 —— 声明「页面从准备态开始」，让首次
  /// update(inGame: true) 正常触发盖屏（否则会被「首次即对局 = 重连」
  /// 规则跳过）。
  void markPrep() {
    _seenFirst = true;
    _wasInGame = false;
    _armed = true;
  }

  /// 每份快照后调用。[inGame] = 当前是否处于对局界面（绝大多数游戏即
  /// `state == 'playing'`）。
  ///
  /// 从准备态首次进入时触发刷子过渡并返回门控 Future；其余情况返回 null
  /// （调用方可安全忽略）。
  Future<void>? update(
    BuildContext context,
    bool inGame, {
    bool keepArmed = false,
  }) {
    // 从未见过准备态就直落对局（重连中途进入）→ 视同「已在对局」，不播。
    final was = _seenFirst ? _wasInGame : true;
    _seenFirst = true;
    _wasInGame = inGame;
    if (!inGame) {
      if (!keepArmed) _armed = true;
      return null;
    }
    if (was || !_armed) return null;
    _armed = false;
    final done = Completer<void>();
    scheduleMicrotask(() {
      if (!context.mounted) {
        // 页面已销毁：直接放行门控，不阻塞引擎/计时启动。
        done.complete();
        return;
      }
      try {
        // underCover 无事可做：页面自身已随快照 setState 切到对局视图，
        // 遮罩只负责「盖住 → 等新视图画完 → 揭开」。
        runBrushWipeTransition(context: context, underCover: () async {})
            .whenComplete(done.complete);
      } catch (_) {
        // 过渡失败不能阻塞游戏开始。
        done.complete();
      }
    });
    return done.future;
  }
}
