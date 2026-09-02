// lib/core/chess/p2p/chess_script.dart
//
// 国际象棋的 net_p2p v3 Lua 状态机脚本（v5：生命周期物理拆分）。
//
// ## v5 架构
//
// Lua 脚本按职责拆成 3 段，物理独立为 3 个文件，入口在这里拼接：
//
//   chess_script.dart            ← 本文件：const String kChessScript 入口
//   chess_script_lifecycle.dart  ← helpers + on_init/on_join/on_leave/state 机
//   chess_script_actions.dart    ← 所有 on_action_* handler + 导出表
//
// ## 拼接顺序（严格）
//
// 拼接顺序：lifecycle → actions。
// · Lua 全局查找发生在调用时而非定义时 —— helper / on_init / on_join /
//   on_leave 在 actions handler 调用时必须已定义。
// · 导出表 `return { definition, on_init, ... }` **绝对放最后一段**：
//   relay 服务端按导出表派发 handler；handler 写在 return 表里而非顶层全局
//   会触发 CreateRoom 400（见 net-p2p-protocol-playbook）。
// · 每段 const String 末尾必须以 `\n` 结尾，保持 `_functionBlock` regex
//   块边界（\non_(?:action|join|leave|init)_\w+ = function）稳定。
//
// ## 与 v4 的核心语义变化
//
// v4 把 `c.initial_side = requested`（requested 是 host_color），导致 host
// 选 'b' 时 role_check 误判 host 为先手方（与棋规冲突）。
//
// v5 解耦为两个字段：
//   c.host_color   = host 执子色（'w'/'b'/'random'→掷筛）—— 用户决策
//   c.initial_side = FEN 第 2 字段（first_moker；棋规本身）
// 先手方是谁：host_color == initial_side ? host : guest。
// role_check 用 c.host_color 而非 c.initial_side 判"走子方是不是 host"。
//
// 残局 FEN 不再被翻转 —— host 选 'b' + 黑先残局 → host 执黑且是后手方
// （guest 执白且先走）。这才是用户要的"host 选后手"语义。
//
// ## 角色权限（action_permissions）
//
//   ACK         = "any"               双方都可在 lobby 阶段点准备
//   DEAL        = "host"              双方 ACK 后由 host 显式开局
//   MOVE        = "current_player"    轮到谁走谁走
//   RESIGN      = "any"               任何一方任何时候都能投
//   DRAW_*      = "any"               议和流程任意一方发起
//   UNDO_*      = "any"               悔棋流程任意一方发起
//   CLAIM_END   = "non_current_player"  刚走完的一方声明将杀/僵局
//   RESET       = "host"              终局后 host 可重开

import 'chess_script_actions.dart' show kChessScriptActions;
import 'chess_script_lifecycle.dart' show kChessScriptLifecycle;

/// 国际象棋 Lua 脚本（v5）。在 net_p2p v3 的 RelayV3Transport.createRoom()
/// 创建一个对弈房时传入 —— 服务端按 sha256 缓存。
///
/// 拼接顺序：lifecycle（helpers + on_init/on_join/on_leave/state 机）
/// → actions（所有 on_action_* + 导出表）。段间 `'\n'` 保持 regex 块边界。
const String kChessScript = '$kChessScriptLifecycle\n$kChessScriptActions\n';
