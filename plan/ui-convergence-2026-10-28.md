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

### R4（2026-10-28，commit 9ca8fa1a）

- 完成：chat 族（149 行）合并 → `global/chat/main.dart`；zen 族（393 行）合并 → `global/zen/main.dart`。
- 验证：analyze lib 152 issues 持平；flutter test +1266 ~3 -10 与基线一致；旧路径零残留。
- 经验：barrel 文件里若同时 export 同一家族的多个旧文件，合并后会出现 **duplicate_export 警告**——`lib/core/ai_chat/pi/pi_chat.dart` 合并后需删掉重复 export 行（analyze 会直接报）。
- 下轮（R5）：renderers 族（6 文件，barrel 模式）→ `global/renderers/`。

### R5（2026-10-28，commit e070ca1b）

- 完成：renderers 6 文件（1097 行）→ `global/renderers/`，`global/renderers/main.dart` 作 barrel（9 消费方）；旧目录 `ui/renderers/`、`ui/shell/`、`ui/atomic/` 已清空移除。
- 验证：analyze lib 152 issues 持平；flutter test +1266 ~3 -10 与基线一致；旧路径零残留。
- 经验：`git add -A <路径>` 里若混入**已删除的目录**，整条命令直接失败（不匹配任何文件），后续新增文件（barrel）会漏暂存——新增 barrel 后必须 `git status` 复查未跟踪项再提交。
- 遗留：`image_picker_widget.dart` 555 行超 400 行阈值（Ec03 已记），待专项拆。
- 下轮（R6）：game 族（ui/game/ 10 文件，barrel 模式）→ `global/game/`。

### R6（2026-10-28，commit 1eac0191）

- 完成：ui/game/ 10 文件（3679 行）→ `global/game/`，`global/game/main.dart` 作 barrel（49 消费方）；ui/ 现存 `global/`（8 类别）+ `global_ring/` + `lab/`。
- 验证：analyze lib 152 issues 持平；flutter test +1266 ~3 -10 与基线一致；旧路径零残留。
- 经验：①同文件**相对 import + package import 双写**同一目标时，按行去重不生效（字符串不同），需人工删其一（jungle_chess_lua 案例）。②被搬文件的头部路径注释要一并改（`_lobby_form.dart` / `relay_v3_lobby.dart` 案例）。
- 下轮（R7）：C1 RtRoundIconButton → BaseIconButton 玻璃变体合并；C2 RtConnDot → 新建 BaseStatusPill；C3 zen_controls ↔ _Zen* 归一。



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

### R7（2026-10-28，commits 6dc46ae4 / 825828a4 / ace223cf）

