# 全局主题通道与硬编码组件审计

> 审计范围：`lib/**/*.dart`  
> 审计日期：2026-06-16  
> 更新：2026-09-21 补 `rose` / `lemon`；2026-10-12 补 `cobalt`（ID'CAKE 蓝白）。修正 `AppColorsExtension` 入口路径、登记 `ReactionPalette` 信号灯色豁免。
> 审计目标：确认当前主题种类、主题通道覆盖情况，以及切换主题后仍保留固定颜色的具体组件。

## 1. 结论摘要

当前全局提供 6 套主题：

| 模式 | 显示名称 | 明暗 | 视觉方向 |
| --- | --- | --- | --- |
| `AppThemeMode.purple` | 暮紫主题 | 深色 | 暮紫主色 + 鎏金暖黑环境 |
| `AppThemeMode.zen` | 茶禅主题 | 浅色 | Sage 绿 + 暖米环境 + 陶土红强调 |
| `AppThemeMode.ink` | 墨白主题 | 浅色 | 墨黑 + 纸白 + 墨赭强调 |
| `AppThemeMode.rose` | 粉雾主题 | 浅色 | 近白页 + 尘玫瑰 CTA |
| `AppThemeMode.lemon` | 柠檬鼠尾草主题 | 浅色 | 黄油主色 + 低彩鼠尾草 |
| `AppThemeMode.cobalt` | 宝蓝主题 | 浅色 | 宝蓝 + 纯白高对比（ID'CAKE） |

主题入口与状态链路：

```text
ThemeNotifier
  -> AppThemeMode
  -> AppTheme.getThemeData(mode)
  -> ThemeData(ColorScheme + ThemeExtension)
  -> MaterialApp
  -> Theme.of(context) / context.colors / context.boardColors / context.gameColors
```

静态扫描结果：

| 通道/模式 | 文件数 | 匹配数 | 说明 |
| --- | ---: | ---: | --- |
| `Theme.of(...)` | 192 | 1393 | 当前覆盖最广的 Material 主题通道 |
| `context.colors` | 50 | 350 | 应用 6 个核心语义角色与完整 `ColorScheme` 兜底 |
| `context.boardColors` / `BoardTheme.of` | 18 | 34 | 棋盘专用颜色通道 |
| `context.gameColors` | 9 | 20 | 游戏棋子、头像、预设色通道 |
| `AppColorsExtension` 相关 | 3 | 26 | success/warning/info/category 使用仍偏少 |
| `Color(0x...)` / `Colors.xxx` | 84 | 769 | 包含主题源数据、合理业务色和待整改 UI 硬编码 |

注意：匹配数是文本静态扫描结果，不等于独立 Widget 数量；`Colors.transparent`、主题 token、品牌色和数据可视化色不能直接判定为问题。

## 2. 审计判定标准

### 2.1 判定为主题已生效

满足以下任一条件：

- 使用 `Theme.of(context).colorScheme.*`；
- 使用 `context.colors.*`；
- 使用 `AppColorsExtension` 的状态色或分类色；
- 棋盘组件使用 `context.boardColors`；
- 游戏专属组件使用 `context.gameColors`；
- Painter 的颜色由上层从当前主题传入。

### 2.2 判定为主题不生效

普通 UI 的背景、文字、边框、按钮、图标、遮罩或状态提示直接使用：

- `Colors.blue/red/green/grey/...`；
- `Colors.white/black/black54/...`；
- 页面或组件内部的固定 `Color(0x...)`；
- `ZenColors.*`；
- 未被主题颜色覆盖的 `ZenText.*`。

典型表现：

- `purple` 深色主题中残留浅灰、浅蓝、浅红背景；
- 标题或正文仍是固定深色，导致深色背景下对比度不足；
- 按钮前景固定为白色，而不是 `onPrimary/onError`；
- 成功、警告、信息状态始终使用 Material 默认绿/橙/蓝；
- 页面切换主题后仍保持 Zen Sage 色。

### 2.3 合理豁免

下列颜色默认不作为全局主题缺陷，但外围 UI 仍需审计：

- 主题系统自身的 raw token、`ColorScheme` 和 `ThemeExtension` 定义；
- 游戏棋盘、棋子、地形、2048 方块等规则视觉色；
- 反应力测试的红 / 绿 / 琥珀信号灯色（`ReactionPalette`）—— 底色即交互指令，跟随主题会在多数主题下失效；
- 网站、平台和第三方品牌色；
- 医学组织分类、痛感梯度等数据语义色；
- 图表分类色，但建议优先评估 `AppColorsExtension.category`；
- 手电筒、屏幕补光、颜料色板等功能实际输出色；
- 小说阅读器纸张、墨色等独立内容主题；
- `Colors.transparent`；
- 为保证内容对比度而经过明确验证的固定前景色。

## 3. 当前主题通道

### 3.1 Material `ColorScheme`

入口：`lib/core/theme/app_theme.dart`、`lib/core/theme/tokens/colors.dart`

覆盖角色包括：

- `primary/onPrimary/primaryContainer/onPrimaryContainer`；
- `secondary/secondaryContainer`；
- `tertiary/tertiaryContainer`；
- `error/onError/errorContainer/onErrorContainer`；
- `surface/surfaceContainerHighest/onSurface/onSurfaceVariant`；
- `outline/outlineVariant/scrim/shadow`。

### 3.2 `context.colors`

入口：`lib/widgets/context_colors.dart`

核心角色：

| 角色 | 用途 |
| --- | --- |
| `accent` | 按钮、选中状态、强调图标 |
| `surface` | 卡片、弹窗、容器背景 |
| `outline` | 边框和分割线 |
| `text` | 主文字 |
| `textMuted` | 次文字 |
| `danger` | 删除、错误和危险操作 |
| `scheme` | 完整 `ColorScheme` 兜底 |

### 3.3 `AppColorsExtension`

入口：`lib/core/theme/tokens/color/app_colors_extension.dart`
（6 套主题各持一份 const 实例，定义在 `lib/core/theme/tokens/color/theme/<theme>.dart`）

用于：

