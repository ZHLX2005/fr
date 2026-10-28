# UI 收敛搬运清单（任务 #7，2026-10-28）

> 任务来源：fr 队列 #7「组件/工具函数收敛到 lib/core/ui/」。
> 本轮深度：**只搬运 + 改 import，不改行为、不改调用方写法**。
> 判定依据：Ec01（分层契约）/ Ec02（现状基线 2026-10-23）/ Ec03（位置地图）。
> 状态：**首轮（#7 主体）已完成并提交**（6eb1a29d + 17b5bd72）。2026-10-28 用户给出细粒度目录规范后，转入 /loop 9 轮迭代（见下节）。
> 任务 #8（game 代码/配置抽离）已领取、暂停，待 loop 结束后继续。

## 0. rp-loop：细粒度目录规范与 9 轮阶梯（2026-10-28 用户拍板）

**目录规范**：
- 全局类组件：`lib/core/ui/global/<类别>/main.dart` —— 一类一目录，`main.dart` 是唯一入口。
  类别总行数 ≤ ~400 行时 main.dart 直接装下全部代码；超出时 main.dart 做 barrel、实现文件同目录并列。
- 工具函数：`lib/core/utils/<类别>/main.dart`，同粒度。
- 非全局件不动：`lib/core/ui/global_ring/`（特性件）、`lib/core/ui/lab/`（lab 域件）留在原位。

**类别划分**：button / nav / dialog / dot / section / empty_state / swipe_action / notification / chat / zen / game / renderers。

**9 轮阶梯**（每轮一个可验证批次，完成即在文末「进度记录」追加）：

| 轮 | 批次 |
|---|---|
| R1 | 规范落档 + 单文件小类别迁移：dot / section / empty_state / swipe_action + utils/format |
| R2 | notification（41 消费方）+ dialog（base_dialog + base_ios_dialog 合并目录） |
| R3 | button 族（base_button + emphasis_button + base_icon_button）+ nav 族（app_nav_bar + nav_entry_icon + quick_nav_bottom_bar） |
| R4 | chat（pi_chat_style + pi_day_divider）+ zen（zen_theme + zen_date_picker） |
| R5 | renderers（6 文件，barrel 模式） |
| R6 | game 族（10 文件，barrel 模式） |
| R7 | C1 RtRoundIconButton→BaseIconButton 玻璃变体合并；C2 RtConnDot→BaseStatusPill；C3 zen_controls↔_Zen* 归一 |
| R8 | 工具收编第一批：formatFileSize×3、formatDate、formatBytes 等私有重复 → utils 共享件（改调用点） |
| R9 | 终检：analyze/test 全闸 + 旧路径零残留 grep + Ec01/Ec02/Ec03 文档同步 + 基线数据刷新 |

**每轮验证闸**：`flutter analyze lib` 新增 error/warning = 0（存量基线 152 issues / 6 warnings）；涉及测试面则 `flutter test`（基线失败 10 项为环境项：Notion 无 token ×6、relay 真服务器 ×1、line 计时 ×2，不得新增失败）；旧路径 grep 零残留。
**每轮提交**：Conventional Commits；显式路径 add（禁 `git add .`；test/ 白名单外已跟踪文件用 `git add -f`）。

## 进度记录

### R1（2026-10-28，commit 4f3920c9）

- 完成：dot / section / empty_state / swipe_action → `lib/core/ui/global/<cat>/main.dart`；time_format → `lib/core/utils/format/main.dart`；34 消费方 import 替换；被搬文件内部相对 import 按新深度 +1 级修正（atomic 单层 vs global/<cat> 双层）。
- 验证：analyze lib 152 issues 持平基线（新增 0）；test/core + zen_theme_test 失败 3 项与基线一致。
- 经验：**global/<cat>/main.dart 比 atomic/ 深一层——后续每轮搬完必须修内部 import 深度**；grep 旧路径时注意注释里也可能引用（spacing.dart 案例，属期望的同步）。
- 下轮（R2）：notification（app_notification.dart，41 消费方）+ dialog（base_dialog.dart + base_ios_dialog.dart → global/dialog/）。

