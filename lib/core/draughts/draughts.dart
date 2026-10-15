/// 国际跳棋（International Draughts 10×10）模块
///
/// 提供：
///   · 数据模型：棋盘状态、棋子（兵/王）、走法（含多跳链）、终局状态
///   · 引擎：走法生成（flying king + 强制吃子 + 最长吃子裁决）、应用走法、终局判定
///   · 协议层：FEN / PDN 编解码 + 与 net_p2p v3 Lua 状态机集成的脚本
///
/// 棋盘 widget 在 `widgets/`；联机入口在 `lobby/` + `p2p/`。
/// 棋子皮肤本期不做 —— 棋盘配色走主题。
library;

export 'constants/draughts_constants.dart';
export 'models/piece.dart';
export 'models/board_state.dart';
export 'models/move.dart';
export 'models/game_status.dart';
export 'engine/move_generator.dart';
export 'engine/make_move.dart';
export 'engine/draughts_engine.dart';
export 'engine/pdn_codec.dart';
export 'lobby/draughts_lobby_spec.dart';
export 'p2p/script/draughts_script.dart';