- `success/onSuccess/successContainer/onSuccessContainer`；
- `warning/onWarning/warningContainer/onWarningContainer`；
- `info/onInfo/infoContainer/onInfoContainer`；
- 8 色 `category` 分类色板。

当前定义完整，但实际消费量明显少于 `ColorScheme`。

### 3.4 棋盘与游戏通道

- `context.boardColors`：棋盘背景、网格、棋子、玩家边框等；
- `context.gameColors`：棋子、头像、护眼预设及多人识别色；
- 不应强制迁移到普通页面的 `primary/surface`。

## 4. 主题真正不生效的具体组件

## 4.1 旧 Zen 兼容层

文件：`lib/widgets/theme/zen_theme.dart`

| 组件/API | 固定颜色 | 影响 | 优先级 |
| --- | --- | --- | --- |
| `ZenText.body` | `#2C2C2C` | 深色主题正文仍为深色 | P0 |
| `ZenText.label` | `#8A8475` | 次文字不跟 `onSurfaceVariant` | P0 |
| `ZenText.title` | `#2C2C2C` | AppBar/页面标题在深色主题失效 | P0 |
| `ZenText.monoDigit` | `#2C2C2C` | 时钟/数字固定深色 | P0 |
| `ZenText.monoDigitLarge` | `#2C2C2C` | 大数字固定深色 | P0 |
| `ZenText.monoDigitSmall` | `#8A8475` | 小数字固定暖灰 | P0 |
| `zenCard()` | `ZenColors.surface/hair` | 卡片背景和边框固定 Zen | P1 |
| `zenDottedZone()` | `ZenColors.surface/hair` | 区域背景和边框固定 Zen | P1 |
| `zenButton()` | `ZenColors.ink/hair` | 按钮文字和边框固定 Zen | P1 |
| `ZenSection` 标题 | `ZenText.label` | 容器已主题化，标题未主题化 | P0 |
| `zenPageScaffold` 标题 | `ZenText.title` | Scaffold 已主题化，标题未主题化 | P0 |

替代 API 已存在：

- `zenCardTheme(context)`；
- `zenDottedZoneTheme(context)`；
- `zenButtonTheme(context)`。

但 `ZenText` 是静态 `const TextStyle`，必须由消费者 `.copyWith(color: ...)`，或新增从上下文构建的主题化文字 API。

## 4.2 Calendar

### `CalendarSettingsPage`

文件：`lib/lab/demos/calendar/service/config/calendar_settings_page.dart`

| 组件 | 问题 |
| --- | --- |
| `_GroupTile` | active 图标固定 `ZenColors.sage`，inactive 固定 `ZenColors.secondary` |
| `_GroupTile` 标题 | 使用固定色 `ZenText.body` |
| “当前”标签 | 固定 `ZenColors.sage` |
| `_ZenActionButton` | 普通/次要操作继续绑定 Zen 色 |
| 删除操作 | 直接使用 `Colors.red` 或 `red.shade400` |

### `CalendarImportDialog`

文件：`lib/lab/demos/calendar/service/config/calendar_import_dialog.dart`

具体受影响区域：

- Dialog 遮罩：`Colors.black26`；
- Dialog 边框：`ZenColors.hair`；
- 标题和正文：`ZenColors.ink/secondary`、`ZenText`；
- 输入框填充：`ZenColors.surface`；
- 输入框边框：`ZenColors.hair`；
- 取消按钮：`ZenColors.secondary/hair`；
- 导入按钮：`ZenColors.sage`；
- 错误块：`red.shade50/200/700`；
- 预览卡片：`ZenColors.surface/hair`。

该组件在 `purple` 主题下仍整体呈现浅色 Zen 对话框，属于明确 P0 缺陷。

## 4.3 Block Editor Demo

### `BlockEditorDemo`

文件：`lib/lab/demos/block_editor_demo/block_editor_demo.dart`

- `_proxyDecorator`：拖拽背景固定 `Colors.blue` 半透明；
- 拖拽边框固定蓝色；
- 阴影固定黑色。

### `BlockCard`

文件：`lib/lab/demos/block_editor_demo/card.dart`

受影响方法：

- `_buildPendingRemoved`：固定浅红背景和红色文字/图标；
- `_buildPendingNew`：固定浅绿背景和绿色边框/文字；
- `_buildDiffHighlight`：固定红绿 Diff 色；
- `_DeletePill`：删除状态固定 Material 红色。

建议角色：

- 删除：`error/errorContainer/onErrorContainer`；
- 新增：`success/successContainer/onSuccessContainer`。

### `NotePanel`

文件：`lib/lab/demos/block_editor_demo/note_panel.dart`

| 组件区域 | 固定颜色 |
| --- | --- |
| Panel 分割线 | `grey[200]` |
| 空状态图标/文字 | `grey[400/500/600]` |
| 删除按钮 | `Colors.red` + `Colors.white` |
| `_NoteListTile` 当前项背景 | 蓝色半透明 |
| `_NoteListTile` 当前项图标/标题 | `Colors.blue/blue[700]` |
| `_NoteListTile` 普通项 | `grey[400/500/600]` |

### `TypePanel`

文件：`lib/lab/demos/block_editor_demo/type_panel.dart`

| 组件区域 | 固定颜色 |
| --- | --- |
| 分隔线 | `grey[300]` |
| 分类标题 | `grey[500]` |
| `_actionTile` 背景 | `grey[50]` |
| `_actionTile` 图标/文字 | `grey[700]` |
| `_typeTile` 背景 | `grey[50]` |
| `_typeTile` 图标/文字 | `grey[700]` |

`purple` 主题下仍是完整浅灰面板，属于 P0 缺陷。

### `EditToolbar`

文件：`lib/lab/demos/block_editor_demo/mode/edit_toolbar.dart`

受影响组件：

- 展开/收起图标；
- `_toolbarTypeButton`；
- `_toolbarButton`。

以上图标固定 `grey[600]`。

### `AiConversationOverlay`

文件：`lib/lab/demos/block_editor_demo/ai/ai_conversation.dart`

受影响组件：

- `_buildPanel`；
- `_buildHeader`；
- `_buildBody`；
- `_buildMessageBubble`；
- `_buildInputArea`；
- `_footerBtn`。

残留固定颜色：