### R2（2026-10-28，commit 167c5c6f）

- 完成：app_notification → `global/notification/main.dart`（41 消费方）；base_dialog + base_ios_dialog 合并 → `global/dialog/main.dart`（366 行，24 消费方）。
- 验证：analyze lib 152 issues 持平；flutter test 全量 +1266 ~3 -10，与基线逐项一致。
- 经验：单类别多文件且总行数 ≤400 时可**合并**进一个 main.dart（保留原类名，调用方只需改 import 路径）；>400 才用 barrel 模式。
- 下轮（R3）：button 族（atomic/base_button.dart + shell/emphasis_button.dart + atomic/base_icon_button.dart）+ nav 族（shell/app_nav_bar.dart + shell/nav_entry_icon.dart + shell/quick_nav_bottom_bar.dart）。

### R3（2026-10-28，commit 506acbd5）

- 完成：button 族三件合并 → `global/button/main.dart`（295 行，40 消费方）；nav 族三件 → `global/nav/`（674 行，超 400 用 barrel），`global/nav/main.dart` 为唯一入口（22 消费方）。
- 验证：analyze lib 152 issues 持平；flutter test +1266 ~3 -10 与基线一致；旧路径零残留。
- 经验：①同一文件原本 import 家族内多个成员时，sed 后会变成**同一目标重复 import**（Dart 报 unnecessary_import）——映射到同一 main.dart 时必须去重（`awk` 按行去重即可）。②`lib/core/nav/`（路由与条目模型）不在 `ui/` 下，从 `ui/global/<cat>/` 引用需退 **3** 级，`ui/lab/` 才是 2 级——搬完逐个文件核对 import 深度。
- 遗留待裁决：**BaseButton 仍零业务引用**（Ec02 判死代码，与 EmphasisButton 职责重叠）——本轮只搬不删，需用户裁决去留。
- 下轮（R4）：chat（ui/chat/pi_chat_style.dart + pi_day_divider.dart）+ zen（ui/zen/zen_theme.dart + zen_date_picker.dart）。



## 1. 纯搬运（零 API 变化，git mv / 文件拆分 + import 更新）

| # | 源 | 目标（提案） | 说明 | 消费方（import 需更新） |
|---|---|---|---|---|
| M1 | `lib/core/gallerymanage/ios_dialog.dart`（309 行；类 `IosDialogAction` / `IosDialogShell` / `_IosDialogRoute`） | `lib/core/ui/atomic/base_ios_dialog.dart` | 通用弹窗套件寄居业务模块（Ec03 §4）；本轮**保留类名不改**，`Base*` 前缀重命名留待后续（避免本轮改调用方） | gallery_manage_page.dart ×1 |
| M2 | `lib/core/ai_chat/pi/pi_chat_ui.dart` 中拆出 `PiChatTokens`(L15) / `PiChatColors`(L60) / `PiDayDivider`(L345) | ⏳ 落点待用户定（见问题①） | 聊天通用样式 token 与分隔件；其余 5 类（PiComposer 等）是 ai_chat 专属，**留在原文件** | pi_chat.dart、pi_chat_page.dart ×2 |
| M3 | `lib/lab/utils/time_format.dart`（38 行；`formatDuration` / `formatTime` / `formatRecordDate`） | ⏳ 落点待用户定（见问题②） | 唯一真正跨模块共享的工具文件（clock + recorder 两域共用）；全仓其余「同名工具函数」都是类内私有重复，见 §4 | clock widgets ×6、recorder ×2、`test/widgets/theme/zen_theme_test.dart`（package import） |
| M4 | `lib/core/net_engine/relay_v3/relay_v3_widget.dart`（`RelayV3Lobby`，565 行）+ `participants_grid.dart`（`LobbyParticipants` 等，~300 行） | `lib/core/ui/game/relay_v3_lobby.dart` + `lib/core/ui/game/lobby_participants.dart` | **Ec03 清单外新发现**：逻辑层残留联机 UI 件（2026-10-24 聚合时漏网）。两文件只 import material + relay 逻辑 + theme/context，无 core/ui 反向依赖，可干净搬 | net_p2p/net_p2p_discovery_host.dart ×1；两文件互引及 relay_device_id/relay_v3_transport 改相对路径 |

