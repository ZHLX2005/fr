# 组件复用与组件化审计

> 审计范围：`lib/core/ui/**`、`lib/core/*/**`（含 p2p / lobby / ui）、`lib/lab/demos/**`、`lib/design_tokens/**`、`lib/screens/**`
> 审计日期：2026-10-23
> 更新：2026-10-24 起，联机 UI 件统一聚合至 `lib/core/ui/game/`（game_ready_style / game_lobby_page / _lobby_form / board_chat_overlay / emoji_overlay / emoji_panel / relay_connection_bar / relay_connection_status_badge）。文中涉及的 `game_kit/lobby|chat|emoji/` 与 `net_engine/relay_v3/` 旧路径以本行为准；判定契约见 skill 的 Ec01「联机 UI 拆分口径」。
> 审计目标：盘点当前组件资产与复用实况，识别「已有但未复用」「重复造轮子」「层级错位」「视觉分叉」四类问题，给出可复用的组件化收敛清单。
> 证据口径：以当前源码为准；行号随代码变动失效，重跑命令见 §10。
> 本轮只做审计与建议，未修改应用代码。

## 1. 结论摘要

一句话：**项目不缺组件，缺的是「组件层被主体模块使用」这件事本身。**

| 事实 | 数据 | 证据 |
|---|---|---|
| 共享 UI 层被引用比例 | 983 个 dart 文件中仅 **62 个（6.3%）**引用 `lib/core/ui/*` | `grep -rlE "core/ui/(atomic\|shell\|zen\|lab\|renderers\|global_ring)" lib` |
| 其中 `lib/core` + `lib/screens` | 仅 **24 个** | 同上 |
| `lib/lab/demos` 独占 | **29 个** | 共享层事实上只服务 clock / recorder / relation_calc 三个 demo |
| 原子组件数量 | **7 个**（`lib/core/ui/atomic/`，合计约 500 行） | `ls lib/core/ui/atomic` |
| 其中零业务引用 | `base_button` / `base_icon_button` / `base_swipe_action` / `base_dot` **4 个** | §2.1 |
| 确认弹窗重复 | 全仓 `AlertDialog(` **77 处**，已有 `BaseConfirmDialog` 仅 1 处调用 | §3.1 |
| 提示条重复 | 全仓 `showSnackBar(` **226 处**（`lib/core` 内 141），已有 `AppNotification` 仅 4 次实际调用 | §3.1 |
| 图标按钮重复 | 全仓裸 `IconButton(` **174 处**（`lib/core`+`lib/screens` 88），已有 `BaseIconButton` 业务侧 0 处 | §3.1 |
| 空态重复 | **14 个**手写空态 widget 类 + 14 处 `Icon(size: 64)`，已有 `BaseEmptyState` 仅 1 处业务调用 | §3.1 |
| chip / badge 无共享实现 | **24 个**私有 chip/badge 类 + 10 个公开 badge 类，散落 12+ 模块 | §3.2 |
| 对局页骨架重复 | 7 个 lua 对局页共 **7422 行**，`_buildLobby` 6/7 相似度 **96.7%–99.9%** | §4.2 |
| `GameReady*` 五件套分叉 | core 4 个房间页全用，7 个 lua demo **全部手写等价物** → 同屏两套样式 | §4.3 |
| 脚本层能力缺口 | 9 个 lua demo 脚本 **0 处**引用 CHAT/EMOJI 共享段 → 收不到聊天/表情 | §4.5 |
| 硬编码颜色 | 719 处 `Color(0x…)`（332 处在 `lib/design_tokens/color` 属 token 定义）+ 21 处 `withOpacity` | §6 |
| 计划-代码漂移 | `plan/game-kit-unification.md` Conventions 明令消灭「每游戏各挂 BoardTheme」，实际 52 处 `BoardThemeData` 参数仍在 | §4.6 |

### 四类问题与优先级

| 优先级 | 类别 | 概要 | 章节 |
|---|---|---|---|
| **P0** | 已有组件的漏用 | 4 个 atomic 零业务引用；全仓 77 处 `AlertDialog`、226 处 `showSnackBar`、14 个手写空态类、174 处裸 `IconButton` 各自手写 | §3.1 |
| **P0** | 视觉分叉 | `GameReady*` 五件套在 demo 侧手写分叉，房间号胶囊在应用内呈两种样式且 demo 版不跟随主题 | §4.3 |
| **P1** | 确实缺失的通用件 | `BaseSheetScaffold` / `BasePromptDialog` / `BaseChatBubble` / `BaseListRow` / `BaseTopBar` / `BaseLoadingState` / `BaseLogPanel` | §3.2、§5.2 |
| **P1** | 对局页壳层未收敛 | `GameRoomShell` / `OnlineRoomScaffold`（`plan/game-kit-unification.md` Phase 4，尚未开工） | §4.4 |
| **P1** | 脚本层共享段未接入 | `assembleLuaScript` + 聊天/表情共享段只有 4 个 core 脚本接入，9 个 demo 脚本是单体 raw string | §4.5 |
| **P2** | 层级错位 | `BoardThemeData` 定义在游戏模块内被跨游戏消费；`ios_dialog.dart`（309 行通用弹窗套件）寄居 `gallerymanage` | §3.3、§4.6 |
| **P2** | 主题通道断层 | 8 个业务模块 `context.colors` 使用次数为 0，语义色各模块自定 | §6 |

**先做 P0 的理由**：改造成本最低（都是「已有组件被漏用」），不需要新设计，且能立刻把组件层引用率从 6.3% 拉起来——这一步不做，后面新建的组件同样会无人使用（`BaseButton` 即是前车之鉴）。

## 2. 共享组件层（lib/core/ui）实况

### 2.1 组件清单与采用率

| 组件 | 文件:行 | 业务侧引用 | 结论 |
|---|---|---:|---|
| `BaseSection` | `lib/core/ui/atomic/base_section.dart:14` | 9（集中在 `timetable/service/config/` + clock demo） | 语义等价的手写版仍在别处，见 §3.1 |
| `BaseEmptyState` | `lib/core/ui/atomic/base_empty_state.dart:14` | 5 | 同上（14 个手写空态类待收编） |
| `BaseIconButton` | `lib/core/ui/atomic/base_icon_button.dart:17` | 6 | 业务侧 0 处；全仓裸 `IconButton(` **174 处**（`lib/core`+`lib/screens` 88），且 `tooltip` 零命中（可访问性缺口）；`BoxShape.circle` 128 处 |
| `BaseConfirmDialog` | `lib/core/ui/atomic/base_dialog.dart:12` | 7 | 业务侧仅 1 处；全仓 77 处 `AlertDialog(` 手写，见 §3.1 |
| `BaseDot` | `lib/core/ui/atomic/base_dot.dart:18` | 3 | 业务侧 0 处；`lib/core/remotetype/canvas/rt_touch_surface.dart:506` `RtConnDot` 是域内平行实现 |
| `BaseSwipeAction` | `lib/core/ui/atomic/base_swipe_action.dart:9` | 1 | 业务侧 0 处；形态与现有 `Dismissible` 用法不匹配，见 §3.1 |
| `BaseButton` | `lib/core/ui/atomic/base_button.dart:13` | **0**（仅 `base_empty_state.dart` import） | **死代码**，且与 `EmphasisButton` 职责重叠，见 §2.3 |

shell 层：`EmphasisButton` **84 处调用 / 35 个文件**（`lib/core/ui/shell/emphasis_button.dart`）、`QuickNavBottomBar` 10 处、`AppNotification` 2 处、`NavEntryIcon` 4 处。
zen 层：`zen_theme.dart` 27 处、`zen_date_picker.dart` 2 处。

### 2.2 层架构存在但层号漂移

项目已有真实分层，头部注释即以 `// Layer N:` 声明：

| 层 | 位置 | 例子 |
|---|---|---|
| Layer 1 | `lib/design_tokens/` | `radius.dart`（`AppRadius` 4/6/8/12/16/24）、`spacing.dart`（`AppSpacing` 4/8/12/16/24/32/48）、`color/` |
| Layer 1–3 | `lib/core/theme/colors/strategy/` | `ColorStrategy` 契约、各游戏 strategy、`ThemeExtension` 注入器 |
| Layer 4 | `lib/core/ui/atomic/` | 7 个 `Base*` 组件 |

