# Game Kit Unification — 持久计划

> 四-phase 跨 fr + ve 仓库重构。Lua 联机游戏从 9 份复制代码收敛为「GameLobbyPage 类型驱动 + 皮肤/表情包管线 tags 化」。
> 任何会话恢复工作时先读本文件。

## Goal

消除 9 个 Lua 联机游戏入口页 ~1800 行复制代码，泛化皮肤与表情包两条资产管线，达成「新增联机游戏 = 一份 const 注册表」。

## Decisions Log

### 用户拍板（2026-09-04）
1. **入口 UX 节奏**：`smartMatch` 与 `dualEntry` 作为**一等 LobbyFlowType** 长期共存，UI 壳统一、UX 各自抽离（非临时开关）。
2. **chess 迁移**：迁 —— chess 变成 `GameLobbyPage(config+slots)` 实例，范本验证 API 完整性，删除 `chess_lobby_page.dart` 原件。
3. **身份通道**：GameLobbyPage 统一 `identityResolver` 注入接口；chess 续用 `ChessIdentity`，其余续用 `RelayDeviceId`，语义统一延后专项决策。
4. **emoji 首跑**：chess 首跑端到端验证；后续游戏只需拼协议段即可复用。

### 自决清单（用户可随时否决）
1. 共享层位置 `lib/core/game_kit/`（方案 b：core 独立目录）
3. 皮肤第二条线选 **gomoku**（黑/白子 + 棋盘底图 + 棋盘颜色自定义一起接）
4. EMOJI Lua 频控：每人最小间隔 ~1.5s + 服务端环形缓冲 16 条
5. 内置 unicode 兜底包：~24 个常用表情（项目禁 emoji 规则仅约束 ve UI 代码，不约束游戏贴图）
6. `GameDefinition.slug` 与 `kGameMeta` 字符级一致；双注册表不合并（slug 是唯一纽带）
7. cowrite 也纳入入口统一（按钮「进入协作」）
8. ve 侧验证标准：`pnpm lint` + showcase build 通过
9. reversi 内联 relayUrl 字面量收编进统一配置
10. 棋盘颜色自定义进通用换肤页，调色板角色作为每游戏注册项

### 提交策略
- 每 phase 收口一个 conventional commit（必要时按子任务拆）
- commit 前 `flutter analyze` + `flutter test` 全绿
- commit 后 push 到 GitHub，由 CI 跑 APK 构建（用户本地无 Java）
- `git status` 逐条确认改动归属，禁止 `add .` / `commit .`

## Architecture

```
lib/core/game_kit/                       ← 新增
├── game_definition.dart                 ← GameType + GameDefinition 注册表
├── lobby/
│   ├── game_lobby_spec.dart             ← GameLobbySpec + LobbyFlowType + LobbyCopy
│   ├── game_lobby_slots.dart            ← GameLobbySlots（可选插槽）
│   ├── game_lobby_page.dart              ← 通用壳（两种 flow 各自 widget）
│   └── game_lobby_identity.dart          ← IdentityResolver 接口 + RelayDeviceId/LoggedInUid 实现
├── room/                                 ← P4
└── emoji/
    ├── k_emoji_script_segment.dart      ← 共享 Lua 段 + 频控
    ├── lua_script_assembler.dart         ← 导出表自动生成（拼接 + handlers 列表）
    ├── emoji_pack_meta.dart              ← emoji_pack:index schema
    ├── emoji_bundle.dart                 ← 加载（common + per-game 索引 + unicode 兜底）
    └── emoji_overlay.dart                ← 浮动动画 + 表情面板
```

皮肤泛化：现有 `lib/core/chess/skins/` 的机制层（bundle/localizer/kv_reader/file_resolver/remote/local）抽到 `lib/core/game_kit/skin/`，`chess` 变成第一个注册实例。

## Naming Convention（tags 模型）

游戏维度塌缩为单个 `gameId` 字符串，其余命名全部派生：

