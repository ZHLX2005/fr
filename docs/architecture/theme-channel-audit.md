# 全局主题通道与硬编码组件审计

> 审计范围：`lib/**/*.dart`  
> 审计日期：2026-06-16  
> 审计目标：确认当前主题种类、主题通道覆盖情况，以及切换主题后仍保留固定颜色的具体组件。

## 1. 结论摘要

当前全局提供 3 套主题：

| 模式 | 显示名称 | 明暗 | 视觉方向 |
| --- | --- | --- | --- |
| `AppThemeMode.purple` | 暮紫主题 | 深色 | 暮紫主色 + 鎏金暖黑环境 |
| `AppThemeMode.zen` | 茶禅主题 | 浅色 | Sage 绿 + 暖米环境 + 陶土红强调 |
| `AppThemeMode.ink` | 墨白主题 | 浅色 | 墨黑 + 纸白 + 墨赭强调 |

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
- 网站、平台和第三方品牌色；
- 医学组织分类、痛感梯度等数据语义色；
- 图表分类色，但建议优先评估 `AppColorsExtension.category`；
- 手电筒、屏幕补光、颜料色板等功能实际输出色；
- 小说阅读器纸张、墨色等独立内容主题；
- `Colors.transparent`；
- 为保证内容对比度而经过明确验证的固定前景色。

## 3. 当前主题通道

### 3.1 Material `ColorScheme`

入口：`lib/core/theme/app_theme.dart`、`lib/core/theme/semantic/colors.dart`

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

入口：`lib/core/theme/semantic/extensions.dart`

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