**漂移点**：同一类对象的层号标注不一致——通用 `ColorStrategy` 契约标「Layer 1」（`lib/core/theme/colors/strategy/color_strategy/color_strategy.dart`），chess/sudoku 的同名契约标「Layer 3」（`lib/core/theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart`），而各自的 Default 实现又标「Layer 2」。**层号目前不可作为导航依据**，需在 Ec 序列中固定为可校验的契约。

### 2.3 按钮存在三套写法

| 写法 | 位置 | 采用 |
|---|---|---|
| `FilledButton` / `FilledButton.tonal` | 裸用 | 26+ 处 |
| `OutlinedButton` + `EmphasisButton.borderEmphasis/dangerEmphasis/ghostEmphasis` | `lib/core/ui/shell/emphasis_button.dart:36,57,63` | 84 处调用 / 35 文件 |
| `BaseButton`（OutlinedButton 风格，色走 ColorStrategy） | `lib/core/ui/atomic/base_button.dart:13` | **0** |

`BaseButton` 与 `zen/zen_theme.dart:92-99 zenButtonTheme` 的 `OutlinedButton.styleFrom` **逐项相同**（`minimumSize Size(88,44)` / `padding EdgeInsets.symmetric(horizontal:14, vertical:10)` / `AppRadius.xs` / fg=text / border=outline）——这是真正的重复实现。
而 `EmphasisButton`（`shell/emphasis_button.dart:36`）语义**不同**：它是 `ButtonStyle` 工厂（调用方自己组装 `OutlinedButton`），走 `colorScheme.primary` + alpha 染色底，圆角取自 `cardTheme.shape`（`:24-31`，实际落到 `AppRadius.xl=16`），且不处理 label/icon。

> 三者并存 = 三套按钮写法（`FilledButton` 裸用 / `OutlinedButton + EmphasisButton` / `BaseButton`）。**裁决建议**（见 §9 待决问题）：删 `BaseButton`，`BaseEmptyState` 改用 `EmphasisButton.borderEmphasis`；`zenButtonTheme` 并入同一处。

### 2.3.1 全仓「带图标+文字的按钮」缺口

`OutlinedButton.icon(` 全仓 124 处，其中 78 处带 `style:`，仅 22 处用了 `EmphasisButton`。`BaseButton` 本来支持 `icon` 参数但从未被用到；`EmphasisButton` 是纯样式工厂，不含 icon 组合逻辑。
→ 建议新增 `EmphasisButton.icon(context, color:, icon:, label:)` 或 `BaseActionButton(label, icon, onPressed, variant)`。

### 2.4 已确认的实现缺陷（低风险、可直接修）

| 问题 | 位置 | 说明 |
|---|---|---|
| **自引用 import ×5** | `base_dialog.dart:10`、`base_dot.dart:15`、`base_empty_state.dart:12`、`base_icon_button.dart:13`、`base_swipe_action.dart:7` | 各自 `import '同名.dart'`；`flutter analyze lib/core/ui` 输出 **5 条 `unused_import` warning**——这是该目录下**唯一**的 warning 类型，零成本可清 |
| `_resolve(context)` 样板复制 7 份 | 7 个 atomic 组件各一份 | 「取 ThemeExtension → 回落 DefaultColorStrategy」逻辑逐份复制，应抽为扩展或 mixin |
| `BaseButton` 内含死代码 | `base_button.dart:87-114` `_LocalOverrideStrategy` | 其 `surface` / `surfaceOverride` 从未被读取（build 里直接用字段 `background`）；`icon`（`:26`）与 `fullWidth`（`:31`）在唯一调用点 `base_empty_state.dart:47-52` 也未使用 |
| `renderers/image_picker_widget.dart`（555 行） | `:413,477,483,491` `withOpacity`；`:321,334,355,375` `MaterialStatePropertyAll`；`:155,156` `use_build_context_synchronously` | `flutter analyze` 输出 10 条 info；全部为废弃 API / 异步 context 误用 |

### 2.5 组件层的其它结构性问题

| 问题 | 位置 | 说明 |
|---|---|---|
| `AppNotification` 主题豁免的根因 | `lib/core/ui/shell/app_notification.dart:244-299`（33 处 hex）、`lib/design_tokens/color/app_colors_extension.dart:13` | 项目已有 `AppColorsExtension`（13 个 success/warning/info 语义角色，按主题注入，`lib/core/theme/app_theme.dart:90-92`），但 `lib/core/theme/context/` 下**没有 `app_colors.dart`**——缺 `context.appColors` 访问器，才逼出硬编码 hex |
| 同模块内重复组件对 | `lib/core/timetable/service/config/advanced/shared/zen_controls.dart:11,160` vs `lib/core/timetable/service/config/timetable_settings_page.dart:391,431` | `ZenSegmentButton` / `ZenActionButton` 与 `_ZenSegmentButton` / `_ZenActionButton` 逐行等价（仅差 `const` 与 `danger` 参数）→ 下沉只做了一半 |
| ColorStrategy 解析路径不统一 | `lib/core/ui/zen/zen_theme.dart:78` vs atomic 6 个文件 | zen 直读 `DefaultColorStrategy.of(colorScheme)`（绕过 `ColorStrategyExtension`），atomic 走 extension 优先 + 兜底；同一 strategy 两条解析路径 |
| 注释指向已删除文件 | `lib/core/ui/global_ring/const_global_ring.dart:26,51` | 引用 `lib/core/ui/xiaodouzi_bottom_bar.dart`（已不存在）；且 `:51` 声称 `RingSnapCurve` 与 `_QQCurve` 同公式，实际 `const_global_ring.dart:58` 是 `1-exp(-4.5t)cos(9.425t)`、`quick_nav_bottom_bar.dart:21` 是 `1-exp(-5.2t)cos(7.5t)`——**公式不同** |
| 组件层测试覆盖为 0 | `test/` 下 0 命中 `Base*` / `EmphasisButton` / `QuickNavBottomBar` | `lib/core/ui` 仅 2 个测试文件（`test/widgets/app_notification_overflow_test.dart`、`test/widgets/nav_entry_icon_test.dart`）；组件重构无回归网 |
| 无 barrel 导出 | `lib/core/ui/` 下 28 个文件全走深路径 import | 如 `import '../../core/ui/shell/app_notification.dart';` |

### 2.6 边界清晰、无需整改的项（负向结论同样要记）

- `lib/core/ui/shell/quick_nav_bottom_bar.dart`（全局浮层钉选条）与各模块自带底栏**职责不同**：`clock_demo.dart:252` `NavigationBar`、`tetris_lua/widgets.dart:735` `ColoredBox`、`chess_skin_settings_page.dart:229` `SafeArea`、`block_editor_demo.dart:191` `toolbarFactory` 均为页面级功能栏；`lib/lab/demos/bottom_bar_demo.dart:38` `_LegacyBottomBar` 自述「demo 专用，不依赖共享组件」。**不需要合并。**

## 3. 业务模块层：已有组件的漏用

> 统计口径：`lib/core/` 下除棋类与联机外的业务模块（novel_reader / remotetype / line / gallerymanage / timetable / ai_chat / doubletime / body / note / share_receive / net_p2p 等）。
> `team_card` / `coup` / `cowrite` 仅含 `lobby/*_lobby_spec.dart`，无 UI；`storage` / `message_net` 零 Widget 类，均不在重复面内。

### 3.1 漏用清单（最高价值）