- 黑色 3%、5%、12% 叠层/阴影；
- 固定白色图标；
- 多处透明背景。

透明色本身不构成缺陷，但固定黑色叠层应改为 `shadow/scrim/onSurface` 派生透明度。

### `DiffViewer`

文件：`lib/lab/demos/block_editor_demo/ai/diff_viewer.dart`

- 新增行：`green.shade700`；
- 删除行：`red.shade700`。

应迁移到 success/error 语义角色。

## 4.4 AI Chat

### `AIChatSettingsPage`

文件：`lib/core/ai_chat/ai_chat_settings_page.dart`

受影响区域：

- 存储状态卡片：`green[50]`；
- 存储图标和文字：`green[700]`；
- 成功状态：`Colors.green`；
- 信息提示卡片：`blue[50]`；
- 信息图标和文字：`Colors.blue`。

深色主题中固定 `green[50]/blue[50]` 是明确 P0 缺陷。

### `FormatCompatibilityPage`

文件：`lib/core/ai_chat/ai_chat_format/format_compatibility_page.dart`

受影响组件：

- `_buildEmptyHint`；
- `_buildInputArea`；
- `_FormatMessageBubble`；
- `_TypeChipStrip`。

残留：固定灰色辅助文字、固定黑色 5% 叠层。

### `AgentChatPage`

文件：`lib/core/ai_chat/ai_chat_sports/agent_chat_page.dart`

受影响组件：

- 空状态提示；
- Agent 状态显示；
- `_buildInputArea`；
- 清空/删除操作；
- `_MessageBubble`；
- `_QuickReply`。

固定颜色：蓝、绿、橙、红、白和黑色 5% 叠层。`_MessageBubble` 的本人消息文字固定白色，应使用对应背景角色的 `on*` 色。

### `SystemMessagesPage`

文件：`lib/core/ai_chat/system_messages/system_messages_page.dart`

- 清空确认按钮固定 `Colors.red`；
- 应使用 `colorScheme.error/onError`。

### `SystemMessagesPanel`

文件：`lib/core/ai_chat/system_messages/system_messages_panel.dart`

- `_EmptyState` 图标固定 `grey[400]`；
- 主提示固定 `grey[600]`；
- 次提示固定 `grey[500]`。

应统一使用 `onSurfaceVariant` 的不同透明度。

### `ReceiptOcrPage`

文件：`lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart`

受影响组件：

- 清空操作固定红色；
- 历史/辅助文字固定灰色；
- `_buildBubble`、`_buildError`、`_buildInputBar`、`_buildEmpty` 需继续检查是否完整使用语义角色。

## 4.5 旧消息策略

### `BillOverviewMessageWidgetStrategy`

文件：`lib/services/message_strategy/strategies/bill_overview_message_strategy.dart`

受影响组件：

- `_BillOverviewContent`；
- `_buildMetricItem`；
- `_buildCategoryRow`；
- `_buildHighlightCard`；
- `_PieChartPainter`。

问题：

- 成功/增长状态直接使用 `Colors.green`；
- 饼图使用固定 6 色表：`#6366F1/#F59E0B/#10B981/#EC4899/#8B5CF6/#6B7280`。

判定：普通状态色应整改；图表色属于可条件豁免项，建议评估迁移到 `AppColorsExtension.category`。

### `LoginMessageWidgetStrategy`

文件：`lib/services/message_strategy/strategies/login_message_strategy.dart`

- `_LoginContent` 部分按钮/图标前景固定白色；
- 应使用按钮背景对应的 `onPrimary/onError`。

### `RegisterMessageWidgetStrategy`

文件：`lib/services/message_strategy/strategies/register_message_strategy.dart`

受影响步骤：

- `_EmailStep`；
- `_CodeStep`；
- `_PasswordStep`；
- `_InviteStep`；
- `_SuccessStep`。

部分按钮或图标前景固定白色，没有绑定对应 `on*` 角色。

### `SystemEventMessageWidgetStrategy`

文件：`lib/services/message_strategy/strategies/system_event_message_strategy.dart`

受影响组件：

- 消息正文与时间文字；
- 事件类型图标颜色映射；
- `_AssistantAvatar`；
- `_BubblePainter`。

固定映射包括：

- 自动检查：indigo；
- 下载：blue；
- 成功：green；
- 失败/崩溃：red；
- 默认：grey；
- Assistant 头像：teal。

成功/失败/默认状态应走主题语义。Assistant teal 若是角色识别色可保留，但其背景、边框和前景应保证主题对比度。

### `WaterCapsuleMessageWidgetStrategy`

文件：`lib/services/message_strategy/strategies/water_capsule_message_strategy.dart`

受影响组件：

- `_WaveCapsule`；
- `_buildControlButton`；
- `_WavePainter`；
- `WaterCapsuleMessageWidgetStrategy`。

固定颜色：

- 背景 `#E8EDFE`；
- 主蓝 `#2633C5`；
- 近白背景 `#FAFAFA`；
- 控制图标 `Colors.white`。

判定：若水胶囊是固定品牌视觉，应登记为组件级主题豁免；若要求跟随全局主题，这是消息策略中最明显的 P0 缺陷之一。

## 4.6 Body

### `RecordSheet`

文件：`lib/core/body/widgets/record_sheet.dart`

受影响组件：

- 分隔线：`grey[300]`；
- 组织类型和空结果辅助文字：`grey[500/600]`；
- `_RecordTile` 删除按钮：红底白图标；
- 编辑图标：固定蓝色；
- 痛感渐变：绿到红。

判定：

- 痛感渐变属于数据语义，可保留；
- 分隔线、辅助文字、编辑和删除按钮应主题化。

### `BodyBlockPainter`

文件：`lib/core/body/painters/body_block_painter.dart`

固定绘制颜色：

- 区域文字：白色；
- 文字阴影：黑色 54%；
- 选中区域：`redAccent`；
- 标记和辅助文字：白色/白色 70%。

Painter 无 `BuildContext`，应由构造函数接收当前主题或 Body 专用颜色策略。

### Body 组织分类色

文件：`lib/core/body/models/body_region.dart`

bone/muscle/joint/organ 色板属于数据语义，默认豁免；禁止把页面文字、按钮或容器颜色混入该业务色板。