- C1（6dc46ae4）：`BaseIconButton` 新增 `glass` variant（实现自 RtRoundIconButton），rt_page 两处迁移，删除域内自造件；布局胶囊测试同步迁移。
- C2（825828a4）：**RtConnDot 实为零引用死代码**（全仓仅定义处），按 Ec01 零引用裁决**直接删除**，不新建 BaseStatusPill（给死代码造新家没有意义）。
- C3（ace223cf）：timetable_settings_page 的 `_ZenSegmentButton`/`_ZenActionButton` 私有重复对改用共享 `zen_controls.dart`（8 处调用点）。
- 验证：analyze 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 经验：删类/改 API 后必须 grep **test/** 引用（`test/core/remotetype/rt_layout_capsule_test.dart` 因引用被删类导致整文件编译失败，表现为 `loading ... [E]`，不在常规失败列表里显眼）。

## 第二轮 9 轮：职责清晰重构（2026-10-28 用户新裁决）

**规范修正**：`ui/global/` 只放**真正的全局组件**（跨域复用）；游戏/其他专类组件按域拆出：
`ui/<域>/<类别>/main.dart`，示例：`ui/game/button/main.dart`、`ui/game/home/main.dart`。
判定口径：被 ≥2 个域消费 → `ui/global/`；只服务一个域 → 该域 `ui/<域>/<类别>/`。

**现状问题**：`ui/global/game/` 10 文件 3679 行是联机游戏专用件，放全局层属职责错位；其余 global 类别也需逐件核验消费面。

| 轮 | 批次 |
|---|---|
| N1 | 全量职责盘点：每个 ui 组件 → 消费域集合 → 归属结论（global / 某域），落本文件表格 |
| N2 | 拆 `ui/global/game/` → `ui/game/<类别>/`（按消费面细分，如 button/home/lobby/chat/emoji/relay） |
| N3 | global 其余类别逐件核验归位（chat/zen/renderers/notification 等，只服务单域的移出） |
| N4 | 域内（game）细分类别整理与 barrel 校正 |
| N5 | 其余业务域（remotetype/line/note/ai_chat 等）内 UI 组件的域级 ui/ 目录建立 |
| N6 | 跨域引用清理：域间互引检查、依赖方向复核（逻辑层禁 import UI） |
| N7 | 收编遗留：image_picker_widget 555 行拆分、BaseButton 死代码裁决执行 |
| N8 | Ec01/Ec02/Ec03 文档同步到新结构；引用路径全量校对 |
| N9 | 终检：analyze/test 全闸、旧路径零残留、目录树与规范逐条比对 |

### N1（2026-10-28）职责盘点结论

统计口径：import/export 图按消费方文件所在顶层域聚合（脚本见本会话；`core/__infra__` = 共享层内部消费，不计入业务域）。

| 组件 | 消费文件数 | 消费域 | 结论 |
|---|---:|---|---|
| global/button | 42 | github / surround_game / timetable / word_drag / screens/profile / lab×2 / … | **global 保留** |
| global/dialog | 24 | ai_chat / timetable / clock / chess / remotetype / relation_calc / doubletime / draughts | **global 保留** |
| global/notification | 40 | ai_chat / screens/profile / chess / timetable / remotetype / doubletime / draughts / … | **global 保留** |
| global/nav | 20 | line / screens/profile / screens/settings / focus / remotetype / app_lifecycle / ai_chat / novel_reader | **global 保留** |
| global/empty_state | 12 | github / clock / ai_chat / gallerymanage / share_receive / timetable / recorder | **global 保留** |
| global/section | 8 | timetable / clock / relation_calc / metronome / recorder | **global 保留** |
| global/zen | 25 | timetable(7) / clock(7) / recorder(3) / relation_calc(3) / focus | **global 保留** |
| global/renderers | 8（+barrel） | screens/profile(4) / services(3) / timetable(1) | **global 保留** |
| global/dot | 3 | clock(2) / recorder(1) | 临界（2 个 demo 域）→ **暂留 global**，若用户要求严格按单域判定再移 |
| global/swipe_action | 1 | clock | **单域** → `ui/lab/clock/swipe_action/main.dart`（N3 处理） |
| global/chat（PiChat 三件） | 3 | ai_chat | **单域** → `ui/ai_chat/chat/main.dart`（N3 处理） |
| **global/game（10 文件 3679 行）** | 26（barrel） | chess / draughts / sudoku / xiangqi / 各 lua demo | **单域（游戏域）** → 拆 `ui/game/<类别>/`（N2） |

**ui/game 类别映射（N2 执行）**：

| 现文件 | 目标 |
|---|---|
| game_lobby_page.dart、_lobby_form.dart、relay_v3_lobby.dart、lobby_participants.dart | `ui/game/home/main.dart`（大厅/入口 + 参与者圆环，4 件 ≤400 行则合并，否则 barrel） |
| game_ready_style.dart | `ui/game/ready/main.dart`（就绪六件套） |
| board_chat_overlay.dart | `ui/game/chat/main.dart` |
| emoji_overlay.dart、emoji_panel.dart | `ui/game/emoji/main.dart`（2 件合并） |
| relay_connection_bar.dart、relay_connection_status_badge.dart | `ui/game/relay/main.dart`（2 件合并） |

**域定义**：game = 全部对局/联机游戏（chess/draughts/sudoku/xiangqi/reversi/jungle_chess/surround_game + 9 个 lua demo）；ui/game/ 内部再按类别分 main.dart。

**N1 结论**：global 八大类别中 7 个确为跨域（button/dialog/notification/nav/empty_state/section/zen/renderers）；错位项 = global/game（整域）、global/chat（单域 ai_chat）、global/swipe_action（单域 clock）、global/dot（临界，维持）。

### N2（2026-10-28，commit 92d196d7）

- 完成：`ui/global/game/` 拆为 `ui/game/{home,ready,chat,emoji,relay}/`（home 4 件 barrel；ready/chat 单文件 main；emoji 2 件 barrel；relay 2 件合并 main）。24 个 lib 消费方按实际使用类拆分 import；global/game 移除。
- 验证：analyze lib 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 经验：①**test/ 内引用 lib 必须用 `package:` 导入**——相对路径 `../../../../lib/...` 与 package URI 形成重复库视图，`find.byType` 身份不匹配导致"widget 找不到"（3 个测试文件踩中）。②按类拆 import 时类名可能出现在**注释**里（8 个 lab demo 误加 home import），analyze 的 unused_import 会兜底，清掉即可。③合并文件时按行号切段容易把 import 行卷进正文，切完立即 grep `^import` 复核。
- 下轮（N3）：global 其余错位项——chat（PiChat 三件，单域 ai_chat）→ `ui/ai_chat/chat/main.dart`；swipe_action（单域 clock）→ 域内 ui 目录。dot 保持 global（已标注临界）。

### N3（2026-10-28，commit 2cde265a）

- 完成：`ui/global/chat` → `ui/ai_chat/chat/main.dart`（3 消费方）；`ui/global/swipe_action` → `ui/lab/clock/swipe_action/main.dart`（唯一消费方 clock demo）。global 剩 9 类别，全部为跨域件（dot 为 clock+recorder 两 demo 域，标注临界维持）。
- 验证：analyze lib 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 域目录约定（本轮确立）：`ui/<域>/<类别>/main.dart`；lab demo 域按 `ui/lab/<demo>/<类别>/main.dart`（如 clock）。若用户希望 demo 域平铺为 `ui/<demo>/...`，只需在终检前统一调整。
- 下轮（N4）：game 域内类别整理——barrel 契约复核（home/emoji/ready/chat/relay），确认无跨类别暗引、入口唯一。

### N4（2026-10-28，commit d0949ef5）

- 复核：`ui/game` 五类别 barrel 契约成立——外部零绕过（全部走 main.dart）、零跨类别暗引；导出完整（home 3 public、emoji 2、ready/chat/relay 单文件即 main）。
- 顺手归一：lab 域件 `lab_demo_icon` + `lab_demo_icon_lookup`（335 行）合并 → `ui/lab/icons/main.dart`（13 消费方）。
- 遗留标记（N7）：`ui/game/chat/main.dart` 单文件 1030 行、`ui/global/renderers/image_picker_widget.dart` 555 行，均超 400 行阈值。
- 验证：analyze lib 152 持平；test 失败集合与基线一致（全为环境项）。
- 下轮（N5）：跨域错位扫描——业务模块内被 ≥2 个域消费的 UI 件（Ec03 §4 剩余项之外的新发现），需上收 global 或域级 ui。

### N5（2026-10-28，commit df9091ac）

- 扫描：业务模块内无「被 ≥2 业务域消费的通用 UI 件」遗留（jungle/surround 跨消费均在游戏域内）；global 层职责已完整。
- 反向错位修复：price_compare 领域模型（127 行，含 PriceRow/PriceTopic/PriceTopicSummary + 格式化）住在 lab demo 却被 core/storage Hive 仓库 + services 策略 + demo 三方消费 → 模型上收 `lib/core/price_compare/price_compare_models.dart`；主题选择 sheet → `lib/core/ui/price_compare/topic_picker/main.dart`。
- 标记未修（语义改动）：`core/focus/focus_home_page.dart` 直接 import `screens/profile/lab/demo_detail_page.dart`（业务层向上依赖应用层），正确解是改走 fr:// 路由——留 N6 评估或独立任务。
- 验证：analyze lib 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 下轮（N6）：依赖方向复核——逻辑层（game_kit/net_engine/message_net/theme）禁 import core/ui 全量扫描；业务层向上依赖清单与处置。

### N6（2026-10-28，commit 936f024b）

- 依赖方向复核结论：
  - 逻辑层（game_kit / net_engine / net_p2p / message_net / theme / storage / nav / schema）→ `core/ui` 的 import：仅 net_engine/settings 与 net_p2p 两处**页面文件**消费 AppNotification（文件本身即 UI 页，非逻辑越界），保持。
  - 业务层 → `screens/`：`core/focus/focus_home_page.dart` 反向上依赖已修（改为 `FrNavigator.handle('fr://lab/demo/<slug>')`）；`core/nav/nav_catalog|nav_bootstrap` 与 `core/schema/handlers/lab_*` 属应用装配层职责，保持；`core/game_kit/game_center_catalog → screens/.../const_game_center`（逻辑层引常量注册表）随任务 #8 game 配置抽离处理。
- 验证：analyze lib 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 下轮（N7）：收编遗留——BaseButton 死代码裁决（删）、image_picker_widget 555 行拆分、game/chat/main.dart 1030 行拆分。

### N7（2026-10-28，commit b8b5c64e）

- BaseButton 裁决**更正**：Ec02 的「零引用死代码」已过期——`ui/global/empty_state/main.dart` 实际在用，**保留不删**（与 RtConnDot 的真死代码不同）。
- `ui/game/chat/main.dart` 1030 行 → main 375 + chat_pill 142 + composer 419 + painters 101（`part of` 保持内部类不对外导出）。
- `ui/global/renderers/image_picker_widget.dart` 555 行 → config 79 + widget 424 + page 63，barrel 补导出；config 补 `image_cropper` import。
- 验证：analyze lib 152 持平；flutter test +1266 ~3 -10 与基线一致。
- 下轮（N8）：Ec01/Ec02/Ec03 文档同步到新结构（global/game 拆分、hierarchical ui/<域>/<类别>、price_compare 归位、lab icons 合并等），全量校对 skill 内路径引用。

### N8（2026-10-28，commit 6ed4de7c）

- Ec03 全文重写（§0 目录规范 + §1 实况树 + §4 错位清单 + §5 速查）；Ec01 分层表/联机口径/落点规则/反模式更新；Ec02 组件表与重跑命令刷新并追加 N1–N7 记录；Ea/Eb 共 7 个文件路径映射；两份历史审计文档加「基线已过期」标注。
- 验证：references 目录旧路径（core/ui/atomic|shell|zen）零残留；Ea03 行号校正。
- 下轮（N9）：终检——目录树逐条比对规范、analyze/test 全闸、旧路径全仓 grep、kv 回填。

### N9（2026-10-28，终检）

| 检查项 | 结果 |
|---|---|
| 目录规范（global 只放跨域件 / ui/<域>/<类别>/main.dart） | ✅ 18 个类别 main.dart；global 9 类全部跨域（dot 临界已标注）；专类域 = game(5 类) / ai_chat(1) / price_compare(1) / lab(2) |
| 类别入口与 barrel 规则 | ✅ 每类有 main.dart；≤400 合并、>400 barrel；私有 `_` 文件不导出；零绕过 main.dart 的直连 |
| 旧路径残留（lib/test） | ✅ 零（仅历史注释保留「归位自 …」说明） |
| references 文档旧路径 | ✅ 零（历史记录段落中的旧结构描述为审计留痕，保留） |
| `flutter analyze lib` | ✅ 152 issues（与基线逐项一致，0 error；6 warning 均为存量） |
| `flutter test` | ✅ +1266 ~3 -10（失败集合与基线一致，全为环境项：Notion 无 token ×7 行 / line 计时 ×2 / relay 真服务器 ×1） |

**第二轮 9 轮（N1–N9）完成**。累计本轮提交：ccd48d83(N1) 92d196d7(N2) 2cde265a(N3) d0949ef5(N4) df9091ac(N5) 936f024b(N6) b8b5c64e(N7) 6ed4de7c(N8) + 各轮 plan 记录。

**已知遗留（不在本轮范围）**：①任务 #8（game 代码/配置抽离）仍暂停——BoardThemeData 上收、kGameMeta 注册表、lua demo 常量/prefs 分离均归它；②Ec02 S2/S3 的组件补缺与联机对局页收敛未动；③`coup_lua/widgets.dart` 1702 行等 lab demo 超大文件未拆（非 UI 层职责）。

## 干净化阶段（2026-10-28，用户指令「继续解耦直到完全干净」）

| 批次 | 内容 | commit |
|---|---|---|
| 死代码 | 删除 16 个零引用文件（约 2100 行：page_curl_view 939、chat_sheet 582、image_picker_service、block_editor ai 工具组等），逐个核实 import 图与最近触达时间 | a5a16f5c |
| 配置/代码分离 | 5 个 lua demo 的死 AliasPrefs + alias key 删除；team_card SetupPrefs/SetupState 外提 team_card_state.dart | 08b99b91 |
| 领域模块化 | 新建 core/game_center/（game_meta + catalog + sync，自 screens/game_kit 归位）；BoardThemeData → core/theme/board/ | 08b99b91 / 4ed30064 |
| 工具收编 | formatFileSize 归一（4 份私有实现 → utils/format） | a92129af |
| 分析器清零 | 152 issues → **No issues found**：6 warning 全修；withOpacity 21、MaterialState 4、RadioGroup 3、DropDown value→key+initialValue 4、RawKeyboard→KeyboardListener、BLE platformName、Color.toARGB32、dart fix 40 处、const 18 处、async context 5 处带守卫修复；use_null_aware_elements 显式关闭（本仓禁空感知语法） | b93f0762 / f38562ef |
| 终检 | 再删 2 个真死文件（clock_color_util 169 行、chat_tool 8 行）；旧路径零残留 | 本记录 |

**终态**：`flutter analyze lib` = No issues found（0/0/0）；`flutter test` = +1266 ~3 -10（与基线一致，全为环境项）；工作树干净。
**保留项（有意）**：零消费模块桶（reversi/surround_game/xiangqi/services/metronome/emoji 等 `main.dart` 公开入口）、`ui/game/emoji`（Phase 3 计划接线）、`reversi/board_theme.dart` 平行令牌（并轨属语义改动）。

## Demo 遍历：可抽离组件审计（2026-10-28，用户指令「遍历所有demo依次检查有无可抽离的组件」）

方法：全量扫描 55 个 demo 注册 / 39 个 demo 目录，按**归一化代码**（去注释、压空白）比对类块与方法体，不靠类名相似——类名相同（`OnlineGamePage`）不等于实现相同。

### 已抽离（本轮落地）

| 重复内容 | 份数 | 归属 | commit |
|---|---|---|---|
| snapshot context 访问器 players/readyMap/actionPermissions/hostId/winner | 7 demo × 5 = 31 | `game_kit/snapshot/main.dart`（协议契约层） | 4db96221 |
| `canPerform` 动作权限判定（any/host/current_player） | 2 demo | `game_kit/snapshot/main.dart`（Ca03 契约） | 8f0e2f9c |
| 认输确认弹窗（裸 AlertDialog） | 3 demo | **改用已有件** `BaseConfirmDialog`（Ec01 §2 第 2 步） | c007a19d |
| 底部动作按钮（图标+文案） | 3 demo | `ui/game/action/main.dart` → `GameBottomAction` | c007a19d |
| 对局页阶段分派（lobby/ready/playing/ended） | 3 demo | `ui/game/shell/main.dart` → `GamePhaseBody` | bec21b04 |

### 判定为不抽（附理由）

| 候选 | 理由 |
|---|---|
| `_GridPainter`（go/gomoku 棋盘绘制，97% 相似） | 棋盘尺寸与星位是棋种特有（kGoSize vs 五子棋 15 路），抽离须参数化视觉，收益低于改动面 |
| `_buildLobby/_buildPlaying/_buildFinished` 正文 | 相似度 96.7%–99.9% 但含棋盘、规则、按钮等游戏特有内容 —— 属 Ec02 S3 的「对局页骨架收敛」，需参数化策略对象，是独立重构项（数千行级），非本轮解耦范围 |
| `_deal`/`_ack`（1–4 行薄包装） | 抽离收益低于噪声（各 1–4 行），保留 |
| `_setPending`/`_onSnapshot`（落子预览/快照处理） | 棋盘坐标与规则私有，不可跨游戏复用 |
| `OnlineGamePage` 类壳 | 类名相同但实现逐字不同（4 份完全相同 / 3 份 86–94%），差异在 Room 类型与 build 内部，共享需抽策略对象 |
| 其余 demo（clock/recorder/network/team_card/metronome/block_editor 等） | 方法级扫描零跨 demo 重复；模块内部件按 Ec01 口诀留在模块内 |

### 扫描结论
- demo 层**跨 demo 逐字重复**仅集中在 7 个 lua 联机游戏；本轮已把其中「协议访问器 + 权限判定 + 通用 UI 件」全部归位。
- 余下相似部分是「结构相似但内容私有」的对局页骨架，需要策略化重构（Ec02 S3），不是复制粘贴式解耦。