| 已有组件 | 位置 | 现状 | 应改用的位置（file:line） |
|---|---|---|---|
| `BaseConfirmDialog` | `lib/core/ui/atomic/base_dialog.dart:12` | 全仓 77 处 `AlertDialog(`（其中约 29 处是确认型），共享件业务侧仅 1 处调用 | `remotetype/settings/rt_layout_dialogs.dart:16,52`；`remotetype/ui/rt_shortcut_bar.dart:1173,1362`；`timetable/presentation/timetable_page.dart:635`；`ai_chat/pi/pi_chat_page.dart:229,257,365`；`ai_chat/pi/pi_session_list_page.dart:178`；`ai_chat/receipt_ocr/receipt_ocr_page.dart:98`；`ai_chat/system_messages/system_messages_page.dart:57`；`ai_chat/ai_chat_sports/agent_chat_page.dart:335`；`doubletime/doubletime_page.dart:638` |
| `BaseEmptyState` | `lib/core/ui/atomic/base_empty_state.dart:14` | **14 个**手写空态 widget 类 + 14 处 `Icon(size: 64)` | `gallerymanage/gallery_manage_page.dart:291,296`；`ai_chat/system_messages/system_messages_panel.dart:64,77`；`ai_chat/pi/pi_chat_page.dart:1125`；`share_receive/share_receive_page.dart:126,144`；`github/github_actions_page.dart:297`；`github/github_issues_page.dart:645`（与 `BaseEmptyState` 结构完全同构：Center + Column + Icon(size:64) + SizedBox(16) + Text）；`screens/profile/lab/game_center_page.dart:764,820`；`remotetype/ui/rt_pairing_view.dart:88,115` |
| `BaseSection` | `lib/core/ui/atomic/base_section.dart:14` | 分组标题全靠手写 `Text` | `doubletime/doubletime_page.dart:878` `_SectionLabel`（fontSize 13 / w700 / onSurfaceVariant，与 BaseSection 语义等价）；`ai_chat/ai_chat_settings_page.dart`；`remotetype/settings/rt_settings_page.dart` |
| `BaseIconButton` | `lib/core/ui/atomic/base_icon_button.dart:17` | 业务侧 0 处；目标模块裸写 `IconButton(` 52 处 / 29 文件 | `remotetype/rt_page.dart:475,488`（域内 `RtRoundIconButton`，`remotetype/ui/rt_layout_capsule.dart:128`）；`gallerymanage/`、`doubletime/`、`timetable/presentation/timetable_page.dart:692,755` |
| `BaseSwipeAction` | `lib/core/ui/atomic/base_swipe_action.dart:9` | 业务侧 0 处；`Dismissible` 手写删除背景 | `remotetype/ui/rt_shortcut_bar.dart:579,1227`；`ai_chat/pi/pi_session_list_page.dart:425`（形态不同，需先加 `iconOnly` 变体） |
| `BaseDot` | `lib/core/ui/atomic/base_dot.dart:18` | 业务侧 0 处；域内平行实现 | `lib/core/remotetype/canvas/rt_touch_surface.dart:506` `RtConnDot` |
| `BaseButton` | `lib/core/ui/atomic/base_button.dart:13` | 业务侧 0 处 | 目标模块 `TextButton(` 38 处 / `OutlinedButton(` 24 处 / `FilledButton` 26 处——**建议先裁决该组件去留，再谈改用**（见 §2.3） |
| `AppNotification` | `lib/core/ui/shell/app_notification.dart:25` | 全仓 **226 处** `showSnackBar(`（`lib/core` 内 141），`AppNotification` 仅 4 次实际调用（`remotetype/rt_page.dart:758,765,771`、`theme_page.dart:68`）；且 `rt_page.dart` **同时用两套** | `ai_chat/pi/pi_chat_page.dart:194,249,279,299,353`；`ai_chat/pi/pi_session_list_page.dart:211,237` 等 |
| `navCanPop` | `lib/core/nav/nav_route.dart:10` | 已有但多用手写 `Positioned` 返回键 | `line/presentation/pages/game_page.dart:251`；`line/settings/line_settings.dart:457`；`line/presentation/pages/game_result_page.dart:102`；`line/presentation/pages/song_select_page.dart:157` |

**落地前置**：`BaseConfirmDialog` 的默认标签是英文 `'Delete' / 'Cancel'`（`lib/core/ui/atomic/base_dialog.dart:20-21`）。直接推广会引入中英混排，**必须先把默认文案参数化并本地化**。

### 3.2 确实缺失的通用件（建议新建）

| 建议组件 | 建议参数 | 目标调用点 | 预计收益 |
|---|---|---|---:|
| `BaseSheetScaffold` | `title`、`subtitle`、`actions`、`child`、`maxHeightRatio`、`showDragHandle`、`radius`、`onClose` | `doubletime/doubletime_page.dart:87,348`（两段壳**逐字节相同**）、`:370`；`gallerymanage/gallery_manage_page.dart:931,949`；`timetable/presentation/timetable_page.dart:492,884`；`body/widgets/record_sheet.dart:124`；`remotetype/ui/rt_shortcut_bar.dart:295,371,441,852,1095,1391` | ≈250 行 |
| `BasePromptDialog` | `title`、`initialText`、`hint`、`maxLength`、`confirmLabel`、`cancelLabel` → `Future<String?>` | `timetable/presentation/timetable_page.dart:585,616`；`remotetype/settings/rt_layout_dialogs.dart:100`；`doubletime/doubletime_page.dart:144,405`；`ai_chat/pi/pi_chat_page.dart:369` | ≈90 行 |
| `BaseChatBubble` | `text`、`isMine`、`maxWidthRatio`、`onLongPressCopy`、`child`（富文本槽）、`showCopyButton` | `ai_chat/pi/pi_chat_page.dart:740` `_Bubble`；`ai_chat/ai_chat_sports/agent_chat_page.dart:367` `_MessageBubble`；`ai_chat/ai_chat_format/format_compatibility_page.dart:294` `_FormatMessageBubble` | ≈120 行 |
| `BaseListRow` | `title`、`subtitle`、`trailing`、`onTap`、`showDivider`、`leading` | `remotetype/settings/rt_settings_page.dart:199,210,216`；`line/settings/line_settings.dart:734,745,813`；`novel_reader/novel_reader_page.dart:690`；`ai_chat/ai_chat_settings_page.dart` | 样式统一 |
| `BaseTopBar` | `title`、`onBack`、`actions`、`centerTitle`、`style` | `remotetype/rt_page.dart:465` `_sharedHeader`；`novel_reader/novel_reader_page.dart:1347` `_ReaderTopBar`；`line/settings/line_settings.dart:449`；`line/presentation/pages/game_page.dart:244`；`game_result_page.dart:102`；`song_select_page.dart:157` | ≈100 行 |
| `BaseLoadingState` / `BaseErrorState` | `message`、`onRetry`、`icon` | 28 处 `CircularProgressIndicator`（19 文件）+ 6 处手写错误态 | loading / error / empty 三件套统一走 ColorStrategy |
| `BaseToast` | `message`、`type`(success/error/info)、`duration` | 77 处裸 SnackBar | 复用 `AppNotification` 能力，或作其薄封装 |
| `BaseLogPanel` | `lines`、`monospace`、`autoScroll` | 15 处 monospace 日志区（`auth_login/self_test_panel.dart:36-180`、`crash_log_demo.dart:137-151`、`network/network_http_tab.dart:239` 等） | ≈120 行 |

### 3.3 应从业务模块下沉的通用件

| 现位置 | 内容 | 建议去向 | 依据 |
|---|---|---|---|
| `lib/core/gallerymanage/ios_dialog.dart`（309 行） | `showIosDialog` / `IosDialogShell` / `IosDialogAction` / `showIosLoadingDialog` | `lib/core/ui/atomic/base_ios_dialog.dart` | 通用 iOS 风格弹窗套件，却寄居业务模块，全仓仅 `gallery_manage_page.dart:6` 一处引用 |
| `lib/core/remotetype/ui/rt_layout_capsule.dart:128` `RtRoundIconButton` | icon + tooltip + onTap，形状通用 | `lib/core/ui/atomic/base_icon_button.dart` | 域内自造，语义与 `BaseIconButton` 重叠 |
| `lib/core/remotetype/canvas/rt_touch_surface.dart:506` `RtConnDot` | 连接状态点 | `lib/core/ui/atomic/base_dot.dart` | 与 `BaseDot` 语义重叠 |
| `lib/core/ai_chat/pi/pi_chat_ui.dart` `PiChatColors:60` / `PiChatTokens:15` / `PiDayDivider:345` | 聊天配色 token 与日期分隔线 | `lib/core/ui/` | 通用件 |

## 4. 联机游戏层

### 4.1 已收敛的部分（先例，不必重做）

- 大厅入口已统一为 `GameLobbyPage` + `GameLobbySpec`（`lib/core/game_kit/lobby/`，Phase 1 已完成，见 `plan/game-kit-unification.md` Status 段）。13 个游戏全部 spec 化接入：chess / coup / cowrite / draughts / go / gomoku / jungle / reversi / sudoku / surround / team_card / tetris / xiangqi。
- 「就绪套件」已下沉到 `lib/core/game_kit/lobby/game_ready_style.dart`：`GameReadyFloatCard:12`、`GameReadyRoomCodeChip:58`、`GameReadyTitleRule:87`、`GameReadyAvatar:105`、`GameReadyStatusBadge:150`、`GameReadyCtaStyle:182`。