## 4.7 部分 Lab Demo

### `ApiTestDemo`

文件：`lib/lab/demos/api_test_demo.dart`

具体组件：

- `_buildApkTab`；
- `_buildAutoDownloadCard`；
- `_buildApkFileCard`；
- `_outlinedBtnStyle`。

问题：大量蓝/绿/红/灰/indigo/deepPurple/orange/teal 固定 UI 色，以及 `green[50]/blue[50]` 浅色状态卡片。属于 P1 整改对象。

### `ApiSpeechTabPage`

文件：`lib/lab/demos/api_test/api_speech_tab.dart`

问题区域：

- 清空按钮；
- Streaming 开关；
- 成功/警告/失败/信息状态卡片；
- 模式按钮；
- 辅助文字。

状态颜色应迁移至 success/warning/error/info 的 container 与 onContainer 角色。

### `PigmentPaletteDemo`

文件：`lib/lab/demos/pigment_palette_demo.dart`

具体组件：

- 页面固定背景 `#F7F7F4`；
- 主文字 `#111111`；
- 次文字 `#6B6B6B`；
- `_HeroPanel`；
- `_SectionCard`；
- `_GroupedListCard`；
- `_MetricChip`；
- `_StatusRow`；
- `_ActionButton`。

若此 Demo 的目的为展示固定颜料视觉，可登记豁免；否则其页面背景和文字属于 P1 主题缺陷。

### `StackCardDemo`

文件：`lib/lab/demos/stack_card_demo.dart`

具体组件：`_card`、`_topEdge`、`_tab`、`_inner`。

堆叠卡片使用固定演示配色。若仅展示动画可豁免；若作为通用 UI 示例，应迁移到 `surface/primaryContainer/outlineVariant`。

### `WebBookmarkDemo`

文件：`lib/lab/demos/web_bookmark_demo.dart`

具体组件：

- `_BookmarkGridView`；
- `_IconTypeOption`；
- `_BookmarkCard`；
- `_EditModeWrapper`；
- `_WebViewPage`。

网站 favicon 和品牌色豁免；编辑按钮、输入框、卡片背景、选中边框必须走主题。

### `TorchDemo`

文件：`lib/lab/demos/torch_demo.dart`

补光实际输出色、色相环和预设颜色豁免。需要主题化的外围 UI：

- `_buildModeSelector`；
- `_buildModeButton`；
- 设置卡片；
- `_buildKeepScreenOnSwitch`；
- `_buildLargeButton`；
- 普通页面文字、边框和错误提示。

### `Game2048Demo`

文件：`lib/lab/demos/game_2048_demo.dart`

方块和棋盘规则色默认豁免。需单独检查：页面 Scaffold、分数面板、普通按钮、Dialog 和非棋盘文字。

### `ReactionTestDemo`（刻意豁免，非缺陷）

文件：`lib/lab/demos/reaction_test_demo.dart`

主屏相位底色**就是**交互指令（waiting 红 = 别点 / ready 绿 = 可以点），
用户要在几百毫秒内靠颜色做判断，因此固定色集中在 `ReactionPalette`，
底色 + 主前景 + 次级前景成对固定（不靠 alpha 叠色）。外围 UI（AppBar）仍走 `ColorScheme`。

登记理由——若不豁免、改回从 `ColorScheme` 派生，各主题实测如下：

| 主题 | 症状 | 程度 |
| --- | --- | --- |
| 墨白 ink | `primary == onSurface == #1A1A1A`，ready 与 idle 底色完全相同，"变绿"那一刻画面零变化 | 功能不可用 |
| 暮紫 purple | ready(primary) 与 waiting(error) 同为紫粉色系，红绿语义同时失效 | 功能不可用 |
| 粉雾海盐 rose | ready(primary) 粉红比 waiting(error) 深红更"危险"，语义近似反转 | 功能不可用 |
| 柠檬鼠尾草 lemon | ready(primary) 是柠檬黄，绿语义丢失 | 语义弱化 |
| 茶禅 zen | primary 恰为灰绿，仅属巧合可用 | 巧合可用 |

守卫测试：`test/lab/demos/reaction_test_demo_test.dart`（主题 × 4 相位 + 对比度 ≥4.5:1）。

## 5. 整改优先级

### P0：切换主题后明显错误

- [ ] `ZenText.body/label/title/monoDigit*`
- [ ] `ZenSection` 标题
- [ ] `zenPageScaffold` 标题
- [ ] `CalendarSettingsPage._GroupTile`
- [ ] `CalendarImportDialog`
- [ ] `BlockEditorDemo._proxyDecorator`
- [ ] `NotePanel` 与 `_NoteListTile`
- [ ] `TypePanel`
- [ ] `AIChatSettingsPage` 成功/信息卡片
- [ ] `AgentChatPage._MessageBubble`
- [ ] `SystemMessagesPage` 清空按钮
- [ ] `SystemMessagesPanel._EmptyState`
- [ ] `WaterCapsuleMessageWidgetStrategy`：整改或登记豁免
- [ ] `RecordSheet`
- [ ] `BodyBlockPainter`

### P1：普通 UI 仍部分硬编码

- [ ] `zenCard/zenDottedZone/zenButton` 消费者迁移
- [ ] `BlockCard` AI Diff 区域
- [ ] `EditToolbar`
- [ ] `AiConversationOverlay`
- [ ] `DiffViewer`
- [ ] `FormatCompatibilityPage`
- [ ] `ReceiptOcrPage`
- [ ] `SystemEventMessageWidgetStrategy`
- [ ] `LoginMessageWidgetStrategy`
- [ ] `RegisterMessageWidgetStrategy`
- [ ] `ApiTestDemo`
- [ ] `ApiSpeechTabPage`
- [ ] `PigmentPaletteDemo`：整改或登记豁免
- [ ] `StackCardDemo`：整改或登记豁免

### P2：业务色与主题色边界确认

