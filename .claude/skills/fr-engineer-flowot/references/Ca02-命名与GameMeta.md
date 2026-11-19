---
name: Ca02-命名与GameMeta
description: FR 联机 demo 命名与 kGameMeta 登记契约——title（联机）后缀、slug 与 kGameMeta 字符级一致、GameCategory/mode 选类与已踩反例。在 lib/lab/demos 下新增联机房间业务并登记游戏中心时读。
---

# naming-and-game-meta — 联机 demo 命名与 kGameMeta 登记契约

> 本 ref 是 [[C00-RelayLua路由]] 的**联机 demo 命名与登记契约**页。
> 任何在 `lib/lab/demos/<game>_lua*/` 下新增 v3 联机房间业务，都要先过本契约：
> demo `title` 怎么写、slug 怎么对、`kGameMeta` 怎么加、`GameCategory` 怎么选。
>
> 是 [[Cb01-双人对战房间模板]]（端到端模板）落地前的**命名/分类环节**——和
> [[Cc01-团队卡牌大厅模式]]（多人派对分类示例）配套使用。
>
> **何时读**：在 `lib/lab/demos/<game>_lua*/` 下新增联机房间业务、需要定 `title`/`slug` 并向 `kGameMeta` 登记分类时。

---

## 1. 命名规则：`title` 后缀

| 业务类型 | `DemoPage.title` 格式 | 示例 |
|---|---|---|
| **联机（Relay v3 Lua 状态机）** | `'<游戏名>（联机）'` | `'五子棋（联机）'`、`'斗兽棋（联机）'` |
| 本地双人对战 | `'<游戏名>'`（无后缀） | `'围追堵截'`、`'黑白翻转棋（旧）'` |
| 单人（街机 / 益智 / 音游） | `'<游戏名>'`（无后缀） | `'2048'`、`'贪吃蛇'`、`'线'` |

**强制约束**：

- 联机 demo **禁止**用 `（Lua）` / `（lua）` / `在线` / `v3` / `v2` 等后缀
  - 这些后缀暴露实现细节（"Lua"指 v3 状态机；"v3"指协议版本），用户不需要
  - 历史遗留的 `（Lua）` / `v3` 已在 2026-08-30 全部统一为 `（联机）`
- `（联机）` 是一致的产品语义（"走 Relay 服务端的互联网对战"），与底层技术无关
- 唯一例外：业务已经有更准确的前缀（"互联网对战"、"团队协作"）时，可以用业务词
  - 但本项目内目前**所有联机 demo 一律 `（联机）`**，保持一致

**AppBar 同步**：demo 内部 `AppBar.title` / `ChessLobbyPage(title:...)` 也要用相同文本，
避免同一游戏出现两个不同名字。

---

## 2. slug 契约：与 `kGameMeta` 字符级一致

```dart
class MyGameLuaDemo extends DemoPage {
  @override
  String get slug => 'my-game-lua';   // ← 这个 key
}

// const_game_center.dart
const Map<String, GameMeta> kGameMeta = {
  'my-game-lua': GameMeta(...),       // ← 必须字符级一致
};
```

**失配后果**：`gameMetaOf(slug)` 走 `kFallbackGameMeta`（街机 · 单人 · 灰板），
游戏中心会显示**错误的分类 + 错误的图标 + 错误的渐变**，但不会崩。

**发现失配的检查**：

```bash
flutter analyze lib/lab/ lib/screens/profile/lab/
# 看 GameMeta 的 key 列表，对照 demo 的 slug
```

---

## 3. `GameCategory` 选类契约

`kGameMeta` 的 `categories` 是 `Set<String>`，**多归属**是常态：

| 业务类型 | 必含 | 通常还加 | 例子 |
|---|---|---|---|
| 联机双人对战棋 | `multiplayer` | `board` | 五子棋、围棋、围追堵截、斗兽棋、国际象棋、黑白翻转棋 |
| 联机派对（多角色） | `multiplayer` | `party` | 团建卡牌、政变 |
| 联机街机（实时比拼） | `multiplayer` | `arcade` | 俄罗斯方块 |
| 协作（无胜负） | `multiplayer` | — | 协作笔记（cowrite-lua 暂未登记 kGameMeta） |
| 本地双人对战 | — | `board` / `party` | 围追堵截、斗兽棋、黑白翻转棋（旧） |
| 单人益智 / 街机 / 音游 | — | 对应单类 | 2048、贪吃蛇、线 |

**强制规则**：

- 联机 demo **必须**含 `GameCategory.multiplayer`，否则不会出现在「联机」tab
- 棋游加 `board`、派对加 `party`、街机加 `arcade` —— 帮助过滤发现，但不强制

**新增分类**（极少发生）需同步改 3 处：