> **可行性证据**：本项目「样式下沉到共享层」的路已被验证过。缺的不是共享件，而是**采纳率**。

### 4.2 对局页骨架未收敛（7 个 lua 对局页，共 7422 行）

| 文件 | 行数 | `_buildLobby` | `_buildPlaying` | `_buildFinished` | `_ReadyAvatar` | 与 gomoku 相似度 |
|---|---:|---|---|---|---:|---:|
| `lib/lab/demos/gomoku_lua/widgets.dart` | 751 | 271–491 | 495–539 | 651–694 | 704–751 | 基准 |
| `lib/lab/demos/go_lua/widgets.dart` | 567 | 215–324 | 328–377 | 472–527 | 534–567 | **99.2%** |
| `lib/lab/demos/reversi_lua/widgets.dart` | 932 | 275–496 | 500–591 | 754–877 | 882–933 | **99.5%** |
| `lib/lab/demos/jungle_chess_lua/widgets.dart` | 937 | 275–497 | 600–651 | 799–871 | 878–935 | **99.1%** |
| `lib/lab/demos/surround_game_lua/widgets.dart` | 881 | 346–566 | 570–629 | 737–798 | 834–881 | **99.9%** |
| `lib/lab/demos/tetris_lua/widgets.dart` | 1655 | 477–699 | 703–746 | 1140–1211 | 1314–1371 | **97.1%** |
| `lib/lab/demos/coup_lua/widgets.dart` | 1703 | 113–282 | 342–462 | 1137–1210 | 用 `CircleAvatar` | **38.6%**（真差异） |

- `_buildLobby` / `_buildPlaying` / `_buildFinished` 三段骨架 **7/7 全部命中**；`_ReadyAvatar` **6/7** 存在。
- 语义 diff 后 gomoku ↔ surround 的 `_buildLobby` **唯一差异是 `GomokuRoom` → `SgRoom`**。
- 归一化去重后行级相同量：`reversi↔gomoku` **271 行**、`reversi↔go` **167 行**（独立统计，与上表相似度互为佐证）。
- `_ReadyAvatar` 三份实现**功能完全相同**，差异仅换行格式与 `Colors.transparent` vs `surface.withValues(alpha: 0.0)`（`reversi_lua/widgets.dart:882`、`gomoku_lua/widgets.dart:704`、`go_lua/widgets.dart:534`）。

`_buildLobby` 内部区块性质（以 gomoku 为例）：

| 区块 | 行号 | 性质 |
|---|---|---|
| 标题 + 分割线 | 299–308 | 壳层（= `GameReadyTitleRule`） |
| 房间号 chip | 311–332 | 壳层（= `GameReadyRoomCodeChip`） |
| 玩家行：头像 + 名字 + 准备徽章 | 336–384 | 壳层（= `GameReadyAvatar` + `GameReadyStatusBadge`） |
| CTA 三态（开始 / 已准备 / 准备好了） | 398–482 | 壳层（= `GameReadyCtaStyle`） |
| `players/readyMap/canDeal/iAmReady` 取数 | 272–281 | **策略侧**（各游戏 Room API 不同） |

**可下沉边界明确**：壳层（状态机 + 卡片 + CTA）与策略侧（棋盘、规则、取数）已可清晰切分。

### 4.3 `GameReady*` 五件套在 demo 侧分叉（P0，视觉不一致）

4 个 core 房间页全部采用共享件（`chess_room_page.dart:1680-1778`、`draughts_room_page.dart:892-985`、`sudoku_room_page.dart:368-395`、`xiangqi_room_page.dart`）；7 个 lua demo **只用了 `GameReadyFloatCard.decoration()` 一个静态方法**（`gomoku_lua/widgets.dart:292`、`go_lua/widgets.dart:235`、`reversi_lua/widgets.dart:297`、`jungle_chess_lua/widgets.dart:296`、`surround_game_lua/widgets.dart:367`、`tetris_lua/widgets.dart:501`、`coup_lua/widgets.dart:144`），其余五件全部手写等价物。

**房间号胶囊实测对比**（同一功能，两种实现）：

| | core `GameReadyRoomCodeChip`（`game_ready_style.dart:58`） | demo 手写版（`gomoku_lua/widgets.dart:311-331`） |
|---|---|---|
| 前景色 | `scheme.onPrimaryContainer` | `theme.btnText`（BoardTheme 皮肤色） |
| 背景 | `scheme.primaryContainer` | `theme.btnText.withValues(alpha: 0.05)` |
| 边框 | 无 | `border` + `alpha 0.2` |
| 字号 / 字距 | 22 / 6 | 24 / 8 |

→ **同一房间号在应用内呈现两种视觉**；demo 版取皮肤色而非 `colorScheme`，不随全局主题切换。`_ReadyAvatar`（6 份）、状态徽章（6 份）、CTA（7 份）同理。

另有一处**行为差异**：`RelayConnectionBar`（`lib/core/net_engine/relay_v3/relay_connection_bar.dart`）被 6 个 demo 使用，唯独 `tetris_lua` 自建 disconnect 处理（`tetris_lua/widgets.dart:150` 自行订阅 `closeEvents`、`:244` 自行 `rejoin()`、`:439` 自绘重连 SnackBar）。

### 4.4 core p2p 页面同构

`lib/core/chess/p2p/chess_room_page.dart`（2262）、`lib/core/xiangqi/p2p/xiangqi_room_page.dart`（1578）、`lib/core/draughts/p2p/draughts_room_page.dart`（1473）、`lib/core/sudoku/p2p/sudoku_room_page.dart`（588）为同一形态的 4 份实现。

draughts ↔ xiangqi 有 **21 个方法逐字符 100% 相同**：`_onSnapshot`（draughts:201-220 / xiangqi:210-229）、`_ensureEmojiBundle`、`_ack`、`_deal`、`_reset`、`_confirmResign`、`_handleSendText`、`_handleSendEmoji`、`_fetchSnapshotWithFeedback`、`_leaveAndPop`、`_buildWsOfflineOverlay`、`_buildMeOfflineBanner`、`_seekReplay`/`_stepReplay`/`_replayTick`/`_clearReplay`、`_undoEntryButton`、`_endedOverlay`、`_actionButtons`（99.6%）、`_buildLobbyReady`（98.8%）、`build`（97.9%）。

chess 缺 `_sendGuardedAction` 抽象（`xiangqi_room_page.dart:675-710`、`draughts_room_page.dart:628-663` 有），把同样的 try/catch 复制在 `_drawOffer` / `_undoRequest` 等 6 处 → **chess 应向 xq/dra 对齐**。

### 4.5 脚本层：共享段存在，但 9 个 demo 一个都没接

现有共享设施：

- `lib/core/game_kit/emoji/lua_script_assembler.dart:31-70` —— `assembleLuaScript(lifecycle, actions, extraSegments)`，负责拼段 + 生成 export 表。
- `lib/core/game_kit/chat/chat_script.dart:18-56` —— 共享 `on_action_CHAT`（限流 1.5s / ring 16 / seq）。
- `lib/core/game_kit/emoji/emoji_script.dart:29-72` —— 共享 `on_action_EMOJI`（限流 / ring 16 / 同 id 合并计数）。

接入现状（实测 grep `CHAT|EMOJI`）：

| 脚本 | 用 assembler | 带 EMOJI | 带 CHAT |
|---|---|---|---|
| `lib/core/chess/p2p/script/chess_script.dart:65` | ✅ | ✅ | ✅ |
| `lib/core/xiangqi/p2p/script/xiangqi_script.dart:50` | ✅ | ✅ | ✅ |
| `lib/core/draughts/p2p/script/draughts_script.dart:49` | ✅ | ✅ | ✅ |
| `lib/core/sudoku/p2p/script/sudoku_script.dart:14` | ✅ | ✅ | ❌ |
| 9 个 lua demo 脚本 | ❌ | ❌ | ❌ |

9 个未接入者：`coup_lua/coup_script.dart`、`cowrite_lua/cowrite_lua_script.dart`、`go_lua/go_script.dart`、`gomoku_lua/gomoku_script.dart`、`jungle_chess_lua/jungle_lua_script.dart`、`reversi_lua/reversi_script.dart`、`surround_game_lua/quoridor_script.dart`、`team_card/team_card_script.dart`、`tetris_lua/tetris_script.dart`。

