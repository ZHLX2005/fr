// lib/core/chess/lobby/chess_lobby_spec.dart
//
// chess 的 GameLobbySpec + GameLobbySlots 实例。
//
// 用 GameLobbyPage 替代原 ChessLobbyPage，行为零变化：
//   · 双入口（创建/加入）
//   · snapshot 门控 onStarted
//   · 建房配置页（host_color/first_mover）
//   · 残局 chip（formExtras 插槽注入）
//   · ChessIdentity（登录 uid 优先）身份通道
//   · AppBar 残局库 + 换肤按钮（actionsBuilder 插槽）

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../endgame/chess_endgame.dart';
import '../p2p/chess_identity.dart';
import '../p2p/chess_room_config_page.dart';
import '../p2p/script/chess_script.dart';

/// chess 专属 IdentityResolver —— 包装 ChessIdentity.resolve()（登录 uid 优先）。
class _ChessIdentityResolver implements GameIdentityResolver {
  const _ChessIdentityResolver();

  @override
  Future<String> resolve() => ChessIdentity.resolve();
}

/// chess 入口 spec const。
const GameLobbySpec kChessLobbySpec = GameLobbySpec(
  gameId: 'chess',
  title: '国际象棋（联机）',
  heroIcon: Icons.meeting_room_outlined,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: 'http://47.110.80.47:8988',
  script: kChessScript,
  maxPlayers: 2,
  flow: LobbyFlowType.dualEntry,
  identityResolver: _ChessIdentityResolver(),
  copy: LobbyCopy(
    primaryBtnText: '创建房间',
    secondaryBtnText: '加入房间',
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText:
        '与朋友约定同一房间号："创建房间"是房主，"加入房间"是后到者。',
    aliasFieldHint: '如：小白',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 构造 chess 用的 GameLobbySlots。
///
/// 两个外部依赖通过闭包注入：
///   · [initialEndgame] —— 残局快照（建房时注入 initial_fen）
///   · [onClearEndgame] —— 残局 chip 的 X 按钮回调
///   · [actionsBuilder] —— AppBar actions（残局库 / 换肤）
GameLobbySlots buildChessLobbySlots({
  required ChessEndgameSnapshot? initialEndgame,
  required VoidCallback onClearEndgame,
  required LobbyActionsBuilder actionsBuilder,
}) {
  return GameLobbySlots(
    // 创建房间前置配置页（chess: 执子角色 + first_mover）
    configPageBuilder: (context, {required data}) async {
      final cfg = await Navigator.of(context).push<ChessRoomConfig>(
        MaterialPageRoute(
          builder: (ctx) => ChessRoomConfigPage(
            alias: data.alias,
            code: data.code,
            endgame: initialEndgame,
            relayUrl: kChessLobbySpec.relayUrl,
            onSubmit: (cfg) => Navigator.of(ctx).pop(cfg),
          ),
        ),
      );
      if (cfg == null) return null;
      final params = <String, dynamic>{
        'host_color': cfg.hostColor,
      };
      if (cfg.guestColor != null) {
        params['guest_color'] = cfg.guestColor;
      }
      params['first_mover'] = cfg.firstMover;
      return params;
    },
    // 残局 FEN 注入（formExtras 渲染 chip 时也在用同一个 initialEndgame）
    initialParamsBuilder: (data, cfg) {
      if (initialEndgame == null) return const {};
      return {'initial_fen': initialEndgame.fen};
    },
    // 残局 chip（房间号字段之后插入）
    formExtras: (context) {
      if (initialEndgame == null) return const [];
      return [_EndgameChip(
        label: initialEndgame.label ?? '快照',
        onClear: onClearEndgame,
      )];
    },
    // AppBar 残局库 + 换肤
    actionsBuilder: actionsBuilder,
  );
}

/// 残局 chip —— 显示当前选中的残局名 + X 清除按钮。
///
/// 颜色走 context.chessColors.lightSquare（chess 入口块色，入口页唯一保留的棋盘色通道）。
class _EndgameChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const _EndgameChip({required this.label, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.chessColors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.lightSquare.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.extension_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '残局：$label',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}