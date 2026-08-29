# 子 ref C：当前颜色用法审计（color 用得最多的目录是哪些）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文是**迁移完整度快照**：残留 hex 归属、Top 热点、目录用色规模、迁移历史。
> 数据基于 v6.2 重构（5 strategy 拆出）+ tetris 特例修正（commit 24d91ea1，2026-08-29）+ **v6.2.1 新增 ChessColorStrategy（第 6 个 strategy）** 后的快照。
> 改/评审任何目录前查此表判断迁移完整度。架构/数据流见 [[architecture]]，改动 SOP 见 [[extension]]，特例业务写法见 [[special-cases]]。

## 0. 迁移状态：✅ v6.2.1（5→6 strategy 通道 + chess 占位）

**5 批迁移 + v6.2 收尾 + v6.2 特例修正 + v6.2.1 新增 ChessColorStrategy 全部落地**
（124 处豁免 + 65 处迁移 + 86 处 BoardTheme 令牌 + 2 处特例 strategy + **1 处新增 strategy 通道**）。

### v6.2.1 关键变化（chess 新通道）
- `lib/core/theme/tokens/color/chess/chess.dart`（13 角色 + *From() 派生）
- `lib/core/theme/colors/strategy/chess_color_strategy/`（13 角色抽象 + Default 实现 + 单例缓存）
- `lib/core/theme/extensions/chess_color_strategy_extension.dart`（注入器）
- `lib/widgets/context_chess_colors.dart`（`context.chessColors` 快捷入口，双层兜底）
- `lib/core/theme/colors/factory.dart` 注册 `createChessColorStrategy`
- `lib/core/theme/app_theme.dart` `_buildTheme` 注入 6 个 strategy（5→6）
- **测试**：`test/core/theme/chess_color_strategy_test.dart`（12 个回归断言：单例缓存、派生正确性、==/hashCode）
- **审计**：本表 §2 加 chessColors 一节（消费点 0 个，等待用户棋子 UI 接入）

### v6.2 关键变化
- `lib/core/theme/colors/strategy/`（5 strategy 独立目录，替代原 `lib/core/theme/strategy/`）
- `lib/core/theme/tokens/color/theme/<mode>.dart`（5 主题色板独立文件，替代原 `semantic/colors.dart`）
- 5 strategy：ColorStrategy / BoardColorStrategy / **TetrisColorsStrategy（特例）** / **TeamAvatarStrategy（特例）** / **TorchProtectStrategy（scheme 派生）**
- 5 消费通道：context.colors / context.boardColors / **context.tetrisColors** / **context.teamAvatar** / **context.torchProtect**

### tetris 特例修正（commit 24d91ea1）
- 根因：v6.2 重构把 pieceColors 改 `List<Color>` 0..6 + 从 scheme 派生 → L 块 type 7 越界 + 1..6 颜色错位 + 棋盘环境跟主题漂移
- 修法：4 角色全 native const + pieceColors 改 `Map<int, Color>` 1..7 + `DefaultTetrisColorsStrategy` 不参与派生 + shouldRepaint 还原 `=> true`
- 新增 15 个回归测试（`test/lab/tetris_lua/`，本地 .gitignore）：7 色 hex 逐项断言 + 越界保护 + 跨主题锁定

当前 `lib/` 内所有残留 `Color(0xFF...)` 均已分类：

| 分类 | 数量 | 说明 |
| --- | --- | --- |
| **S 令牌系统** | 86 | surround_game (54) + reversi (32) 的 `BoardThemeData` 独立令牌，与 `context.boardColors` 平级 |
| **E 豁免** | 124 | 全部带 `主题豁免` 注释（品牌色/国际识别色/纸质书视觉/医学解剖色/sage 家族…） |
| **特例 strategy** | 14 | `tokens/color/tetris/` (8 = 4 角色 + 7 方块色 - 2 重叠) + `tokens/color/team/` (6 头像色) — 架构决策保留，**不豁免注释**（本身就是架构师决策） |
| **新增 strategy 通道** | 0 | `tokens/color/chess/` (13 角色基础色 + 13 *From scheme 派生 → 0 残留) — v6.2.1 新通道，**不豁免**（派生方法封装在 token 中，调用方零裸 hex） |
| **未分类** | **0** | — |

**红线不变**：`lib/` 新增代码禁止裸 hex —— 走 scheme / 5 通道，或写豁免注释说明业务理由。