## 2. 合并/归一类（超出纯搬运，涉 API 或形态，需用户点头）

| # | 项 | 现状核实结论 | 工作量 |
|---|---|---|---|
| C1 | `RtRoundIconButton` → 合并进 `BaseIconButton` | 是玻璃拟态圆钮（BackdropFilter blur + 特殊 decoration + 触感反馈 + kRtTopControlHeight 尺寸），与 BaseIconButton 三 variant 均不同形；合并=新增 glass 变体 + haptic | 中；消费方 rt_page.dart + rt_layout_capsule.dart |
| C2 | `RtConnDot` → 与 `BaseDot` 合并 | **Ec03 判断需修正**：RtConnDot 实为「8px 圆点 + 已连接/未连接文字」的胶囊（pill），BaseDot 是 12×12 裸点，形态不同。合理动作是新建 atomic `BaseStatusPill`（dot+label）；另注意其硬编码 `Color(0xFF34A853)` 绿，迁移时应走 ColorStrategy | 小~中；消费方 rt_touch_surface.dart 内部 ×1 |
| C3 | `zen_controls.dart` ↔ `timetable_settings_page.dart:388,428` 的 `_ZenSegmentButton`/`_ZenActionButton` 归一 | timetable 模块内重复对；归一后可顺势上移 `lib/core/ui/zen/`（zen 风格控件本属 zen 域） | 中 |

## 3. 待裁决（类型搬家，Ec03 标「待裁决」）

| # | 项 | 选项 |
|---|---|---|
| D1 | `BoardThemeData`（定义于 `lib/core/surround_game/board_theme.dart:43`，21 文件跨游戏消费；reversi 另有 `lib/core/reversi/board_theme.dart` 平行令牌） | a) 数据模型上收 `game_kit/`；b) token 部分进 `design_tokens/`；c) 本轮不动（归任务 #8 game 抽离一并处理） |

## 4. 留原地（Ec01 口诀：换个模块用不上就不下沉）

- `lib/lab/demos/clock/utils/clock_chain_util.dart`（314 行）、`clock_color_util.dart`（170 行）——clock 内部。
- `lib/lab/demos/recorder/recorder_list_utils.dart`（76 行）——recorder 内部。
- 类内私有重复（**收编另立任务**，本轮不动）：`_formatFileSize`×3（api_test）、`_formatDate`×4（chess_replay/focus/gallery/timetable）、`_formatDuration`/`formatDuration` 多处（sudoku/line/focus/clock）、`formatBytes`×2、`formatUnitPrice`/`formatCreatedAt`（price_compare）。
- `lib/core/chess/skins/` 剩余文件多为 chess 专属（chess_skin_localizer 160 行 i18n、chess_skin_settings_page 912 行 UI、chess_skin 模型）；与 `game_kit/skin/` 的成套同构归一（public_kv_reader 仅 3 行转发等）属专项，建议并入任务 #8 或另立。
- coup_lua 6 人局手牌区等 demo 私有件（Ec01 明确保留）。

## 5. 执行约束（确认后照此办）

1. `git mv` 保留历史；禁 `os.rename` + `git add -u`（新文件会丢在 index 外）。
2. import 整路径精确替换，禁裸 substring 全局替换；改完 `grep` 复查旧路径零残留。
3. 只搬不改语义；不碰调用点写法（裸 AlertDialog/SnackBar/IconButton 收编不在本轮）。
4. 本仓 Dart 禁空感知元素语法（`?[]`/`?{}`，hive_generator 锁 analyzer 6.x）。
5. 验证闸：`flutter analyze lib` 0 error/0 warning + `flutter test` 全量全绿 + `dart run build_runner build --delete-conflicting-outputs`（A08 要求）。
6. commit 用 Conventional Commits；commit 前逐条 `git status` 核对归属，禁 `git add .`。
