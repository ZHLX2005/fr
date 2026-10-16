# 国际跳棋（International Draughts 10×10）联机版 — 实施计划

日期：2026-10-15 · 范围：**规则引擎 + Relay v3 Lua 联机**（不做本地 / 不做 AI）

## 目标

在 lab 游戏中心新增「国际跳棋（联机）」，与既有 `chess-online` / `jungle-chess-lua`
同构：本地权威规则引擎 + Relay v3 Lua 状态机做服务端权威棋谱。

## 规则基线（International / FMJD）

- 10×10 棋盘，仅 50 深色格；每方 20 子占前 4 行；**白先**。
- 兵斜进 1 格；**吃子可前可后**。王（flying）斜行任意距离，隔任意距离吃、自选落点。
- **强制吃子** + **最长吃子规则**（必须吃最多子）。
- 多跳链：被吃子整手结束才移除；同一子不可被跳两次。
- 升王：走完停对方底线；但若还能继续吃，必须继续吃、不升王。
- 和棋：三重复局面 / 王对王。

## 内部坐标约定（三份参考里最干净的一种）

- 内部 `(row, col)` 0-based；格子索引 `row*10 + col`；可用格 `(row+col)%2 == 1`。
- 对外方格号 1–50（PDN/FEN 用）：`square = row*5 + col~/2 + 1`。
- FEN：`<turn>:W<squares>:B<squares>`，如 `W:W31-50:B1-20`。
- PDN 着法：`32-28`（走）/ `32x23`（吃，多跳 `32x23x14`）。

> 参考 pydraughts 用 1–50 + 行列奇偶补偿，几何极易出错；本项目改用 (row,col) 直算，
> 只在 FEN/PDN 边界换算编号。

## 交付物

### 阶段 1 — 引擎核心 `lib/core/draughts/`
| 文件 | 内容 |
|---|---|
| `constants/draughts_constants.dart` | 尺寸、4 个斜向、编号↔坐标映射、初始布局 |
| `models/piece.dart` | `DraughtsPiece`（color, isKing）+ pack/unpack |
| `models/move.dart` | `DraughtsMove`（from/to/path/capturedSquares/isPromotion） |
| `models/board_state.dart` | 不可变棋盘（`List<int?>` 100）+ copyWith |
| `models/game_status.dart` | 进行中 / 白胜 / 黑胜 / 和 |
| `engine/move_generator.dart` | 兵/王走法、flying king、吃子链 DFS、最长吃子裁决 |
| `engine/make_move.dart` | 应用走法、整手末移除被吃子、升王判定 |
| `engine/draughts_engine.dart` | facade：legalMoves / applyMove / status |
| `engine/pdn_codec.dart` | FEN + PDN 读写 |
| `draughts.dart` | barrel export |

### 阶段 2 — 联机（Relay v3 Lua）
| 文件 | 内容 |
|---|---|
| `p2p/script/draughts_script_lifecycle.dart` | on_init/on_join/on_leave + role_check |
| `p2p/script/draughts_script_actions.dart` | ACK / DEAL / MOVE / RESIGN / CLAIM_END / RESET |
| `p2p/script/draughts_script.dart` | 经 `assembleLuaScript` 装配（+ emoji 段） |
| `lobby/draughts_lobby_spec.dart` | `kDraughtsLobbySpec`（GameLobbySpec const） |
| `p2p/draughts_room_page.dart` | 房间页：棋盘 + 准备/走子/认输 |

### 阶段 3 — demo + 游戏中心登记 ✅ 2026-10-15
| 文件 | 内容 |
|---|---|
| `lib/core/draughts/lobby/draughts_lobby_spec.dart` | `kDraughtsLobbySpec`（smartMatch） |
| `lib/lab/demos/draughts_lua_demo.dart` | `DraughtsLuaDemo`（slug `draughts-lua`，type game） |
| `lib/lab/lab_bootstrap.dart` | `registerDraughtsLuaDemo()` |
| `lib/screens/profile/lab/game_center/const_game_center.dart` | `kGameMeta` 加一条 |
| `lib/core/game_kit/game_center_catalog.dart` | `kGameCenterCatalog` 加一条 |
| 延期 | KV 目录发布（`publish_game_center_index`）——本地 token 401，需人工 `kvcli auth login` 后再发；不影响进游戏中心对局（程序化封面） |

### 阶段 4 — 测试 `test/core/draughts/`
- 走法生成：兵单步 / 王 flying 滑动
- 吃子：单吃 / 多跳链 / 最长吃子裁决 / 不可跳两次
- 升王边界（能继续吃则不升）
- FEN / PDN 往返
- 终局：无子 / 无着

## 关键取舍

1. **自研引擎**（不引 `draughts_engine` pub 包）：与 chess/jungle 同构、可控、无外部 license 风险。
2. **服务端权威棋谱**：MOVE 只追加 `history`，胜负由客户端引擎判定后 `CLAIM_END` 上报（对齐 chess_v5）。
3. **不做本地/AI**：按用户决策。

## 验证

- `flutter analyze`（CI 会跑）
- `flutter test test/core/draughts/`
- 手动：双端建房 → 准备 → 走子 → 吃子链 → 终局