→ **能力缺口**：这 9 个 demo 的 UI 侧也没有聊天入口（`grep chat` 在其 `widgets.dart` / `*_demo.dart` 中 0 命中），即聊天/表情功能对它们**完全不可用**，而非「接了但失效」。这是「共享能力已建成、采纳率 4/13」的又一处证据。

跨脚本逐字相同的 handler（可抽公共 Lua 段）：

| handler | 相同簇 | 位置 | 行数 |
|---|---|---|---|
| `on_action_ACK` | chess / draughts / xiangqi 三份相同 | `chess_script_actions.dart:35`、`draughts_script_actions.dart:28`、`xiangqi_script_actions.dart:28` | ~15 |
| `on_action_ACK` | go / gomoku / jungle / reversi / quoridor / tetris **六份相同** | `gomoku_script.dart:125`、`go_script.dart:198`、`jungle_lua_script.dart:158`、`reversi_script.dart:110`、`quoridor_script.dart:152`、`tetris_script.dart:115` | ~15 |
| `on_action_DEAL` | chess/draughts/xiangqi 三份 + go/gomoku/jungle/quoridor 四份 | `gomoku_script.dart:140`、`go_script.dart:213` 等 | ~12 |
| `on_action_START` | chess/draughts/xiangqi 三份相同 | `chess_script_actions.dart:66` 等 | ~3 |
| `on_action_DRAW_ACCEPT` / `DRAW_DECLINE` / `UNDO_DECLINE` | draughts/xiangqi 相同 | `draughts_script_actions.dart:224,244,342` | ~34 |

**游戏特有、不可抽取**：`on_action_MOVE`（8 份 8 簇）、`on_action_SET_RULES`（45.3%）、`on_action_CLAIM_END`（57–71.6%）、`on_action_UNDO_ACCEPT`（78.5%）、`on_action_RESET`（88.1%）、`on_init`（79.2%）。

### 4.6 计划-代码漂移：`BoardThemeData`

- 定义在**游戏模块内**：`lib/core/surround_game/board_theme.dart:43`，却被 **21 个文件**跨游戏消费（reversi / xiangqi / draughts / 7 个 lua demo）。
- `lib/core/reversi/board_theme.dart`（154 行）又平行实现了一套「同设计语言」的令牌（其头注释自述「与 surround_game 的 BoardThemeData 共用同一设计语言」）。
- `BoardThemeData` 作为参数在对局页中传递 **52 处**。
- `plan/game-kit-unification.md` 的 Conventions 段明写「入口页统一走 `Theme.of(context).colorScheme` + `context.colors`，**不再每游戏各挂 BoardTheme/chessColors**（顺手消灭主题不一致）」——**计划已写、代码未收敛**。

### 4.7 建议

- 新增 `lib/core/game_kit/room/`：`OnlineRoomScaffold`（承接 ready 卡 / 玩家列表 / 回合条 / 确认槽 / 底部操作栏 / 终局 overlay 骨架）+ `RoomBottomActionBar` + `RoomTurnStatusBar` + `GameResultOverlay`；各游戏以 spec 提供棋盘与规则段。
- 复用既有 `GameLobbySpec` / `GameLobbySlots` 插槽模式作为模板（先例：`lib/core/game_kit/lobby/game_lobby_slots.dart`）。
- core p2p 侧新增 `P2pRoomSpec` + `P2pRoomPageBase`，吸收 21 个 100% 相同的方法。
- 脚本侧新增 `kBoardGameCommonActionsSegment`（ACK / DEAL / START / RESIGN / DRAW_* / UNDO_DECLINE），让 12+ 脚本共享约 90 行 Lua。
- 现状约束：`plan/game-kit-unification.md` Phase 4 写明「存量 9 个对局页不强迁；新游戏强制用壳」。**建议改为「新代码强制 + 存量按收益分批」**，因为现存重复量已达 7422 行量级。

## 5. lab demos 层

> 范围：`lib/lab/demos/` 206 个 `.dart`，共 57114 行，其中 44 个文件 >400 行。

### 5.1 违反「>400 行拆目录」约定的文件

**A. 本应拆分但仍是顶层单文件（16 个）**

| 行数 | 文件 | 建议 |
|---|---|---|
| 2584 | `storage_analyze_demo.dart` | 拆 `storage_analyze/`（含 15 个私有 widget） |
| 1594 | `web_bookmark_demo.dart` | 主体下沉 `web_bookmark/`，入口只留 `DemoPage` |
| 1549 | `notion_image_host_demo.dart` | 拆 `notion_image_host/` |
| 1341 | `torch_demo.dart` | 拆 `torch/` |
| 1152 | `kvcli_todo_demo.dart` | 半拆分：页面 state 占 714 行，移入已有 `kvcli_todo/` |
| 722 | `pigment_palette_demo.dart` | 拆 `pigment_palette/` |
| 675 | `api_test_demo.dart` | 半拆分，入口瘦身 |
| 653 | `sensor_demo.dart` | 拆 `sensor/` |
| 577 | `metronome_demo.dart` | 半拆分：`metronome/metronome_widgets.dart` 已 505 行 |
| 474 / 465 / 449 / 446 / 439 / 406 / 404 | `game_2048_demo.dart` / `snake_game_demo.dart` / `schema_demo.dart` / `chess_online_demo.dart` / `cowrite_lua_demo.dart` / `overlay_demo.dart` / `reaction_test_demo.dart` | 各自拆目录（`cowrite_lua_demo.dart` 为半拆分，`cowrite_lua/` 已存在） |

**B. 已拆目录但文件仍超大（28 个，列前 10）**

| 行数 | 文件 | 建议 |
|---|---|---|
| 1974 | `team_card/widgets.dart` | 19 个 widget 类 → 拆 `team_card/widgets/`（lobby/host/spectator/playing） |
| 1703 | `coup_lua/widgets.dart` | 拆 ready / play / result |
| 1655 | `tetris_lua/widgets.dart` | 拆 ready / play / result |
| 1303 | `api_test/api_speech_tab.dart` | 拆 speech / tts / asr / file |
| 937 / 933 / 881 / 751 / 567 | `jungle_chess_lua/`、`reversi_lua/`、`surround_game_lua/`、`gomoku_lua/`、`go_lua/` 的 `widgets.dart` | 拆 ready / play / result |
| 834 | `block_editor_demo/card.dart` | 拆 card 变体 |
| 795 | `api_test/api_download_manager.dart` | 拆 manager / updater / bg-mode |
| 753 | `coup_lua/coup_script.dart` | Lua 脚本可下沉 `lib/core/` |

### 5.2 跨 demo 重复样板