- [ ] `BillOverviewMessageWidgetStrategy` 图表色是否改用 `category`
- [ ] Body 组织分类色登记豁免
- [ ] Torch 实际补光色登记豁免
- [ ] 2048 方块色登记豁免
- [x] `ReactionTestDemo` 信号灯色登记豁免（`ReactionPalette`，主屏底色/前景成对固定，AppBar 仍走主题）
- [ ] Web Bookmark 品牌色登记豁免
- [ ] 棋盘、棋子、地形色登记专用通道
- [ ] 小说阅读器纸张主题登记组件级独立主题

## 6. 建议颜色映射

| 当前硬编码用途 | 建议主题角色 |
| --- | --- |
| 普通蓝色选中态 | `colorScheme.primary` / `primaryContainer` |
| 普通卡片背景 | `surface` / `surfaceContainerHighest` |
| 普通文字 | `onSurface` |
| 次级文字、灰色图标 | `onSurfaceVariant` |
| 分隔线、灰色边框 | `outlineVariant` / `outline` |
| 删除/失败 | `error/onError/errorContainer/onErrorContainer` |
| 成功 | `AppColorsExtension.success/...Container` |
| 警告 | `AppColorsExtension.warning/...Container` |
| 信息 | `AppColorsExtension.info/...Container` |
| 图表分类色 | `AppColorsExtension.category` |
| 固定白色按钮前景 | 对应背景角色的 `onPrimary/onError/onTertiary` |
| 固定黑色遮罩 | `scrim` 或 `onSurface` 派生透明度 |
| 固定黑色阴影 | `shadow` 派生透明度 |

## 7. 审计复核清单

每次整改后至少人工检查：

- [ ] `zen` 主题显示正常；
- [ ] `ink` 主题不存在 Sage/默认蓝色残留；
- [ ] `purple` 深色主题不存在固定浅灰、浅蓝、浅红面板；
- [ ] 标题、正文、辅助文字具有足够对比度；
- [ ] 按钮使用背景对应的 `on*` 前景色；
- [ ] success/warning/info/error 同时检查前景和 container；
- [ ] Painter 接收主题颜色，而非内部读取固定 Material 色；
- [ ] 合理业务色已明确登记豁免，不与普通 UI 颜色混用；
- [ ] 搜索新增的 `Colors.xxx` 和 `Color(0x...)`，逐项解释或整改。

建议复扫命令：

```powershell
rg -n --glob '*.dart' 'Color\(0x|Colors\.[A-Za-z]|ZenColors\.' lib
rg -n --glob '*.dart' 'ZenText\.' lib
rg -n --glob '*.dart' 'Theme\.of\(|context\.colors|context\.boardColors|context\.gameColors' lib
```

## 8. 审计维护规则

新增硬编码颜色时必须满足以下之一：

1. 位于主题 token、`ColorScheme` 或 `ThemeExtension` 定义层；
2. 属于品牌、游戏规则、数据语义或内容主题，并在本文件登记豁免；
3. 是 `Colors.transparent`；
4. 有明确对比度约束，且普通主题角色无法表达；
5. 否则必须改用主题通道。

新增普通 UI 组件时优先级：

```text
标准 Material 角色 -> ColorScheme
应用状态/分类角色 -> AppColorsExtension
通用简化角色 -> context.colors
棋盘 -> context.boardColors
游戏内容 -> context.gameColors
独立内容主题 -> 明确的组件级 ThemeExtension/Strategy
```

## 9. 用色审计快照与迁移史（v6.2 → v6.2.1 → v6.4，2026-08 ~ 2026-10）

> 本节自 skill 册《Ec02-用色审计》外迁归档（2026-11-20）：审计快照、迁移批次史与架构议题属治理史，不进 skill；册内只保留审计 SOP 与目录推荐通道速查。
> **本节所有数字都是快照，不是实时值**——各节数据分属不同统计时点（已标注），引用前先重跑 skill 册《Ec02-用色审计》§1 的命令现场重测。
> 数据基线：v6.2 重构（5 strategy 拆出）+ tetris 特例修正（commit 24d91ea1，2026-08-29）+ v6.2.1 新增 ChessColorStrategy（第 6 个 strategy）+ v6.4 补账。

### 9.1 迁移状态史

**5 批迁移 + v6.2 收尾 + v6.2 特例修正 + v6.2.1 新增 ChessColorStrategy 全部落地**
（124 处豁免 + 65 处迁移 + 86 处 BoardTheme 令牌 + 2 处特例 strategy + **1 处新增 strategy 通道**）。

#### v6.2.1 关键变化（chess 新通道）
- `lib/design_tokens/color/chess.dart`（13 角色 + *From() 派生）
- `lib/core/theme/colors/strategy/chess_color_strategy/`（13 角色抽象 + Default 实现 + 单例缓存）
- `lib/core/theme/extensions/chess_color_strategy_extension.dart`（注入器）
- `lib/core/theme/context/chess_colors.dart`（`context.chessColors` 快捷入口，双层兜底）
- `lib/core/theme/colors/factory.dart` 注册 `createChessColorStrategy`
- `lib/core/theme/app_theme.dart` `_buildTheme` 注入 6 个 strategy（5→6）
- **测试**：`test/core/theme/chess_color_strategy_test.dart`（12 个回归断言：单例缓存、派生正确性、==/hashCode）

#### v6.2 关键变化
- `lib/core/theme/colors/strategy/`（5 strategy 独立目录，替代原 `lib/core/theme/strategy/`）
- `lib/design_tokens/color/palettes/<mode>.dart`（5 主题色板独立文件，替代原 `semantic/colors.dart`）
- 5 strategy：ColorStrategy / BoardColorStrategy / **TetrisColorStrategy（特例）** / **TeamAvatarColorStrategy（特例）** / **TorchProtectColorStrategy（scheme 派生）**
- 5 消费通道：context.colors / context.boardColors / **context.tetrisColors** / **context.teamAvatar** / context.sudokuColors
  （`context.torchProtect` **不在其中**——扩展已注册但无 context 入口）

#### tetris 特例修正（commit 24d91ea1）
- 根因：v6.2 重构把 pieceColors 改 `List<Color>` 0..6 + 从 scheme 派生 → L 块 type 7 越界 + 1..6 颜色错位 + 棋盘环境跟主题漂移
- 修法：4 角色全 native const + pieceColors 改 `Map<int, Color>` 1..7 + `DefaultTetrisColorStrategy` 不参与派生 + shouldRepaint 还原 `=> true`
- 新增 15 个回归测试（`test/lab/tetris_lua/`，本地 .gitignore）：7 色 hex 逐项断言 + 越界保护 + 跨主题锁定

