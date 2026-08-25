# 子 ref C：当前颜色用法审计（color 用得最多的目录是哪些）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文是**迁移完整度快照**：残留 hex 归属、Top 热点、目录用色规模、迁移历史。
> 数据基于 v6.1 重构 + 5 批迁移 + v6.2 收尾（ZenColors 兼容层删除）后的快照（`grep` 实拍，2026-08-25）。
> 改/评审任何目录前查此表判断迁移完整度。架构/数据流见 [[architecture]]，改动 SOP 见 [[extension]]。

## 0. 迁移状态：✅ 已完成（含 v6.2 收尾）

**5 批迁移 + v6.2 收尾全部落地**（124 处豁免 + 65 处迁移 + 86 处 BoardTheme 令牌）。
v6.2（2026-08-25 工作区）：`zenButton(...)` → `zenButtonTheme(context, ...)` 签名迁移覆盖 15 文件、删除 `ZenColors` 兼容层（`zenCard`/`zenDottedZone`/`zenButton`）、zen 主题 5 环境色校准回 ZenColors 常量值、`calendar_import_dialog` 最后一处 `ZenColors.secondary` 迁移。
当前 `lib/` 内所有残留 `Color(0xFF...)` 均已分类：

| 分类 | 数量 | 说明 |
| --- | --- | --- |
| **S 令牌系统** | 86 | surround_game (54) + reversi (32) 的 `BoardThemeData` 独立令牌，与 `context.boardColors` 平级 |
| **E 豁免** | 124 | 全部带 `主题豁免` 注释（品牌色/国际识别色/纸质书视觉/医学解剖色/sage 家族…） |
| **未分类** | **0** | — |

**红线不变**：`lib/` 新增代码禁止裸 hex —— 走 scheme / 3 通道，或写豁免注释说明业务理由。

## 1. 顶层目录用色规模（迁移后实拍）

| 目录 | Theme.of 文件数 | colors | board | game | 角色 |
| --- | --- | --- | --- | --- | --- |
| `lib/core/` | 82 | 8 | 0 | 1 | 业务核心模块（游戏/笔记/AI 聊天/表格） |
| `lib/lab/` | 69 | 57 | 2 | 7 | Demo 实验场，**colors 通道最高频** |
| `lib/screens/` | 18 | 1 | 0 | 0 | 主壳 + 设置 |
| `lib/services/` | 11 | 0 | 0 | 0 | 消息/图片 service |
| `lib/widgets/` | 15 | 5 | 2 | 1 | Base* 组件 + 3 个 context 扩展入口 |

## 2. 3 通道扩散地图

### `context.colors`（6 角色抽象）
覆盖 57+ 文件（lab/demos 大头）：`block_editor_demo/`、`calendar/`、`clock/`、`api_test/`、`tetris_lua/`、`reversi_lua/` 等。
**Base\* 组件**：`lib/widgets/base/*.dart` 全部走 ColorStrategyExtension。

### `context.boardColors`（10 角色，棋盘专属）
使用点 2 个：
- `lib/lab/demos/gomoku_lua/board.dart`
- `lib/lab/demos/tetris_lua/board.dart`

**S 级并存系统**：`surround_game` 与 `reversi` 用各自的 `BoardThemeData` 令牌（见 §4），是架构决策保留的独立通道。

### `context.gameColors`（方块/头像/护眼色板）
使用点 8 个：
- `gomoku_lua/widgets.dart`（棋子黑白）
- `team_card/`（6 头像）
- `tetris_lua/`（7 方块）
- `torch/`（10 护眼色）
- `net_engine/relay_v3/participants_grid.dart`（**本批迁入**：12 头像色 → avatarColors）

## 3. 用色热点文件 Top 20

> 计数 = `Theme.of(context)` 单文件出现次数。**code review 优先扫这些**。

| 文件 | 调用数 | 备注 |
| --- | --- | --- |
| `lib/lab/demos/storage_analyze_demo.dart` | 82 | 存储分析，文件大 |
| `lib/core/novel_reader/novel_reader_page.dart` | 54 | 阅读器主壳 |
| `lib/lab/demos/tetris_lua/widgets.dart` | 45 | 俄罗斯方块 HUD |
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
| `lib/lab/demos/team_card/widgets.dart` | 24 | 团队卡 |
| `lib/lab/demos/game_2048_demo.dart` | 22 | 2048 |
| `lib/lab/demos/api_test/api_speech_tab.dart` | 22 | 语音 tab |
| `lib/core/ai_chat/ai_chat_sports/agent_chat_page.dart` | 22 | AI 聊天 |
| `lib/core/focus/focus_timer_page.dart` | 21 | 专注计时 |
| `lib/lab/demos/reversi_lua/widgets.dart` | 20 | 黑白棋 |
| `lib/lab/demos/gomoku_lua/widgets.dart` | 19 | 五子棋 |

## 4. 残留 Color(0xFF) 210 处 — 全部已分类

> 不含 `lib/core/theme/`、`lib/widgets/theme/`。每一条都有归属：S 令牌系统 或 E 豁免。