| 样板 | 次数 | 典型位置 | 下沉判断 |
|---|---:|---|---|
| 准备阶段整卡（标题 + 分割条 + 房间号 + 玩家列表 + 徽章 + CTA） | **7** | `gomoku_lua/widgets.dart:281`、`go_lua/widgets.dart:224`、`jungle_chess_lua/widgets.dart:285`、`reversi_lua/widgets.dart:285`、`surround_game_lua/widgets.dart:356`、`tetris_lua/widgets.dart:490`、`coup_lua/widgets.dart:144` | **是**——core 已有全套（见 §4.3） |
| 房间号 chip | **7** | `gomoku_lua/widgets.dart:310` … `cowrite_lua/cowrite_widgets.dart:330` | **是**——`GameReadyRoomCodeChip` |
| 「已准备 ✓ / 未准备」徽章 | **6** | `gomoku_lua/widgets.dart:371` … `tetris_lua/widgets.dart:580` | **是**——`GameReadyStatusBadge` |
| `_ReadyAvatar` 私有实现 | **6** | `gomoku_lua/widgets.dart:704`、`go_lua/widgets.dart:534`、`jungle_chess_lua/widgets.dart:878`、`reversi_lua/widgets.dart:882`、`surround_game_lua/widgets.dart:834`、`tetris_lua/widgets.dart:1314` | **是**——`GameReadyAvatar`（gomoku 与 surround 版本字节级相同） |
| 「准备好了」CTA 按钮 | **7** | `gomoku_lua/widgets.dart:473` … `coup_lua/widgets.dart:261` | **是**——`GameReadyCtaStyle` |
| `_bottomAction` 底部动作按钮 | **4**（字节级相同） | `gomoku_lua/widgets.dart:637`、`go_lua/widgets.dart:458`、`jungle_chess_lua/widgets.dart:783`、`surround_game_lua/widgets.dart:725` | **是**——`RoomBottomActionBar` |
| 底部操作栏（认输 / 重新开始 / 退出） | **4** | `gomoku_lua/widgets.dart:524-537`、`go_lua/widgets.dart:357-375`、`jungle_chess_lua/widgets.dart:635-645`、`surround_game_lua/widgets.dart:613-625` | **是**——权限位不同，应参数化 |
| 回合状态条 | **4+** | `gomoku_lua/widgets.dart:568-578`、`go_lua/widgets.dart:403-411`、`jungle_chess_lua/widgets.dart:653`、`reversi_lua/widgets.dart:593` | **是** |
| 终局结果面板 | **7** | `gomoku_lua/widgets.dart:651-696` … `coup_lua/widgets.dart:1171` | **是**——胜负文案与按钮同构 |
| Snapshot 访问器（`players`/`readyMap`/`hostId`/`winner`/`actionPermissions`） | **6 × 5 方法** | `gomoku_lua/engine.dart:78-96`、`go_lua/go_engine.dart:69`、`reversi_lua/engine.dart:80-100`、`jungle_chess_lua/jungle_engine.dart:129`、`surround_game_lua/engine.dart`、`tetris_lua/engine.dart:342` | **是**——纯 context 读取，应为 `lib/core/net_engine/relay_v3/` 静态工具类 |
| Lua 房间状态机（`on_leave`/`ACK`/`DEAL`/`RESIGN`/`WIN`） | **6** | `gomoku_lua/gomoku_script.dart:121-170`、`go_lua/go_script.dart:195`、`reversi_lua/reversi_script.dart:107`、`jungle_chess_lua/jungle_lua_script.dart:155`、`surround_game_lua/quoridor_script.dart:149`、`tetris_lua/tetris_script.dart:112` | **是**——`role_check` + `state` 守卫模板与游戏无关 |
| 日志/输出文本区（monospace + ListView） | **15** | `auth_login/self_test_panel.dart:36-180`、`crash_log_demo.dart:137-151`、`network/network_http_tab.dart:239`、`network/network_ws_tab.dart:222` | **是**——无任何公共实现 |
| 棋盘容器（正方形 SizedBox + Stack + radius 8 + CustomPaint 网格） | **2** | `gomoku_lua/board.dart:71-100`、`go_lua/go_board.dart:66-95` | **部分**——只抽 `LayoutBuilder`/`step`/正方形 Stack 外壳，绘制留 demo |
| 连接状态条 | 6 已下沉 / 1 缺失 | 已用 `RelayConnectionBar`：gomoku / go / jungle_chess / reversi / surround / cowrite；**tetris 缺失** | 补齐 tetris |

去重工具交叉验证：`go_lua/widgets.dart` ↔ `gomoku_lua/widgets.dart` 有 **16 段** 8 行级重复块；`gomoku_lua/widgets.dart` ↔ `surround_game_lua/widgets.dart` **12 段**；`gomoku_lua/gomoku_script.dart` ↔ 另 5 个 `*_script.dart` 各 **3–4 段**。

### 5.3 demo 内部重复 widget

| # | file:line | 说明 |
|---|---|---|
| 1 | `team_card/widgets.dart:600-621` **vs** `:1740-1766` | 房间号胶囊**内联一份 + 又定义 `_RoomCodeBadge` 一份**，同文件写两遍 |
| 2 | `storage_analyze_demo.dart:1141-1170` **vs** `:1630-1658` | `_KeyDetailSheet` 与 `_NotePreviewSheet` 各自复制 `DraggableScrollableSheet` + 拖拽条 + 圆角 shell |
| 3 | `pigment_palette_demo.dart:459` **vs** `:502` | `_SectionCard` 与 `_GroupedListCard` 复制同一 header |
| 4 | `relation_calc/manage_view.dart:75-95` / `:136-150` / `:247-249` | 同一「实体编辑 AlertDialog」**三份** |
| 5 | `web_bookmark_demo.dart:373-392` **vs** `:1152-1170` | favicon 提取 RegExp 列表写两遍 |
| 6 | `storage_analyze_demo.dart:509` / `:760` / `:793` | 同一「确认删除」AlertDialog **三份** |
| 7 | `network/network_env_cards.dart:120-140` **vs** `:199-220` | 同一结果行两份 |
| 8 | `storage_analyze_demo.dart:1252-1266` **vs** `:1717-1731` | 同一「卡片内 padding 16 + surface 底」区块 |

### 5.4 应保留的教学性重复（不要下沉）

| 重复 | 理由 | 证据 |
|---|---|---|
| 各 demo 各自的规则/引擎代码（胜负判定、走法生成） | 正是 demo 的教学主体，抽走就没有 demo 价值 | `gomoku_lua/gomoku_script.dart:171-215`、`go_lua/go_script.dart:264-290`、`reversi_lua/reversi_script.dart:236-243` |
| 棋盘绘制细节（星位、落子高亮、提子红框、镜像） | 各游戏规则差异正是教学点 | `go_lua/go_board.dart:149-150`、`gomoku_lua/board.dart:262`、`reversi_lua/board.dart:72` |
| 一次性结果文案（"黑方连五" / "数子终局"） | 每个游戏终局语义不同 | `gomoku_lua/widgets.dart:680`、`go_lua/widgets.dart:482`、`surround_game_lua/widgets.dart:745-749` |
| 参数输入行 | 几乎无成规模重复，各 demo 字段语义不同 | `storage_analyze_demo.dart:2379`、`auth_login/unified_login_panel.dart:501` |
| 保存/应用/重置按钮组 | 语义各异 | `clock/widgets/clocks_tab.dart:639`、`block_editor_demo/block_editor_demo.dart:315` |

### 5.5 lua demo 是否应迁到 `lib/core/`

**结论：只迁「壳层骨架 + 房间状态机」，游戏规则留在 demo。**

理由：

1. **入口层已下沉完毕**（`go_lua/widgets.dart:4-6` 明写「入口已迁移到 GameLobbyPage + kGoLobbySpec」），in-game 层是唯一缺口。
2. core 已有 4 个同型房间页做参考实现，彼此也互为复制——再加 7 份 demo 版即 **10 份同型房间页**。
3. `GameReady*` 五件套完备但 demo 不用，是「重复 + 主题不一致」双重问题（§4.3）。
4. tetris 缺 `RelayConnectionBar` 导致**实际行为差异**（自建 disconnect 处理）。

预期收益：7 个 demo 的 `widgets.dart` 合计约 6846 行，其中准备阶段 + 回合条 + 底部栏 + 终局 overlay 四段重复约 1900 行 → 抽 core 后可减约 **27%**；并消除 `GameReady*` 的 6–7 份手写分叉与 `engine.dart` 的 6 份 × 5 方法静态读取复制。

## 6. 主题通道断层

### 6.1 `context.colors`（ColorStrategy 角色层）被 8 个模块整体绕过

| 模块 | `context.colors` | `Theme.of(context).colorScheme` |
|---|---:|---:|
| timetable | 102 | 44 |
| remotetype | 70 | 3 |
| novel_reader | **0** | 85 |
| doubletime | **0** | 32 |
| line | **0** | 20 |
| ai_chat | **0** | 17 |
| net_p2p | **0** | 16 |
| gallerymanage | **0** | 9 |
| note | **0** | 6 |
| body | **0** | 3 |
| share_receive | **0** | 0 |

后果：这 8 个模块拿不到 `accent` / `textMuted` / `outline` / `danger` 语义角色，换主题时只有 Material primary/secondary 在变，危险色与弱文本色各模块自定。

### 6.2 硬编码色板（非豁免）

- `lib/core/timetable/presentation/timetable_colors.dart:17-24`（8 色灰蓝系）+ `:43`（sage）——模块本地调色板，未进 ColorStrategy。
- `lib/core/body/models/body_region.dart:10-13`（浅色 tissue 4 色）+ `:17-20`（深色 4 色）——手写明暗两套，未走 `ThemeExtension`（`lib/core/theme/extensions/` 已有 7 个 strategy extension 可承载）。

### 6.3 有豁免注释但缺 ThemeExtension 承载