### 9.2 残留 hex 分类快照（2026-08，v6.2.1 后，合计 224 处）

| 分类 | 数量 | 说明 |
| --- | --- | --- |
| **S 令牌系统** | 86 | surround_game (54) + reversi (32) 的 `BoardThemeData` 独立令牌，与 `context.boardColors` 平级 |
| **E 豁免** | 124 | 全部带 `主题豁免` 注释（品牌色/国际识别色/纸质书视觉/医学解剖色/sage 家族…） |
| **特例 strategy** | 14 | `tokens/color/tetris/` (8) + `tokens/color/team/` (6) — 架构决策保留 |
| **新增 strategy 通道** | 0 | `tokens/color/chess/` 13 角色基础色 + 13 *From scheme 派生 → 0 残留 |
| **未分类** | **0** | — |

### 9.3 顶层目录用色规模（2026-10 快照）

| 目录 | Theme.of 文件数 | colors | board | chess | tetris | teamAvatar | torchProtect | 角色 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `lib/core/` | 133 | 47 | 5 | 11 | 2 | 3 | 1 | 业务核心模块（游戏/笔记/AI 聊天/表格） |
| `lib/lab/` | 75 | 34 | 4 | 1 | 1 | 1 | 0 | Demo 实验场 |
| `lib/screens/` | 20 | 1 | 0 | 0 | 0 | 0 | 0 | 主壳 + 设置 |
| `lib/services/` | 9 | 0 | 0 | 0 | 0 | 0 | 0 | 消息/图片 service |
| `lib/core/ui/` | 16 | 5 | 0 | 0 | 0 | 0 | 0 | Base* 组件 + 5 个 context 扩展入口 |

> 计数口径 = **文件数**（`grep -rl '<token>' <dir> --include='*.dart' | wc -l`）。
> `lib/core/` 的 board=5 / chess=11 / torch=1 里包含 `lib/core/theme/` 下的定义文件与注释引用；真正的外部消费点见 §9.4。

### 9.4 各通道使用点清单（2026-10 快照）

#### `context.colors`（6 角色抽象，scheme 派生）
覆盖 **82 个文件**（`grep -rl 'context\.colors\b' lib/`），分布见 §9.3（lab 34 + core 47 + screens 1 + core/ui 5）。`lib/core/ui/*.dart`（5 个文件）全部走 ColorStrategyExtension。

#### `context.boardColors`（11 角色，scheme 派生）
使用点 **4 个文件**：
- `lib/lab/demos/go_lua/go_board.dart`、`widgets.dart`
- `lib/lab/demos/gomoku_lua/board.dart`、`widgets.dart`

> `lib/lab/demos/tetris_lua/board.dart` 走的是 `context.tetrisColors` 特例，**不是**本通道。
> S 级并存系统：`surround_game` 与 `reversi` 用各自的 `BoardThemeData` 令牌，是架构决策保留的独立通道（议题见 §9.9）。

#### `context.chessColors`（13 国际象棋角色，scheme 派生，v6.2.1 新通道）
使用点 **9 个文件**（国际象棋 UI 已接入）：`lib/core/chess/chess.dart`、`p2p/chess_room_page.dart`、`skins/chess_skin_settings_page.dart`、`widgets/{board_palette,chess_board,chess_piece,chess_replay_bar,promotion_panel}.dart`、`lib/lab/demos/chess_online_demo.dart`。
特殊豁免（未来 chess 模块）：棋子图案走 asset bundle，棋子本身不消费 `player1Stone / player2Stone`（棋子是图片而非纯色），仅棋盘底色 / 选中格 / 走法提示 / 将军警告等环境色走 strategy 派生。

#### `context.tetrisColors`（3 角色 + 7 方块色 Map，native const 特例）
使用点 1 个：`lib/lab/demos/tetris_lua/board.dart`（3 处 `pieceColors[...]!`：`:140` / `:168` / `:366`）。切任意主题 3 个颜色角色 + 7 方块色完全不变。

#### `context.teamAvatar`（6 头像色，native const 特例）
使用点 2 个：`lib/lab/demos/team_card/widgets.dart`、`lib/core/net_engine/relay_v3/participants_grid.dart`（v6.2 批迁入：12 头像色 → 6 头像色）。

#### `context.torchProtect`（4 个 UI 环境角色，scheme 派生）——无 context 入口
strategy 只承载 4 个护眼 UI 角色（protectWarmYellow/Orange/Neutral/CoolWhite），extension 已在 `app_theme.dart:156` 注册，但 `lib/core/theme/context/` 下无 torch 扩展文件，`grep -rn "get torchProtect" lib/` 0 命中 → `context.torchProtect` 不可用。10 种补光预设**不走本通道**：`lib/design_tokens/color/torch.dart` 的 `TorchColors.presets` 是补光实际输出色（主题豁免 const 表），2026-10 起由 `torch_demo.dart` 直连消费（单一来源设计）。

### 9.5 用色热点 Top 20（2026-10 快照）

> 计数 = `Theme.of(context)` 单文件出现次数。