| 层 | 派生规则 | chess 示例 | gomoku 示例 |
|---|---|---|---|
| 皮肤 KV key | `<game>_skin:index` | `chess_skin:index` | `gomoku_skin:index` |
| 皮肤 KV tag | `<game>-skin` | `chess-skin` | `gomoku-skin` |
| 皮肤 file key | `<path | `<game>/<skinId>/<pieceKey>` | `chess/...` | `gomoku/...` |
| 表情包 common KV | `emoji_common:index` | 同 | 同 |
| 表情包 game KV | `emoji_<game>:index` | `emoji_chess:index` | `emoji_gomoku:index` |
| 表情包 tag | `<scope>-emoji` | `common-emoji` / `chess-emoji` | `common-emoji` / `gomoku-emoji` |
| 表情包 file key | `emoji/<scope>/<emojiId>` | `emoji/chess/crown` | `emoji/gomoku/...` |
| 客户端缓存目录 | `<game>_skins` / `emojis/<scope>` | `chess_skins` | `gomoku_skins` |
| SharedPreferences key | `<game>_skin_id` | `chess_skin_id` | `gomoku_skin_id` |
| groupId | `190`（全游戏共享） | 190 | 190 |

ve 端对应：`game-skin-admin`（单组件 + 游戏切换器）、`emoji-pack-admin`（单组件 + scope 切换器），不再为每个游戏新建目录。

## Phases

### Phase 1：入口页统一（立即开工）

**子任务：**
1. [ ] **1.0 scaffolding**：创建 `lib/core/game_kit/` 目录；定义 `GameType` enum + `GameDefinition` + `GameLobbySpec` + `LobbyFlowType`(enum: smartMatch/dualEntry) + `LobbyCopy` + `GameLobbySlots` + `IdentityResolver` 接口
2. [ ] **1.1 GameLobbyPage 壳**：smartMatch 渲染器 + dualEntry 渲染器（两个 `_buildSmartMatchEntry` / `_buildDualEntryEntry` 私有方法），共同壳（Scaffold/AppBar/actionsBuilder/snapshot 门/error mapping/409 区分/loading 过渡/alias sync）
3. [ ] **1.2 chess 迁移**：写 `chess_lobby_spec.dart`（host/guest/执子/残局）+ slots（configPageBuilder + endgame chip + actionsBuilder + initialParamsBuilder）；改 `chess_online_demo.dart` 用 `GameLobbyPage`；删 `chess_lobby_page.dart` + `chess_room_config_page.dart`（config page 整体作 slot 闭包移走？—— 决定：保留 `ChessRoomConfigPage` 不动，slot 引用之）
4. [ ] **1.3 8 Lua 游戏批量迁移**：gomoku / go / jungle / surround / tetris / reversi / coup / cowrite，每个写一份 `xxx_lobby_spec.dart` const + 改 demo 用 `GameLobbyPage` + 删旧 widgets（每个文件 ~200 行）→ 一个 commit
5. [ ] **1.4 team_card 迁移**：team_card 形态特殊（随机号按钮 + 入房后 snapshot 驱动 config），用 slots 表达；可能需要新增一个 `randomCodeButton` 插槽
6. [ ] **1.5 收口**：reversi 内联 relayUrl 字面量收编进 spec；flutter analyze + flutter test；commit + push + gh-ci-monitor

### Phase 2：皮肤系统泛化

**子任务：**
1. [ ] 抽 `lib/core/game_kit/skin/` 机制层（bundle/localizer/meta/remote/local/kv_reader/file_resolver）
2. [ ] `GameSkinSpec.forGame(gameId)`：所有命名派生
3. [ ] chess skins 改为注册实例（KV key/cache dir/prefs key 全部不变 → 零回归）
4. [ ] 通用 `GameSkinSettingsPage`（列表+预览+棋盘颜色自定义，调色板角色由 spec 声明）
5. [ ] 上传脚本 `add_skin.py --game <id>` 参数化（PIECE_KEYS/tag 前缀/KV key/文件名）
6. [ ] ve `game-skin-admin`：抽 `useSkinAdmin(config)` 工厂 + GAME_SKIN_REGISTRY + scope 切换器
7. [ ] gomoku 第二条线验证（棋盘渲染接入贴图 + BoardPalette 调色板声明）
8. [ ] flutter analyze + ve pnpm lint + showcase build；commit + push

### Phase 3：表情包通路

**子任务：**
1. [ ] `kEmojiScriptSegment`（共享 Lua 段，含频控 + 环形缓冲）
2. [ ] `LuaScriptAssembler`：从 handlers 列表自动生成导出表（解决当前「手写 return」痛点）
3. [ ] chess script 改走 assembler + 拼 emoji 段 + chess 首跑端到端
4. [ ] `EmojiBundle.forGame('chess')`（加载 common + chess 索引）
5. [ ] `EmojiOverlay`（seq 去重 + 浮动动画）+ 表情面板 + AppBar 表情按钮
6. [ ] 内置 unicode 兜底包（~24 个）
7. [ ] ve `emoji-pack-admin`（单组件 + scope 切换器）
8. [ ] 用 `.tool/relay-room-tester` 验证两个客户端收发
10. [ ] flutter analyze + pnpm lint + showcase build；commit + push

### Phase 4：对局页插槽 `GameRoomShell`（最重，单独 phase）

**作用域**：存量 9 个对局页不强迁；新游戏强制用壳；chess_room_page.dart 单独专项迁移。Phase 4 拆分独立 plan 子文件。

## Conventions

- **常量文件**：模块内常量统一 `const_xxxx.dart`（flutter-work-flow rule 4）
- **文件解耦**：方案 b（`lib/core/<模块>` 多文件）适用于 game_kit 等高度可扩展模块；方案 a（`lab/demos/<模块>/`）适用于单个 demo 内超过 400 行
- **颜色通道**：入口页统一走 `Theme.of(context).colorScheme` + `context.colors`，**不再每游戏各挂 BoardTheme/chessColors**（顺手消灭主题不一致）
- **测试**：现有 chess 入口有测试，迁移时沿用；GameLobbyPage 至少覆盖 409 映射/双入口/snapshot 门/smartMatch 流程

## Status

**Phase 1 COMPLETE** (CI 验证中)：

- ✅ **1.0 scaffolding** —— `lib/core/game_kit/lobby/` 5 文件：identity / spec / slots / page / form
- ✅ **1.1 GameLobbyPage 壳** —— smartMatch + dualEntry 两个一等 LobbyFlowType 渲染器
- ✅ **1.2 chess 迁移** —— const spec + slots builder；删 chess_lobby_page.dart（576 行）；PR commit 1
- ✅ **1.3 8 Lua 游戏批量迁移** —— gomoku/go/jungle/tetris/surround/reversi/coup/cowrite，每个 const spec + demo rewire；删 LobbyEntryPage 复制（每游戏 ~200 行）；PR commit 2
- ✅ **1.4 team_card 迁移** —— random code 按钮（`LobbyCopy.randomCodeEnabled` 内置支持）+ `onHostNeedsConfig` via `slots.onStartedExtras`；删除 demo 内的旧 LobbyEntryPage（259 行）
- ✅ **1.5 收口** —— `trailingEntry` 插槽接线（cowrite 弃用 Column 绕过）；`LobbyStartedCtx.extras` 改 mutable（handler 写入不抛 const-modify 异常）；`LobbyOnStartedExtrasBuilder` 签名加 `RoomHandle` 参数；smartMatch 也调 onStartedExtras；删除 `test/core/chess/p2p/chess_lobby_page_test.dart`

**PR #88** 已开启跟踪（commits: `3b65d5a9` chess, `cfc229fa` 8-game + cleanup）。Chess commit CI run #33853584296 **PASSED**；全量提交 CI 验证中。

**API 扩展（迁移过程中确认为必要）**：
- `LobbyStartedCtx.extras` 改 non-const ctor —— handler 写入 `ctx.extras['key'] = value` 不抛 `Cannot modify unmodifiable Map`
- `LobbyOnStartedExtrasBuilder` 加 `RoomHandle` 参数 —— handler 可读 `handle.latest`（snapshot）+ `handle.transport.deviceId` 做服务端权威判断
- `GameLobbyPage._goSmartMatch` 也调 `onStartedExtras`（原本仅 dualEntry 调）—— smartMatch 流也支持 ctx 注入（needsConfig / isHostSide 等）

**Phase 2 待开工**：皮肤泛化（fr GameSkinSpec + ve game-skin-admin）。等用户拍板。