`lib/core/novel_reader/canvas_reader_engine.dart:722-724` 与 `lib/core/novel_reader/novel_reader_page.dart:18` 声明「主题豁免：纸质书视觉风格」。豁免本身合理，但 23 个 `Color(0x…)` 以枚举常量内嵌在绘制引擎/页面里，缺 ThemeExtension 承载位 → 无法被主题切换页预览，也无法被其他模块复用。

### 6.4 深色模式硬编码底色

- `lib/core/novel_reader/novel_reader_page.dart:765,807,825` 与 `:228`：浅色常量（`0xFFEEE6D8` / `0xFFF8F1E6` / `0xFFE4D5C0` / `0xFFF4EDE3`）直接作页面底，dark theme 下会出现亮色块。
- `lib/core/ai_chat/ai_chat_sports/agent_chat_page.dart:404` `color: Colors.white`，与 `lib/core/ai_chat/pi/pi_chat_page.dart:773-780` 的 `PiChatColors` 双端配对方案不一致。

### 6.5 弹窗按钮样式分裂

同一动作在四种按钮间摇摆：`TextButton`（`timetable_page.dart:648`）、`FilledButton.tonal`（`rt_layout_dialogs.dart:29,65`）、`OutlinedButton`（`doubletime_page.dart:653`）、`IosDialogAction`（`gallery_manage_page.dart:151`）。`EmphasisButton` 已有三档语义（`lib/core/ui/shell/emphasis_button.dart:36,57,63`），但仅 doubletime / gallerymanage / novel_reader / timetable 部分使用，ai_chat / remotetype / line 未用。

### 6.6 其他基线数字

- 全仓 `Color(0x…)` 719 处，其中 332 处在 `lib/design_tokens/color`（token 定义，属正常）、34 处在 `lib/core/ui`（组件层，应走 strategy）。
- `withOpacity` 残留 21 处（项目约定优先 `withValues(alpha:)`）。

## 7. 超大文件拆分（超出项目 400 行分文件约定）

> 约定来源：`lib/core/ui/zen/zen_theme.dart:5-9` 注释 + `SKILL.md` FR 开发约束速记第 2 条。

| 文件（现行行数） | 拆分建议 |
|---|---|
| `lib/core/novel_reader/novel_reader_page.dart`（1636） | 书架页 `22-403`；`_BookshelfSwipeDeck` `907-1102` + 卡片 `1103-1325` → `widgets/bookshelf_cards.dart`；`_ReaderTopBar 1347` / `_ReaderBottomBar 1410` / `_ProgressSeekSlider 1533` / `_ReaderSettingSlider 1566` → `widgets/reader_chrome.dart` |
| `lib/core/novel_reader/canvas_reader_engine.dart`（1620） | 3 套纸张主题枚举 `724-760` → `novel_reader_paper_theme.dart`（引擎只留绘制逻辑） |
| `lib/core/remotetype/ui/rt_shortcut_bar.dart`（1478） | 托盘 `23-279` → `ui/rt_shortcut_tray.dart`；编辑 sheet `381-859` → `ui/rt_shortcut_item_editor.dart`；`RtKeyDisplay 1010-1102` 属 label 映射，应归 data 层；`RtShortcutItem` / `RtBarDisplay` 现定义于 `remotetype/data/rt_prefs.dart:145`，托盘若下沉须先提类型 |
| `lib/core/remotetype/canvas/rt_canvas_view.dart`（1467） | 编辑侧栏 `675-923` → `rt_canvas_edit_panel.dart`；模块渲染 `1102-1369` → `rt_canvas_modules.dart`；编辑框 `923-1178` → `rt_canvas_edit_frame.dart` |
| `lib/core/remotetype/rt_page.dart`（1216） | 输入桥接 `933-1020` → `canvas/rt_canvas_input_bridge.dart`；`_sharedHeader 465-497` 随 header 下沉 |
| `lib/core/ai_chat/pi/pi_chat_page.dart`（1413） | `_Bubble 740-1042` → `widgets/pi_bubble.dart`；`_TypingCursor 1043` / `_ThinkingDots 1192` → `widgets/`；`_NotConfiguredView 1094` / `_EmptyChatView 1125` → `widgets/`；`_ContextBar 1288` → `widgets/`；`_CodeBlockBuilder 1332` 与 `lib/core/ui/renderers/markdown_renderer_widget.dart` 合并 |
| `lib/core/line/settings/line_settings.dart`（1100） | `_DemoPainter 15-215` → `painters/line_demo_painter.dart`；背景图标 painter `999-1099` → `painters/`；`_buildTimingControls 602` + `_buildScrollSpeedControls 829` → `widgets/line_timing_controls.dart` |
| `lib/core/game_kit/chat/board_chat_overlay.dart`（1030） | `_ChatPill 379-516` → `chat/chat_pill.dart`；`_Composer 517-935` → `chat/chat_composer.dart`；`_EmojiImage 936` + painter `981` → `chat/chat_bubble_art.dart` |
| `lib/core/gallerymanage/gallery_manage_page.dart`（1071） | `_buildAlbumSelector 238` / `_buildImageGrid 304` / `_buildSelectBar 380` → `widgets/`；`_MoveImageDialog 710-816`；`_ImagePreviewPage 817-1070` → `pages/gallery_preview_page.dart` |
| `lib/core/timetable/presentation/timetable_page.dart`（985） | `_SpaceSheet 552-772`；`_SlotLabel 773` + `_CycleChips 814`；`_CoursePreviewSheet 850-985` |
| `lib/core/doubletime/doubletime_page.dart`（979） | `_showAddEventSheet 78-340` 与 `_showEventDetailSheet 341-636` 表单壳逐字节重复 → 抽 `widgets/doubletime_event_sheet.dart`（≈230 共用），页面降至 ≈500 |
| `lib/core/chess/p2p/chess_room_page.dart`（2262） | 见 §4.4；属 Phase 4 专项 |

## 8. 组件化收敛清单（按投入产出排序）

> 均为**建议**，未修改应用代码。每条给出可验证的完成判据。