| 文件 | 调用数 | 备注 |
| --- | --- | --- |
| `lib/lab/demos/storage_analyze_demo.dart` | 82 | 存储分析，文件大 |
| `lib/core/novel_reader/novel_reader_page.dart` | 61 | 阅读器主壳 |
| `lib/lab/demos/web_bookmark_demo.dart` | 48 | 书签编辑器 |
| `lib/lab/demos/pigment_palette_demo.dart` | 41 | 配色 demo |
| `lib/core/word_drag/pages/word_drag_page.dart` | 39 | 单词拖拽 |
| `lib/core/doubletime/doubletime_page.dart` | 33 | 时间双线 |
| `lib/lab/demos/torch_demo.dart` | 31 | 护眼灯 |
| `lib/lab/demos/notion_image_host_demo.dart` | 28 | 图床 |
| `lib/lab/demos/coup_lua/widgets.dart` | 26 | 卡牌游戏 |
| `lib/core/net_engine/pages/net_engine_debug_page.dart` | 26 | 网络调试 |
| `lib/core/novel_reader/page_curl_view.dart` | 25 | 翻页视图 |
| `lib/lab/demos/tetris_lua/widgets.dart` | 23 | 俄罗斯方块 HUD（棋盘色走 `context.tetrisColors`） |
| `lib/lab/demos/game_2048_demo.dart` | 22 | 2048 |
| `lib/core/focus/focus_timer_page.dart` | 22 | 专注计时 |
| `lib/lab/demos/volume_decay_demo.dart` | 20 | 音量衰减 demo |
| `lib/lab/demos/network/network_env_cards.dart` | 20 | 网络环境卡 |
| `lib/screens/profile/lab/game_center/game_center_cards.dart` | 19 | 游戏中心卡片 |
| `lib/screens/profile/lab/lab_panel/lab_panel_content.dart` | 18 | Lab 面板内容 |
| `lib/lab/demos/team_card/widgets.dart` | 18 | 团队卡（用 `context.teamAvatar`） |
| `lib/lab/demos/reversi_lua/widgets.dart` | 18 | 黑白棋 |

### 9.6 残留 Color(0xFF) 664 处分类（2026-10 快照）

> 口径 = `grep -rn "Color(0xFF" lib/ --include="*.dart" | grep -v "lib/core/theme/" | wc -l`。合计 **664**。

| 目录 | 计数 | 归属 | 豁免理由 / 系统说明 |
| --- | --- | --- | --- |
| `lib/design_tokens/color/` | 328 | **token 层** | 7 套 palettes（zen 37 + 其余 6 套各 43）+ torch 10 + sudoku 9 + tetris 8 + team 6。token 文件本身就是色值真源，不算"残留" |
| `lib/core/surround_game/` | 54 | **S** | `BoardThemeData` 令牌系统（warm/cool 两套预设，6 层视觉栈） |
| `lib/lab/demos/` | 43 | **E** | reaction_test 13 / web_bookmark 15（demo 10 + provider 5）/ tetris_lua 12 / game_2048 3 |
| `lib/core/reversi/` | 36 | **S 32 + E 4** | 32 同 surround_game；4 是 Othello 国际识别色 |
| `lib/core/xiangqi/` | 30 | **S** | 象棋棋盘/棋子令牌（与 surround/reversi 同类，2026-10 新增模块） |
| `lib/core/ui/` | 30 | **E** | `shell/app_notification.dart` 29（4 语义 × 明暗双模固定配色）+ `global_ring/ring_bubble.dart` 1 阴影 |
| `lib/screens/profile/` | 26 | **E** | game_center 封面渐变 / character_profile 皮肤色 / lab_panel delete 红 |
| `lib/core/novel_reader/` | 26 | **E** | 纸质书视觉语言：纸张底色/棕色墨水/烫金封面渐变 |
| `lib/core/draughts/` | 14 | **S** | `DraughtsBoardPalette` 棋具令牌（对齐 surround/reversi 先例） |
| `lib/core/chess/` | 14 | **E** | 玩家身份对（蓝/橙）+ 皮肤预设色（v6.2.1 新模块） |
| `lib/core/game_kit/` | 12 | **E** | `chat/board_chat_overlay.dart` F2 设计移植保真配色 |
| `lib/core/timetable/` | 9 | **E** | 莫兰迪课程色（light 主题专属）+ sage 1 |
| `lib/core/focus/` | 9 | **E** | sage 家族 zen 风识别 |
| `lib/core/body/` | 8 | **E** | 医学解剖标准色（骨蓝/肌红/关黄/器绿） |
| `lib/core/jungle_chess/` | 7 | **E** | 斗兽棋国际识别色（暖米盘/浅蓝河/金兽穴/红蓝方） |
| `lib/core/remotetype/` | 6 | **E** | 虚拟手柄按键识别色（A/B/X/Y，2026-10 新增模块） |
| `lib/core/line/` | 6 | **E** | 音游评级奖励渐变（P 粉紫蓝 / S 金橙） |
| `lib/services/message_strategy/` | 5 | **E** | 消息策略拟物水体等固定色（带 `主题豁免` 注释） |
| `lib/app_lifecycle/` | 1 | **E** | `globals_error_guard.dart` 错误色 |

> 表里的"归属"列是**按模块性质归纳**的，不是逐条核对豁免注释得到的统计；逐条判定必须跑命令 + 读源码 `主题豁免` 注释。
> 特例 strategy 单独计：`lib/design_tokens/color/tetris.dart`（8 处）、`team.dart`（6 头像色）、`torch.dart`（10 预设）——已含在上面 328 里。

### 9.7 迁移批次史（批次 1–9）

| 批 | 目录 | 迁移数 | 改法摘要 |
| --- | --- | --- | --- |
| 1 | doubletime / message_strategy / word_drag | 21 | painter scheme 注入；PieChart 加 categoryColors；CategoryBucket.color 死字段删除 |
| 2 | timetable / net_engine / focus | 14 | TimetableColors → 函数式（BuildContext）；kParticipantColors → avatarColors；TimePageMeta.color 删 → colorFor() |
| 3 | profile / jungle_chess / body / line | 8 | lab_panel delete → scheme.error；jungle 5 色 → 顶层函数式 |
| 4 | novel_reader | 6 | 错误/绿色强调 → scheme.error/tertiary |
| 5 | lab/demos | 16 | bottom_bar 死字段删；reaction 5 phase → scheme；bookmark 2 处迁 |
| 6（v6.2 收尾） | 全 lib 调用点 | 17 文件 | `zenButton` → `zenButtonTheme` 签名迁移；删 `ZenColors` 兼容层；zen 主题 5 色校准；calendar_import_dialog 最后 1 处 → scheme；recorder `zenCard` → `zenCardTheme` |
| 7（v6.2.1 特例修正） | tetris_lua + tetris_color_strategy | 4 文件 | `pieceColors` 改 Map 1..7 + 4 角色 native const + shouldRepaint `=> true` + 新增 15 回归测试 |
| 8（v6.2.1 新通道） | chess token/strategy/extension/factory/app_theme/context/test | 7 文件 | `ChessColorStrategy` 第 6 个 strategy：13 角色 from scheme 派生 + ThemeExtension + context 双层兜底 + 12 单元测试 |
| 9（v6.4 补账，2026-10-18） | bill_overview_message_strategy (6) / draughts_room_page (3) / chess player_strip (1) | 10 处 M | 环形图 6 色 → `AppColorsExtension.category`；`_colorDot` → `DraughtsBoardPalette.light.*`；meta 灰 → `context.colors.textMuted` |