## 1. 顶层目录用色规模（v6.2 迁移后实拍）

| 目录 | Theme.of 文件数 | colors | board | tetris | teamAvatar | torchProtect | 角色 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lib/core/` | 82 | 8 | 0 | 0 | 0 | 0 | 业务核心模块（游戏/笔记/AI 聊天/表格） |
| `lib/lab/` | 69 | 57 | 2 | 1 | 1 | 1 | Demo 实验场，**colors 通道最高频** |
| `lib/screens/` | 18 | 1 | 0 | 0 | 0 | 0 | 主壳 + 设置 |
| `lib/services/` | 11 | 0 | 0 | 0 | 0 | 0 | 消息/图片 service |
| `lib/widgets/` | 15 | 5 | 0 | 0 | 0 | 0 | Base* 组件 + 5 个 context 扩展入口 |

## 2. 5 通道扩散地图

### `context.colors`（6 角色抽象，scheme 派生）
覆盖 57+ 文件（lab/demos 大头）：`block_editor_demo/`、`calendar/`、`clock/`、`api_test/`、`tetris_lua/`（HUD 部分）、`reversi_lua/` 等。
**Base\* 组件**：`lib/widgets/base/*.dart` 全部走 ColorStrategyExtension。

### `context.boardColors`（11 角色，scheme 派生）
使用点 2 个：
- `lib/lab/demos/gomoku_lua/board.dart`
- 早期 `lib/lab/demos/tetris_lua/board.dart`（v6.2 短暂用过，现已迁到 `context.tetrisColors` 特例）

**S 级并存系统**：`surround_game` 与 `reversi` 用各自的 `BoardThemeData` 令牌（见 §4），是架构决策保留的独立通道。

### `context.chessColors`（13 国际象棋角色，scheme 派生，**v6.2.1 新通道**）

设计原因：国际象棋棋盘的"两色格对照"语义（lightSquare + darkSquare）无法用 `board_color_strategy` 的"single background"表达，独立通道避免稀释其他棋类。

使用点 0 个：
- 暂无消费点（v6.2.1 策略通道已搭建，等待用户后续提供棋子 UI 时接入 widget 端）

**特殊豁免**（未来 chess 模块）：棋子图案走 asset bundle（用户后续提供），不进入 strategy 通道；棋子本身**不用** `chessColors.player1Stone / player2Stone`（棋子是图片而非纯色），仅棋盘底色 / 选中格 / 走法提示 / 将军警告等环境色通过 strategy 派生。

### `context.tetrisColors`（4 角色 + 7 方块色，native const 特例）
使用点 1 个：
- `lib/lab/demos/tetris_lua/board.dart`（主棋盘 + ghost + 下落块 + preview 4 处 `pieceColors[t]!`）

切任意主题 4 角色 + 7 方块色完全不变（玩家靠颜色识别方块）。

### `context.teamAvatar`（6 头像色，native const 特例）
使用点 2 个：
- `lib/lab/demos/team_card/widgets.dart`
- `lib/core/net_engine/relay_v3/participants_grid.dart`（**v6.2 批迁入**：12 头像色 → 6 头像色）

### `context.torchProtect`（10 护眼色预设，scheme 派生）
使用点 1 个：
- `lib/lab/demos/torch_demo.dart`（护眼灯）

## 3. 用色热点文件 Top 20

> 计数 = `Theme.of(context)` 单文件出现次数。**code review 优先扫这些**。

| 文件 | 调用数 | 备注 |
| --- | --- | --- |
| `lib/lab/demos/storage_analyze_demo.dart` | 82 | 存储分析，文件大 |
| `lib/core/novel_reader/novel_reader_page.dart` | 54 | 阅读器主壳 |
| `lib/lab/demos/tetris_lua/widgets.dart` | 45 | 俄罗斯方块 HUD（不读棋盘色，4 处 board.dart 走 `context.tetrisColors`） |
| `lib/lab/demos/web_bookmark_demo.dart` | 39 | 书签编辑器 |
| `lib/core/word_drag/pages/word_drag_page.dart` | 36 | 单词拖拽 |
| `lib/lab/demos/torch_demo.dart` | 35 | 护眼灯 |
| `lib/lab/demos/api_test_demo.dart` | 31 | API 测试 |
| `lib/lab/demos/coup_lua/widgets.dart` | 29 | 卡牌游戏 |
| `lib/core/doubletime/doubletime_page.dart` | 29 | 时间双线 |
| `lib/lab/demos/pigment_palette_demo.dart` | 27 | 配色 demo |
| `lib/lab/demos/notion_image_host_demo.dart` | 27 | 图床 |
| `lib/core/net_engine/pages/net_engine_debug_page.dart` | 26 | 网络调试 |
| `lib/core/novel_reader/page_curl_view.dart` | 25 | 翻页视图 |
| `lib/lab/demos/team_card/widgets.dart` | 24 | 团队卡（用 `context.teamAvatar`） |
| `lib/lab/demos/game_2048_demo.dart` | 22 | 2048 |
| `lib/lab/demos/api_test/api_speech_tab.dart` | 22 | 语音 tab |
| `lib/core/ai_chat/ai_chat_sports/agent_chat_page.dart` | 22 | AI 聊天 |
| `lib/core/focus/focus_timer_page.dart` | 21 | 专注计时 |
| `lib/lab/demos/reversi_lua/widgets.dart` | 20 | 黑白棋 |
| `lib/lab/demos/gomoku_lua/widgets.dart` | 19 | 五子棋 |

## 4. 残留 Color(0xFF) 223 处 — 全部已分类

> 不含 `lib/core/theme/`、`lib/widgets/theme/`。每一条都有归属：S 令牌系统 / E 豁免 / 特例 strategy。

| 目录 | 计数 | 归属 | 豁免理由 / 系统说明 |
| --- | --- | --- | --- |
| `lib/core/surround_game/` | 54 | **S** | `BoardThemeData` 令牌系统（warm/cool 两套预设，6 层视觉栈） |
| `lib/lab/demos/` | 42 | **E** | pigment 15 / web_bookmark 15 / stack_card 7 / 2048 3 / tetris 1 / calendar 1 |
| `lib/core/reversi/` | 36 | **S 32 + E 4** | 32 同 surround_game；4 是 Othello 国际识别色 |
| `lib/core/novel_reader/` | 27 | **E** | 纸质书视觉语言：纸张底色/棕色墨水/烫金封面渐变 |
| `lib/screens/profile/` | 20 | **E** | game_center 13 封面渐变 / character_profile 3 皮肤色 / lab_panel 3 历史 delete 红 + 1 |
| `lib/core/timetable/` | 9 | **E** | `_morandi` 8 莫兰迪（light 主题专属课程色）+ sage 1 |
| `lib/core/body/` | 8 | **E** | 医学解剖标准色（骨蓝/肌红/关黄/器绿 × 2 档） |
| `lib/core/jungle_chess/` | 7 | **E** | 斗兽棋国际识别色（暖米盘/浅蓝河/金兽穴/红蓝方） |
| `lib/core/focus/` | 5 | **E** | sage 家族（B5C9A3/7A9A6E）zen 风识别 |
| `lib/core/line/` | 2 | **E** | 音游评级奖励渐变（P 粉紫蓝 / S 金橙） |
| `lib/core/theme/tokens/color/tetris/` | 8 | **特例** | 4 角色 + 7 方块色（v6.2 修正，native const 锁定） |
| `lib/core/theme/tokens/color/team/` | 6 | **特例** | 6 头像色（native const 锁定） |
| `lib/core/theme/tokens/color/torch/` | 10 | **特例（但 scheme 派生）** | 10 护眼色预设（实际从 scheme 派生） |

> 特例 strategy 数量（24 处）= §0 表里"特例 strategy 13" + torch 10 + 1 阴影忽略项（未在 §0 表中列 torch 详细数）。

### 迁移历史（5 批，65 处 M）

| 批 | 目录 | 迁移数 | 改法摘要 |
| --- | --- | --- | --- |
| 1 | doubletime / message_strategy / word_drag | 21 | painter scheme 注入；PieChart 加 categoryColors；CategoryBucket.color 死字段删除 |
| 2 | timetable / net_engine / focus | 14 | TimetableColors → 函数式（BuildContext）；kParticipantColors → avatarColors；TimePageMeta.color 删 → colorFor() |
| 3 | profile / jungle_chess / body / line | 8 | lab_panel delete → scheme.error；jungle 5 色 → 顶层函数式 |
| 4 | novel_reader | 6 | 错误/绿色强调 → scheme.error/tertiary |
| 5 | lab/demos | 16 | bottom_bar 死字段删；reaction 5 phase → scheme；bookmark 2 处迁 |
| 6（v6.2 收尾） | 全 lib 调用点 | 17 文件 | `zenButton` → `zenButtonTheme` 签名迁移；删 `ZenColors` 兼容层；zen 主题 5 色校准；calendar_import_dialog 最后 1 处 → scheme；recorder `zenCard` → `zenCardTheme` |
| 7（v6.2.1 特例修正） | tetris_lua + tetris_colors_strategy | 4 文件 | `pieceColors` 改 Map 1..7 + 4 角色 native const + shouldRepaint `=> true` + 新增 15 回归测试 |
| **8（v6.2.1 新通道）** | **theme/tokens/color/chess/ + colors/strategy/chess_color_strategy/ + extensions/ + factory + app_theme + context + test** | **7 文件** | **`ChessColorStrategy` 第 6 个 strategy：13 角色 from scheme 派生 + ThemeExtension + context 双层兜底 + 12 单元测试** |

## 5. 迁移完整度自检命令

```bash
# 1. 统计每目录 5 通道使用量
for d in lib/core lib/lab lib/screens lib/widgets; do
  echo "$d: Theme.of=$(grep -rl 'Theme.of(context)' "$d" | wc -l) | colors=$(grep -rl 'context\.colors\b' "$d" | wc -l) | board=$(grep -rl 'context\.boardColors' "$d" | wc -l) | tetris=$(grep -rl 'context\.tetrisColors' "$d" | wc -l) | team=$(grep -rl 'context\.teamAvatar' "$d" | wc -l) | torch=$(grep -rl 'context\.torchProtect' "$d" | wc -l)"
done

# 2. 检查残留硬编码 hex —— 每一处必须带豁免注释或属于特例 token
grep -rn "Color(0xFF" lib/ --include="*.dart" | grep -v "lib/core/theme/" | grep -v "lib/widgets/theme/"

# 3. 任何新增 widget 后必须
flutter analyze --no-pub  # 0 error
flutter build apk --debug  # √ Built

# 4. tetris 特例回归（本地 .gitignore）
flutter test test/lab/tetris_lua/  # 15/15 passed
```

## 6. 目录推荐配色策略速查

| 目录类型 | 推荐通道 | 理由 |
| --- | --- | --- |
| 业务壳层（profile/chat/setting） | `Theme.of(context).colorScheme.X` + `context.colors` | 跨主题一致性高 |
| 棋盘/棋类游戏（gomoku/reversi/jungle） | `context.boardColors` | 棋子黑白关系 + 棋盘环境独立 |
| **国际象棋** | **`context.chessColors`** | **两色格 + 选中/将军/升变（v6.2.1 新通道）** |
| 俄罗斯方块 | `context.tetrisColors` | 7 方块识别色锁定，玩家靠颜色识别 |
| 团队卡头像 | `context.teamAvatar` | 6 头像色锁定，色 = 身份 |
| 护眼灯 | `context.torchProtect` | 10 预设色，跟主题联动（暗主题更柔） |
| AI 聊天/笔记/阅读 | `Theme.of(context).colorScheme.X` + `AppColorsExtension.category` | 文本/分类场景 |
| 计时/专注（zen 风） | `Theme.of(context).colorScheme.X` + sage 家族（豁免） | 与 zen 主题呼应 |
| 调试/诊断页 | `Theme.of(context).colorScheme.X` | 无视觉风格诉求 |
| 自定义数据色（站点/品牌） | **硬编码豁免** + `主题豁免` 注释 | 数据持久化属性 |

## 6.5 历史踩坑文件清单（迁移时必查）

> 这些文件在本会话及历次主题迁移中**至少踩过 1 次主题色坑**。下次迁移相似功能前先扫一遍，能直接复用修法：
>
> （修法与根因详见 [[extension]] §4.5 与 [[architecture]] §6。）

| 文件 | 踩过的坑 | 修法 |
| --- | --- | --- |
| `lib/lab/demos/clock_demo.dart` | 嵌套 `MaterialApp` 只复制 4 个字段，子树退回 Flutter 默认配色 | `theme: base.copyWith(...)` 继承完整 ThemeData（[[architecture]] §6.2） |
| `lib/lab/demos/calendar_demo.dart` | `CalendarSettingsPage` 被 `Navigator.push` 推出去后查不到 `LabCalendarProvider`，红屏崩溃 | push 时用 `MultiProvider` + `.value` 显式传 provider（[[architecture]] §6.3） |
| `lib/lab/demos/web_bookmark_demo.dart` | 卡片 `backgroundColor: onSurface`、icon selector `withAlpha(51)` 半透明硬编码色、`surfaceVariant` 已 deprecated | 卡片改 `surface`、selector 改 `primaryContainer`/`surfaceContainerHighest`、`surfaceVariant` 改 `surfaceContainerHighest` |
| `lib/core/word_drag/pages/word_drag_page.dart` | 拖拽背景 `onSurface`（深底） | 改 `surface` |
| `lib/core/word_drag/widgets/word_card_content.dart` | 定义/例句容器用 `onSurfaceVariant` / `primary` 等不协调角色 | 定义 `primaryContainer`+`onPrimaryContainer`，例句 `secondaryContainer`+`onSecondaryContainer`+`outline` 边框 |
| `lib/widgets/markdown_renderer_widget.dart` | code/codeblock 背景 `surfaceContainerHighest`（深） | `primaryContainer` |
| `lib/widgets/theme/zen_theme.dart` `zenPageScaffold` | `backgroundColor: surfaceContainerHighest`（深） | `surface` |
| `lib/core/theme/app_theme.dart` `appBarTheme` / `bottomNavigationBarTheme` | 背景 `surfaceContainerHighest`（深） | `surface` |
| `lib/lab/demos/crash_log_demo.dart` / `kvcli_todo_demo.dart` / `overlay_demo.dart` / `schema_demo.dart` | AppBar `backgroundColor: inversePrimary`（暗沉互补色） | 移除（走 AppBarTheme 默认 `surface`） |
| `lib/core/theme/tokens/color/theme/lemon.dart` / `rose.dart` | `outline`/`outlineVariant` 鲜艳（纯黄/纯粉），与主题整体调性冲突 | 改为"带主题色温的淡色调" |
| `lib/core/theme/tokens/color/theme/purple.dart` | `surface` 被基于错误诊断改亮（#3A3832）→ 暮紫主题丢失"鎏金暖黑底"质感 | 恢复 `#201F1A`（所有 ColorScheme 改动必须有"为什么"注释） |
| `lib/lab/demos/notion_image_host_demo.dart` | 拍照框 + 文字输入框 `surfaceContainerHighest` → `primaryContainer` → `Color.lerp(0.4)` → `Color.lerp(0.2)` 才够浅 | `Color.lerp(surface, primaryContainer, 0.2)`（§0.1 契约规则） |
| `lib/core/novel_reader/novel_reader_page.dart` | 顶部注释"全部豁免"含烫金封面渐变 → 用户要求不豁免书皮封面 | 注释改为逐项豁免；封面渐变改主题三段色 |
| `lib/core/novel_reader/novel_reader_page.dart` | 占位卡边框硬编码绿 `Color(0xFF2F6A55).withAlpha(0.30)` | `colorScheme.outline`（边框主义） |
| `lib/core/theme/tokens/color/tetris/tetris.dart`（v6.2） | pieceColors 改 `List<Color>` 0..6 + 从 scheme 派生 → L 块越界消失 + 1..6 颜色全错 + 棋盘跟主题漂移 + shouldRepaint 引用比较失效 | 改 `Map<int, Color>` 1..7 + 4 角色 native const + shouldRepaint `=> true`（[[special-cases]] §1） |

## 7. v7 架构议题（未做，已记录）

surround_game + reversi 的 `BoardThemeData`（86 处 hex）是否整合进 `context.boardColors`：
- **保持现状**（推荐）：两系统各有 warm/cool 预设和多角色 3D 效果色，整合成本高、收益低
- **整合**：统一棋牌策略通道，但 BoardColorStrategy 现有 11 角色无法覆盖 BoardThemeData 的 30+ 角色（棋子高光/边缘暗部/墙面高光…），需扩接口

tetris 特例是否扩展为更通用的"识别色 strategy"模板：
- **保持现状**（推荐）：tetris / teamAvatar 各一个 strategy，简单清晰
- **提取模板**：写一个 `RecognizableColorStrategy<T>` 抽象，强制 `Map<int, Color>` + native const —— 但增加抽象层对未来扩展收益不大
