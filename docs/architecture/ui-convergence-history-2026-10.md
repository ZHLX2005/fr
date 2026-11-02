# UI 收敛治理史（2026-10）

> 本文件是从 fr-engineer skill 的 E 序列中抽出的**历史记录归档**（落地轮次、审计快照、阶段回顾）。
> 当前状态与待办见 `.claude/skills/fr-engineer-flowot/references/Eb03-收敛待办.md`；
> 组件复用全量证据见 `docs/architecture/component-reuse-audit.md`；
> 收敛进度与后续轮次见 `plan/ui-convergence-2026-10-28.md`。
> skill 只保留活清单，历史不再留在册内。

### UI 件聚合记录（2026-10-24）

按「全局组件目录统一聚合」原则完成（用户裁决）：

- 新建 **`lib/core/ui/game/`**（2026-10-28 再拆为 home/ready/chat/emoji/relay 五类别），迁入 8 个联机 UI 件：`game_ready_style.dart`、`game_lobby_page.dart`、`_lobby_form.dart`（自 `game_kit/lobby/`）、`board_chat_overlay.dart`（自 `game_kit/chat/`）、`emoji_overlay.dart`、`emoji_panel.dart`（自 `game_kit/emoji/`）、`relay_connection_bar.dart`、`relay_connection_status_badge.dart`（自 `net_engine/relay_v3/`），全部 `git mv` 保留历史。
- `lib/core/game_kit/` 收敛为纯逻辑（25 文件：spec / slots / identity / skin / Lua 脚本 / 快照模型）；依赖方向恒为 `ui/game/ → game_kit`。
- 顺带修复一处反向依赖：`chat_event.dart` 曾从 `emoji_overlay.dart`（UI）导入快照事件模型 → 抽出 `lib/core/game_kit/emoji/emoji_snapshot.dart`（纯逻辑），双方改为消费它。
- 28 个外部引用方路径已更新（lib + test）；`emoji.dart` barrel 去掉 overlay/panel 导出（barrel 零外部消费方，无破坏面）。
- 验证：`flutter analyze lib` 0 error / 0 warning（149 条 info 与迁移前一致）；p2p 相关测试 189/189 通过。
- 判定规则同步进 《Eb02 分层契约与放置》 §1 的「联机 UI 拆分口径」。

### 职责清晰重构记录（2026-10-28）

用户裁决「global 只放全局件，专类按域拆 `ui/<域>/<类别>/main.dart`」后的 9 轮落地（详见 `plan/ui-convergence-2026-10-28.md` 的 N1–N9）：

- **N1 盘点**：按 import/export 图统计每个组件消费域；global 八类中 7 类确认跨域，错位项 = `ui/global/game`（整域）、`global/chat`（单域 ai_chat）、`global/swipe_action`（单域 clock）。
- **N2**：`ui/global/game` 10 文件 3679 行 → `ui/game/{home,ready,chat,emoji,relay}/`；24 个消费方按实际使用类拆 import（commit 92d196d7）。
- **N3**：PiChat 三件 → `ui/ai_chat/chat/main.dart`；BaseSwipeAction → `ui/lab/clock/swipe_action/main.dart`（2cde265a）。
- **N4**：game 五类别 barrel 契约复核（零绕过/零暗引）；lab 图标两件 → `ui/lab/icons/main.dart`（d0949ef5）。
- **N5**：price_compare 领域模型出 lab demo → `core/price_compare/`，选择 sheet → `ui/lab/price_compare/topic_picker/main.dart`（df9091ac；2026-10-28 移入 lab 域）。
- **N6**：依赖方向复核；focus 首页改走 `fr://` 路由，消除业务层→screens 反向依赖（936f024b）。
- **N7**：`game/chat` 1030 行与 image_picker 555 行拆分；确认 `BaseButton` 已被采用、保留（b8b5c64e）。
- 每轮闸门：`flutter analyze lib` 新增 error/warning = 0（存量 152 issues / 6 warnings）；`flutter test` 不新增失败（基线 +1266 ~3 -10 为环境项）。

### 导航抽离记录（2026-10-24）

