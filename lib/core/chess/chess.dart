/// 国际象棋 (Chess) 模块
///
/// 提供：
///   - 数据模型：棋盘状态、走法、终局状态
///   - 引擎：走法生成、攻击盘、FEN 编解码、应用走法、终局判定
///   - 协议层：与 net_p2p v3 Lua 状态机集成的脚本
///   - 皮肤合约：12 棋子 + 棋盘底图接口（占位 stub，待用户填资源）
///
/// 注意：本模块不含 UI / 棋子渲染 —— 棋子资产（皮肤）由 ui 层另行提供。
/// 颜色 / 主题色走 ColorStrategy（参见 context.chessColors）。
library;

export 'constants/chess_constants.dart';
export 'models/piece.dart';
export 'models/board_state.dart';
export 'models/move.dart';
export 'models/game_status.dart';
export 'engine/attack_map.dart';
export 'engine/move_generator.dart';
export 'engine/make_move.dart';
export 'engine/chess_engine.dart';
export 'engine/fen_codec.dart';
export 'p2p/chess_script.dart';
export 'skins/chess_skin.dart';