| # | 动作 | 范围 | 预计净减行数 | 完成判据 |
|---|---|---|---:|---|
| 1 | **7 个 lua demo 换成 core 现成 `GameReady*` 五件套** | 7 文件 | ≈900 | demo 中 `_ReadyAvatar` 等私有实现归零；房间号胶囊全应用一致 |
| 2 | `BaseConfirmDialog` 文案参数化 + 本地化，收编约 29 处确认型弹窗 | `base_dialog.dart` + 10 文件 | ≈120 | 业务代码中确认型 `AlertDialog(` 归零（文本输入型走 #5 的 `BasePromptDialog`） |
| 3 | `AppNotification` 收编裸 SnackBar（全仓 226 处，先覆盖 `lib/core` 内 141 处） | `app_notification.dart` | ≈60 | `ScaffoldMessenger.of(context).showSnackBar` 在业务页归零 |
| 4 | `BaseEmptyState` 收编 14 个手写空态类 | 9 文件 | ≈40 | 手写空态图标块（`Icon(size: 64)`）归零 |
| 5 | 新建 `BaseSheetScaffold`，替换 5 处底部弹层壳 | `lib/core/ui/atomic/` | ≈250 | `doubletime_page.dart` 979 → ≈500 |
| 6 | 新建 `BasePromptDialog`，收编 5 处文本输入弹窗 | `lib/core/ui/atomic/` | ≈90 | `AlertDialog(content: TextField` 归零 |
| 7 | 新建 `BaseChatBubble`，收编 3 套气泡 | `lib/core/ui/atomic/` | ≈120 | 3 套 `_Bubble` 合并为 1 |
| 8 | 新建 `GameResultOverlay` / `RoomTurnStatusBar` / `RoomBottomActionBar`，收编 7+4+4 处 | `lib/core/game_kit/room/` | ≈400 | demo 与 core 房间页统一 |
| 9 | 新建 `room_snapshot_accessors.dart`，收编 6 份 × 5 方法 | `lib/core/net_engine/relay_v3/` | ≈150 | 6 个 `engine.dart` 不再各自实现 |
| 10 | `ios_dialog.dart` 迁至 `lib/core/ui/atomic/base_ios_dialog.dart` | 2 文件 | 0（纯搬移） | `lib/core/gallerymanage/` 不再持有通用弹窗套件 |
| 11 | 裁决 `BaseButton` 去留（并入 `EmphasisButton` 或补齐采用） | `lib/core/ui/atomic/` | 0 / −113 | 零引用组件归零 |
| 12 | `BaseIconButton` 收编 174 处裸 `IconButton`（含补 `tooltip`）；`RtRoundIconButton` 下沉 | `lib/core/ui/atomic/` | ≈80 | 裸 `IconButton(` 显著下降；可访问性 tooltip 覆盖 |
| 13 | 新建 `BaseTopBar`，收编 6 处手写顶部栏 | `lib/core/ui/atomic/` | ≈100 | 6 处 `Positioned` 返回键实现归一 |
| 14 | 新建 `BaseListRow`，收编设置项行 | `lib/core/ui/atomic/` | ≈60 | 「标题+副标题+右侧开关」统一 |
| 15 | 新建 `BaseLoadingState` / `BaseErrorState` / `BaseLogPanel` | `lib/core/ui/atomic/` | ≈190 | 28 处 `CircularProgressIndicator`、15 处日志区有统一容器 |
| 16 | 新建 `OnlineRoomScaffold`，迁移 7 个 lua 对局页 | `lib/core/game_kit/room/` | ≈1500–2000 | `_buildLobby/_buildPlaying/_buildFinished` 骨架归一 |
| 17 | `P2pRoomPageBase` + `P2pRoomSpec`，收敛 4 个 core p2p 页 | `lib/core/game_kit/room/` | ≈600 | draughts↔xiangqi 的 21 个同构方法归一 |
| 18 | `kBoardGameCommonActionsSegment` Lua 共享段，12+ 脚本接入 | `lib/core/game_kit/room/` | ≈250（Lua） | ACK/DEAL/START/RESIGN 不再逐字复制 |
| 19 | 9 个 lua demo 脚本接入 `assembleLuaScript` + 聊天/表情段 | 9 文件 | 行数不减，**补齐聊天/表情能力** | demo 房间可发聊天与表情 |
| 20 | `BoardThemeData` 上收到共享层，reversi 平行令牌并轨 | `lib/core/game_kit/` 或 `lib/core/ui/` | 0（结构收敛） | 跨游戏消费不再依赖游戏模块内部路径 |
| 21 | 8 个模块接入 `context.colors` | 8 模块 | 0 | `context.colors` 计数 0 → >0，语义色统一 |
| 22 | 拆 16 个顶层单文件 demo + 28 个超大已拆文件 | `lib/lab/demos/` | 0（结构） | 全部 ≤400 行或按约定分目录 |
| 23 | **清 5 个 atomic 自引用 import**（`flutter analyze lib/core/ui` 的全部 warning） | `lib/core/ui/atomic/` | 0 | `flutter analyze lib/core/ui` 0 warning |
| 24 | 新建 `BaseChip` / `BaseBadge`，收编 24 个私有 chip/badge 类 | `lib/core/ui/atomic/` | ≈200 | 私有 chip/badge 类归零；选中态与徽标圆角统一 |
| 25 | 新建 `context.appColors` 访问器（约 20 行，照 `team_avatar_colors.dart`），解 `AppNotification` 的 33 处 hex | `lib/core/theme/context/` | 0 | `app_notification.dart` 裸 hex 归零 |
| 26 | 清 `image_picker_widget.dart` 的 10 条 analyze info（4 `withOpacity` + 4 `MaterialStatePropertyAll` + 2 async-context） | `lib/core/ui/renderers/` | 0 | `flutter analyze lib/core/ui` 0 issue |
| 27 | `timetable` 内部重复对归一（`zen_controls.dart` 的 `ZenSegmentButton`/`ZenActionButton` vs 同目录私有 `_Zen*`） | 2 文件 | ≈60 | 同一控件只留一份实现 |
| 28 | `const_global_ring.dart:26,51` 注释修正（指向已删文件 + 曲线公式不符） | 1 文件 | 0 | 注释与代码一致 |

**执行顺序建议**：#1 → #2 → #3 → #4（低风险、纯收益，先把组件层引用率拉起来）→ #5–#9（新建缺失件）→ #16–#19（联机层收敛，工作量最大）→ #20–#22（结构与主题）。

## 9. 需要人工裁决的问题（改动前必须先定）

> 下列每条都会改变落地范围或改法，**先定再动手**。

| # | 问题 | 选项 | 影响 |
|---|---|---|---|
| 1 | `BaseButton` 去留 | (a) 删除，`BaseEmptyState` 改用 `EmphasisButton.borderEmphasis`；(b) 保留并补齐采用 | (a) 少一个零引用组件，但 `BaseEmptyState` 行动按钮视觉从「中性描边」变「描边强调」；需产品确认 |
| 2 | `shell/` 与 `zen/` 的边界 | (a) atomic 提为唯一实现，zen 只留 `ZenText` / `zenPageScaffold` / 日期选择器；(b) 保持 zen 域专属 | (a) 影响 26 个引用方，改动面大；(b) 允许 `zenButtonTheme` 与 `BaseButton` 继续并存 |
| 3 | `AppNotification` 是否收编 SnackBar | (a) 全量迁移 226 处；(b) 承认双轨并写明分工（顶栏通知 vs 底部 snackbar） | (a) 工作量大且会改变部分交互观感；(b) 需在 Ec01/Ec02 写清边界 |
| 4 | `AppNotification` 的 33 处 hex 主题豁免 | (a) 坚持「通知永远同色」；(b) 改吃 `AppColorsExtension`（需先补 `context.appColors` 访问器，约 20 行） | 影响暗黑/茶禅主题下通知辨识度 |
| 5 | 房内就绪 CTA 形状 | (a) 以代码为准（全胶囊 `StadiumBorder`）；(b) 改回文档原写的「方圆角 12」 | (a) 保持现状，文档已更正；(b) 要同时改 `game_ready_style.dart` 与 `_lobby_form.dart`，否则两边撞车 |
| 6 | 对局页收敛的范围 | (a) 按 `plan/game-kit-unification.md` Phase 4 原计划「存量不强迁」；(b) 改为「新代码强制 + 存量按收益分批」 | (b) 才能回收 7422 行量级的重复；(a) 则重复长期存在 |
| 7 | `BoardThemeData` 的归属 | (a) 上收到 `lib/core/game_kit/` 或 `lib/core/ui/`；(b) 维持现状 | (a) 消除「游戏模块定义跨游戏共用类型」的层级错位 |
| 8 | 圆形角 token 错位 | (a) 把 10/11/14/18/20/22/28 归一到 `AppRadius` 档位；(b) 登记为形状特例 | 影响是否抽 `AppShapeExtension` |

## 10. 重跑与验证命令

```bash
# 共享层采用率
grep -rlE "core/ui/(atomic|shell|zen|lab|renderers|global_ring)" lib --include="*.dart" | wc -l
grep -rlE "core/ui/(atomic|shell|zen|lab|renderers|global_ring)" lib/core lib/screens --include="*.dart" | wc -l

# 单组件引用数（替换组件名）
grep -rl "core/ui/atomic/base_button.dart" lib --include="*.dart" | wc -l

# 重复样板
grep -rn "showDialog\|AlertDialog(" lib/core --include="*.dart" | wc -l
grep -rn "ScaffoldMessenger.of(context).showSnackBar" lib --include="*.dart" | wc -l
grep -rn "IconButton(" lib/core lib/screens --include="*.dart" | wc -l
grep -rn "CircularProgressIndicator" lib/core --include="*.dart" | wc -l

# 主题化
grep -rn "Color(0x" lib --include="*.dart" | wc -l
grep -rn "withOpacity" lib --include="*.dart" | wc -l
grep -rln "context.colors" lib/core --include="*.dart" | wc -l

# GameReady 五件套采纳率
grep -rn "GameReadyRoomCodeChip\|GameReadyAvatar\|GameReadyStatusBadge\|GameReadyCtaStyle\|GameReadyTitleRule" lib --include="*.dart" | grep -v game_ready_style.dart

# 脚本层聊天/表情接入
for f in $(find lib -name "*script*.dart"); do echo "$(grep -c 'CHAT\|EMOJI' $f)  $f"; done

# 对局页骨架
for f in lib/lab/demos/*_lua/widgets.dart; do echo "--- $f"; grep -nE "^  Widget _build|^class _" "$f"; done

# 超大文件
find lib -name "*.dart" -exec wc -l {} + | sort -rn | head -30
```