页头导航统一为 **`AppNavBar`**（`lib/core/ui/global/nav/app_nav_bar.dart`，L5 shell）：

| 样式 | 规范来源 / 服务对象 |
|---|---|
| `AppNavBar.standard` | **规范样板 = 远程输入设置页（RtSettingsPage）**：AppBar、返回 + 左对齐标题 + actions；`transparent` 变体服务透明 AppBar 页（word_detail） |
| `AppNavBar.floating` | 全出血内容浮层行（SafeArea + 返回钮 + 标题插槽 + actions；`backStyle: solid` 圆钮 / `plain` 裸图标；`centerTitleSlot` 居中标题）。服务 rt 主页头部（玻璃钮走 `leading` 插槽）、line 三页、focus 计时头部 |
| `AppNavBar.pill` | 浮卡胶囊条（返回 + 标题插槽 + trailing；豁免色走显式参数）。服务 novel_reader 顶栏 |

配套：`BaseIconButton` 补 `tooltip` 参数（可访问性）；`RtRoundIconButton` 在 nav 场景由 `leading` 插槽承载（域内其它用点留待后续归并）。

**判定规则**：新页面页头一律用 `AppNavBar`，**禁止再造第三套手写 nav**；特殊视觉通过变体参数/插槽表达，豁免色在调用点显式声明（组件不写死）。

### S1 落地记录（2026-10-23）

| 项 | 结果 |
|---|---|
| `GameReady*` 采纳 | 6 个 lua 对局页（gomoku / go / reversi / surround / jungle / tetris）换用 `GameReadyFloatCard` + `TitleRule` + `RoomCodeChip` + `Avatar` + `StatusBadge` + `CtaStyle`；6 个私有 `_ReadyAvatar` 全删；`coup`（6 人局真差异）按计划保留。`GameReadyFloatCard` 消费方达 **11 个文件**（4 core 房间页 + 6 demo + 定义）。**净减约 750 行**，视觉分叉（皮肤色 vs colorScheme）随之消除 |
| 确认弹窗 | `BaseConfirmDialog` 默认文案改中文「确认/取消」且 `onConfirm` 改可选；收编 **19 处** / 16 文件（含 chess/draughts/xiangqi 认输确认）；bool 契约场景保留 await 用法 |
| SnackBar | `AppNotification` 收编 **144 处** / 31 文件（含 p2p 房间页 60+ 处）；残留 13 处全部合理（10 处带 `SnackBarAction` + 3 处在 `lib/core/ui` 自身） |
| 空态 | `BaseEmptyState` 扩展 `title` / `message?` / `iconSize`；收编 **10 处**（github ×2、system_messages、share_receive、game_center ×2、gallerymanage ×2、net_engine_debug）；`pi_chat_page._EmptyChatView`（含交互 starter chips）与 `rt_pairing_view`（表单内嵌提示文本）**有意保留**——前者非同构，后者收编会改变表单排版 |
| 组件层清理 | 5 个 atomic 自引用 import 全清（`flutter analyze lib/core/ui/global` 归零） |
| 验证 | `flutter analyze lib`：0 error / 0 warning（149 条 info 为存量）；`flutter test` 全量见 QUALITY-AUDIT 同日记录 |

**有意保留的例外**（后续不要当漏网收编）：`coup_lua` 就绪卡、10 处带 action 的 SnackBar、`pi_chat_page._EmptyChatView`、`rt_pairing_view` 表单提示、`gallerymanage` 的 `ios_dialog` 体系（迁移动作见 §3.3 第 1 行，属独立搬移）。

### 与既有计划的衔接

`plan/game-kit-unification.md` Phase 4（`GameRoomShell`）正是 S3 的对局页部分，且明确写着「**存量 9 个对局页不强迁；新游戏强制用壳**」。
**建议修订为「新代码强制 + 存量按收益分批」**：现存重复量已达 7422 行量级，按原计划搁置不划算。
该计划另有 Phase 3（表情包通路）标记 IN PROGRESS，与 §3 热点 C 的「9 个 demo 脚本未接共享段」是同一件事的两面。