1. `GameCategory` 加 `static const String`（lib/screens/profile/lab/game_center/`const_game_center.dart` 的 `GameCategory` 定义（按符号检索，行号会漂移））
2. `kGameCategoryTabs` 加一项（决定 tab 顺序）
3. `kGameCategoryIcons` 加一个 `IconData` + `kGameCategoryLabels` 加一个标签

---

## 4. `mode` 标签契约

| 标签 | 含义 | 例子 |
|---|---|---|
| `'联机双人'` | 1v1 互联网对战 | 五子棋、围棋、斗兽棋、国际象棋、黑白翻转棋、围追堵截、俄罗斯方块 |
| `'联机多人'` | 2-6 人互联网对战 | 团建卡牌、政变 |
| `'本地双人'` | 同一设备双人对战 | 围追堵截（本地）、斗兽棋（本地）、黑白翻转棋（旧） |
| `'单人'` | 一个人玩 | 2048、贪吃蛇、线 |

`mode` 文字出现在卡片角标，与 `categories: {multiplayer}` 联动——
联机 demo 不要用 `'本地双人'`，反之亦然。

---

## 5. 添加新联机 demo：登记步骤（指针）

**登记机制的唯一事实源在《A05-游戏中心扩展》§加新游戏**——kGameMeta 条目位置与排序、tab 归类、4 处必改，都到那里执行。本契约只约束联机 demo 的命名/分类落点：

1. `title` 带 `（联机）` 后缀，并同步 `AppBar.title` / lobby 页标题（§1）
2. `slug` 与 `kGameMeta` key **字符级一致**，失配 = 静默 fallback 灰板（§2）
3. `categories` 必含 `multiplayer`；`mode` 用 `'联机双人'` / `'联机多人'`（§3/§4）
4. `gradient` 用本游戏**视觉识别色**，不复用本地版渐变——同游戏本地/联机必须一眼可区分（§6 反例）

---

## 6. 反例（已踩过）

| 错误 | 后果 | 正确做法 |
|---|---|---|
| `title => '五子棋（Lua）'` | 用户看到"Lua"不知道是啥；与"围追堵截（Lua）"风格不统一 | `'五子棋（联机）'` |
| `title => '团建卡牌 v3'` | 暴露 v3 协议版本；用户不在乎 | `'团建卡牌（联机）'` |
| `title => '俄罗斯方块'` | 看不出是联机版（与本地版同名） | `'俄罗斯方块（联机）'` |
| `kGameMeta` 漏登记 jungle-chess-lua | 游戏中心 fallback 到"街机·单人·灰板" | 必须按 slug 加条目 |
| `gradient` 复用本地版（如 jungle-chess 0xFF92400E / 0xFFD97706） | 联机/本地视觉难区分 | 联机版用**同色族但不同明度**：0xFF7C2D12 / 0xFFB45309（更暗红棕） |
| `categories: {GameCategory.board}` 给联机 demo | "联机" tab 看不到 | 必含 `multiplayer` |
| `mode: '本地双人'` 给联机 demo | 卡片角标误导 | 用 `'联机双人'` / `'联机多人'` |

---

## 7. 检查脚本（手动）

```bash
# 列所有联机 demo 的 title / slug
grep -rn "title =>" lib/lab/demos/*_lua_demo.dart lib/lab/demos/reversi_demo.dart lib/lab/demos/chess_online_demo.dart

# 列 kGameMeta 所有 key
grep -nE "^\s+'[a-z-]+':" lib/screens/profile/lab/game_center/const_game_center.dart

# diff：任何 demo slug 缺 kGameMeta 条目 = fallback
flutter analyze lib/lab/ lib/screens/profile/lab/
```

**对照表**（2026-08-30 当前状态）：

> 注：以下为 2026-08-30 快照；联机条目持续新增（chess/draughts/go 等已 lobby spec 化），现状以 lib/screens/profile/lab/game_center/const_game_center.dart 的 kGameMeta 为准，命名落地由 core/game_kit/lobby/ 各 *_lobby_spec.dart 承接。

| slug | title | 联机分类 | 备注 |
|---|---|---|---|
| `surround-game-lua` | 围追堵截（联机） | multiplayer + board | |
| `gomoku-lua` | 五子棋（联机） | multiplayer + board | |
| `go-lua` | 围棋（联机） | multiplayer + board | |
| `team-card-lua` | 团建卡牌（联机） | multiplayer + party | |
| `tetris-lua` | 俄罗斯方块（联机） | multiplayer + arcade | |
| `coup-lua` | 政变（联机） | multiplayer + party | |
| `reversi-lua` | 黑白翻转棋（联机） | multiplayer + board | |
| `chess-online` | 国际象棋（联机） | multiplayer + board | |
| `jungle-chess-lua` | 斗兽棋（联机） | multiplayer + board | 2026-08-30 新增 |

> 通用交付门槛见 [[C00-RelayLua路由]] 动线收尾。
