/// 中国象棋（Xiangqi / Chinese Chess 9×10）模块
///
/// 提供：
///   · 数据模型：棋盘状态、棋子（七子）、走法（起点-终点记号）、终局状态
///   · 引擎：走法生成（蹩马腿 / 塞象眼 / 炮架 / 将帅照面）、应用走法、终局判定
///   · 协议层：FEN 编解码 + 与 net_p2p v3 Lua 状态机集成的脚本
///
/// 棋盘 widget 在 `widgets/`（棋盘线 CustomPaint + 棋子 SVG）；
/// 联机入口在 `lobby/` + `p2p/`。
/// 棋子为**纯 SVG 绘制**（汉字字形烘焙为矢量 path，见 widgets/xiangqi_piece_glyphs.dart）。
library;

export 'constants/xiangqi_constants.dart';
export 'models/piece.dart';
export 'models/board_state.dart';
export 'models/move.dart';
export 'models/game_status.dart';
export 'engine/move_generator.dart';
export 'engine/make_move.dart';
export 'engine/fen_codec.dart';
export 'engine/xiangqi_engine.dart';
export 'lobby/xiangqi_lobby_spec.dart';
export 'p2p/script/xiangqi_script.dart';