| 目录 | 计数 | 归属 | 豁免理由 / 系统说明 |
| --- | --- | --- | --- |
| `lib/core/surround_game/` | 54 | **S** | `BoardThemeData` 令牌系统（warm/cool 两套预设，6 层视觉栈），与 context.boardColors 平级 |
| `lib/lab/demos/` | 42 | **E** | pigment 15（demo 展示调色板本体）/ web_bookmark 15（iOS 调色板 + 品牌色）/ stack_card 7（封面艺术）/ 2048 3（原版识别色）/ tetris 1 / calendar 1（RGB 合成） |
| `lib/core/reversi/` | 36 | **S 32 + E 4** | 32 同 surround_game BoardTheme；4 是 Othello 国际识别色（绿盘黑白子） |
| `lib/core/novel_reader/` | 27 | **E** | 纸质书视觉语言：纸张底色/棕色墨水/烫金封面渐变（文件级豁免注释） |
| `lib/screens/profile/` | 20 | **E** | game_center 13 封面渐变 / character_profile 3 皮肤色 / lab_panel 3 历史 delete 红（使用点已迁，常量留参考）+ 1 |
| `lib/core/timetable/` | 9 | **E** | `_morandi` 8 莫兰迪（light 主题专属课程色）+ sage 1（zen 家族） |
| `lib/core/body/` | 8 | **E** | 医学解剖标准色（骨蓝/肌红/关黄/器绿 × 2 档） |
| `lib/core/jungle_chess/` | 7 | **E** | 斗兽棋国际识别色（暖米盘/浅蓝河/金兽穴/红蓝方） |
| `lib/core/focus/` | 5 | **E** | sage 家族（B5C9A3/7A9A6E）zen 风识别 |
| `lib/core/line/` | 2 | **E** | 音游评级奖励渐变（P 粉紫蓝 / S 金橙） |

### 迁移历史（5 批，65 处 M）

| 批 | 目录 | 迁移数 | 改法摘要 |
| --- | --- | --- | --- |
| 1 | doubletime / message_strategy / word_drag | 21 | painter scheme 注入；PieChart 加 categoryColors；CategoryBucket.color 死字段删除 |
| 2 | timetable / net_engine / focus | 14 | TimetableColors → 函数式（BuildContext）；kParticipantColors → avatarColors；TimePageMeta.color 删 → colorFor() |
| 3 | profile / jungle_chess / body / line | 8 | lab_panel delete → scheme.error；jungle 5 色 → 顶层函数式 |
| 4 | novel_reader | 6 | 错误/绿色强调 → scheme.error/tertiary |
| 5 | lab/demos | 16 | bottom_bar 死字段删；reaction 5 phase → scheme；bookmark 2 处迁 |
| 6（v6.2 收尾） | 全 lib 调用点 | 17 文件 | `zenButton` → `zenButtonTheme` 签名迁移（timetable/clock/relation_calc 等）；删 `ZenColors` 兼容层（card/dottedZone/button）；zen 主题 5 色校准对齐 ZenColors 常量；calendar_import_dialog 最后 1 处 `ZenColors.secondary` → scheme；recorder `zenCard` → `zenCardTheme` |

## 5. 迁移完整度自检命令

```bash
# 1. 统计每目录 4 通道使用量
for d in lib/core lib/lab lib/screens lib/widgets; do
  echo "$d: Theme.of=$(grep -rl 'Theme.of(context)' "$d" | wc -l) | colors=$(grep -rl 'context\.colors\b' "$d" | wc -l) | board=$(grep -rl 'context\.boardColors' "$d" | wc -l) | game=$(grep -rl 'context\.gameColors' "$d" | wc -l)"
done

# 2. 检查残留硬编码 hex —— 每一处必须带豁免注释或属于 BoardThemeData
grep -rn "Color(0xFF" lib/ --include="*.dart" | grep -v "lib/core/theme/" | grep -v "lib/widgets/theme/"

# 3. 任何新增 widget 后必须
flutter analyze --no-pub  # 0 error
flutter build apk --debug  # √ Built
```

## 6. 目录推荐配色策略速查

| 目录类型 | 推荐通道 | 理由 |
| --- | --- | --- |
| 业务壳层（profile/chat/setting） | `Theme.of(context).colorScheme.X` + `context.colors` | 跨主题一致性高 |
| 棋盘/棋类游戏 | `context.boardColors` + `context.gameColors.pieceXxx` | 棋子黑白关系 + 棋盘环境独立 |
| 方块/角色分类游戏 | `context.gameColors.pieceColors/avatarColors` | 独立色板 |
| AI 聊天/笔记/阅读 | `Theme.of(context).colorScheme.X` + `AppColorsExtension.category` | 文本/分类场景 |
| 计时/专注（zen 风） | `Theme.of(context).colorScheme.X` + sage 家族（豁免） | 与 zen 主题呼应 |
| 调试/诊断页 | `Theme.of(context).colorScheme.X` | 无视觉风格诉求 |
| 自定义数据色（站点/品牌） | **硬编码豁免** + `主题豁免` 注释 | 数据持久化属性 |

## 7. v7 架构议题（未做，已记录）

surround_game + reversi 的 `BoardThemeData`（86 处 hex）是否整合进 `context.boardColors`：
- **保持现状**（推荐）：两系统各有 warm/cool 预设和多角色 3D 效果色，整合成本高、收益低
- **整合**：统一棋牌策略通道，但 BoardColorStrategy 现有 10 角色无法覆盖 BoardThemeData 的 30+ 角色（棋子高光/边缘暗部/墙面高光…），需扩接口