#### v6.4 补账：E 豁免标注补齐（块级/文件级，逐项）

- `draughts_board.dart` `DraughtsBoardPalette`：S 级模块棋具令牌（对齐 surround/reversi 先例），类注释逐项列出
- `chess_skin_settings_page.dart`：皮肤预设/底板色板 = 用户可选识别色数据（两处块注释）
- `chess player_strip` 蓝/橙身份对 + 白/黑棋子点：身份识别色（F2 设计规格），doc 注释逐项
- `board_chat_overlay.dart`：F2 设计移植保真（1A1A1A 硬黑 / FAFAF7 --bg / 9B9B9B --text-2 / 2A6FDB-C2410C 身份对），文件头逐项
- `tetris_lua/widgets.dart` 霓虹 HUD 7 色 + `board.dart` lerp 端点 2 处：固定皮肤（对齐 tetris 特例逻辑）
- `app_notification.dart`：4 语义 × 明暗双模固定配色系统，类注释逐项
- `web_bookmark/providers` 5 品牌色、`body_region.dart` 8 医学解剖色、`canvas_reader_engine.dart` 3 纸张主题、`line` 评级色 5 处、`focus` sage/workflow 措辞标准化、`water_capsule` 拟物水体 3 处、`globals_error_guard` 1、`ring_bubble` 阴影 1

> v6.4 补账后残留 301 处（统计口径/时点与 §9.6 不同，引用前现场重测）全部有归属。

#### v6.4 补账：几何令牌决断（同批落地）

- `lib/design_tokens/radius.dart` / `spacing.dart` **接通**：`app_theme._buildTheme`（卡片/FAB xl、按钮 lg）、`base_button`（xs）、`base_section`（sm + `AppSpacing.sm`）、`zen_theme`（sm/xs）——组件层零视觉变化接线（token 实际路径没有 `tokens/` 中间层，仓库根下就是 `lib/design_tokens/`）
- `lib/design_tokens/elevation.dart` **删除**（API 形态不匹配：ThemeData 收 shadowColor 而非 BoxShadow 列表，0 消费者）
- `spacing.dart` 内 `AppInsets` **删除**（预设值与实际排版值错位，0 消费者）

### 9.8 历史踩坑文件清单（迁移时排查入口）

> 这些文件在历次主题迁移中**至少踩过 1 次主题色坑**。修法与根因的当前权威版本在 skill 册《Ec01 扩展SOP与迁移》§4.5；本清单保留为排查史索引。

| 文件 | 踩过的坑 |
| --- | --- |
| `lib/lab/demos/clock_demo.dart` | 嵌套 `MaterialApp` 只复制 4 个字段，子树退回 Flutter 默认配色 |
| `lib/lab/demos/calendar_demo.dart` | `Navigator.push` 推出后查不到 `LabCalendarProvider`，红屏崩溃（需 `MultiProvider` + `.value` 显式传） |
| `lib/lab/demos/web_bookmark_demo.dart` | 卡片 `backgroundColor: onSurface`、selector `withAlpha(51)`、`surfaceVariant` deprecated |
| `lib/core/word_drag/pages/word_drag_page.dart` | 拖拽背景 `onSurface`（深底） |
| `lib/core/word_drag/widgets/word_card_content.dart` | 定义/例句容器用 `onSurfaceVariant` / `primary` 等不协调角色 |
| `lib/core/ui/global/renderers/markdown_renderer_widget.dart` | code/codeblock 背景 `surfaceContainerHighest`（深） |
| `lib/core/ui/global/zen/main.dart` `zenPageScaffold` | `backgroundColor: surfaceContainerHighest`（深） |
| `lib/core/theme/app_theme.dart` `appBarTheme` / `bottomNavigationBarTheme` | 背景 `surfaceContainerHighest`（深） |
| `lib/lab/demos/crash_log_demo.dart` 等 4 个 demo | AppBar `backgroundColor: inversePrimary`（暗沉互补色） |
| `lib/design_tokens/color/palettes/lemon.dart` / `rose.dart` | `outline`/`outlineVariant` 鲜艳，与主题调性冲突 |
| `lib/design_tokens/color/palettes/purple.dart` | `surface` 被基于错误诊断改亮 → 暮紫丢失"鎏金暖黑底"质感（ColorScheme 改动必须有"为什么"注释） |
| `lib/lab/demos/notion_image_host_demo.dart` | 拍照/输入框底色 lerp 强度反复调试（§0.1 大色块契约规则） |
| `lib/core/novel_reader/novel_reader_page.dart` | "全部豁免"注释含不该豁免的封面渐变；占位卡边框硬编码绿 |
| `lib/design_tokens/color/tetris.dart`（v6.2） | pieceColors 改 List 0..6 + scheme 派生 → 越界 + 错位 + 漂移（《Ec03 特例豁免》§1） |

### 9.9 v7 架构议题（未做，已记录）

surround_game + reversi 的 `BoardThemeData`（86 处 hex）是否整合进 `context.boardColors`：
- **保持现状**（推荐）：两系统各有 warm/cool 预设和多角色 3D 效果色，整合成本高、收益低
- **整合**：统一棋牌策略通道，但 BoardColorStrategy 现有 11 角色无法覆盖 BoardThemeData 的 30+ 角色（棋子高光/边缘暗部/墙面高光…），需扩接口

tetris 特例是否扩展为更通用的"识别色 strategy"模板：
- **保持现状**（推荐）：tetris / teamAvatar 各一个 strategy，简单清晰
- **提取模板**：写 `RecognizableColorStrategy<T>` 抽象，强制 `Map<int, Color>` + native const —— 抽象层对未来扩展收益不大
