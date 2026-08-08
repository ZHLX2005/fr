# fr 任务意图文档（taskget 领取 · 2026-08-09）

> 来源：kvcli todo `fr` topic（默认空间 / 组 24）。4 条 open，按主题聚成 3 簇。
> 领取时 id：#1 #2 #3 #4（回填 `todo done` 用这些 id）。

## 聚类总览

| 簇 | 主题 | 涉及 kvcli 任务 | 模块 |
|---|---|---|---|
| A | clock demo 体验改造（中文化 + 删除守卫 + zen 主题） | #1、#4 | `lib/lab/demos/clock/**` + `lib/widgets/theme/zen_theme.dart` |
| B | beat 冷启动声音初始化 | #2 | `lib/lab/demos/clock/providers/` + `lib/lab/demos/metronome/` |
| C | profile banner 切换闪屏 | #3 | `lib/main.dart` + `lib/screens/profile/profile_page.dart` |

三簇相互独立，可分别实现、分别回填。

---

## 簇 A — clock demo 体验改造（任务 #1 + #4）

### A1. 中文化（#1 前半）— 整个 clock demo 全译

**目标**：ClockDemo 所有子页（Clocks / Tracks / Dashboard + 编辑器 Sheet + Runner）英文文案改中文。

**范围**（subagent 已逐行定位）：
- `clock_demo.dart`：标题 `Clock`、3 个 AppBar 标题、tooltip、Wipe 对话框、底部 NavigationBar 3 标签
- `clocks_tab.dart`：`Records`、空状态、`Delete`/`Create` swipe 标签、删 clock 对话框、Rename 对话框
- `clock_editor_sheet.dart`：标题、Cancel、Title/Description/Duration/Color/Beat/Total rounds/Mode、节拍模式 label/sub、Add/Save
- `tracks_tab.dart` / `track_runner_page.dart` / `track_editor_page.dart` / `track_records_page.dart` / `dashboard_tab.dart`：全部英文文案

**不翻译**（按惯例）：`bpm`/`BPM`、滚轮单位 `h/m/s`、拍号 `1/4`·`2/4`。

**验收**：flutter analyze 干净；demo 内无残留英文 UI 文案（单位记号除外）；真机目视。

### A2. 删除守卫（#1 后半）— 运行中/暂停记录禁止删除

**现状**：`clocks_tab.dart:382-396` 记录 swipe Delete 与 `track_records_page.dart:98-102` track 记录删除，**无确认、无状态判断**，任意状态可删。记录状态由 `record.completed` 判定（运行中/暂停 = `completed==false`，已完成 = `completed==true`，见 `lab_clock_record.dart:11-14`）。

**目标**：clock 记录 + track 记录都加守卫——只有 `completed==true` 才允许删；运行中/暂停点击删除时弹提示「运行中/暂停的记录不可删除」。

**修法**：删除动作 `onTap` 先判 `record.completed`，false 则 `ScaffoldMessenger` 提示并 return，不调 `deleteRecord`。

**验收**：运行中/暂停记录点删除弹提示且不删；已完成记录正常删除；flutter analyze 干净。

### A3. zen 主题细节（#4）

**现状/根因**：
- clock 创建新记录 FAB（`clock_demo.dart:184-193`）用 `Theme.of(context).colorScheme.primary`（根主题亮色）→ 应改 `ZenColors.sage`（同页其它按钮已正确用 sage）。
- `ZenConfirmDialog`（`zen_theme.dart:413-447`）内 AlertDialog **没设 `backgroundColor`**（应 `ZenColors.surface` 暖米）、Cancel 按钮走默认亮色。
- 2 处 Rename 对话框（`track_records_page.dart:111-128`、`clocks_tab.dart:434-451`）是裸 AlertDialog，无 zen。

**目标**：FAB 改 sage；ZenConfirmDialog 套 `ZenColors.surface` 背景 + Cancel 文字色 zen 化（全局受益）；2 处 Rename 对话框 zen 化。

**验收**：clock demo 内无亮色漏网组件（FAB/对话框均为 zen 米色系）；flutter analyze 干净。

---

## 簇 B — beat 冷启动声音初始化（任务 #2）

**根因**：`LabClockProvider` 构造（`lab_clock_provider.dart:34`）只调 `MetronomeService.instance.ensureReady()` 初始化 Oboe 流，**未挂木鱼采样**；3 个 sample 槽（level 0/1/2）全空 → clock beat 经共享单例播放时命中 C++ 内置合成 click = 用户说的"系统默认声"。木鱼挂载只在进 metronome 页面时发生（`metronome_demo.dart` 的 `_restoreSoundSlots` 读 SharedPreferences `metronome_slot_0/1/2`）。

**目标（用户拍板：还原用户全部 3 槽）**：冷启动时读 SharedPreferences `metronome_slot_0/1/2`，把用户配过的声音全部挂上 = 等价于自动"进过一次 metronome"，弱拍/次强拍/accent 都有正确音色。

**修法**：把 `_restoreSoundSlots`（当前在 metronome 页面）的声音还原逻辑下沉/复用到 app 启动路径（`LabClockProvider` 构造 `ensureReady()` 之后，或 `main.dart` 启动流程），fire-and-forget 异步挂载。复用 `SampleLoader.materializeAsset` + `MetronomeFFI.loadSample`。

**验收**：冷启动直进 clock→beat 播用户配置音色（默认木鱼在 accent 槽），无需先进 metronome；不影响 metronome 页面原有行为；flutter analyze 干净。

---

## 簇 C — profile banner 切换闪屏（任务 #3）

**根因（已亲自读码确认）**：`main.dart:251-284` 传送带切换，`_pages` 为 `const` 列表。动画时同一页挂到树的不同位置（底层→覆盖层 Transform），位置链变化 → `canUpdate` 失败 → 离场页 State 销毁、新建全新 State。新 State `_bannerPath=null`，等 `_loadBanner()` 异步读 SharedPreferences（`profile_page.dart:85-96`）期间露出 `_buildDefaultBanner` 占位。
- 切走 profile：离场的是全新 State、banner 未加载 → 占位 = 用户看到的"切出退化"。
- 切回 profile：内存缓存 + ImageCache 命中、够快 → 正常。

**目标（用户拍板：路径预热，不动切换架构）**：让 banner 路径在 ProfilePage 建建时同步可取，消除 null 占位帧。

**修法**：app 级（`main.dart` `_MainScreenState.initState` 或全局）预读 SharedPreferences `home_banner_path` 存到静态/全局变量；`_ProfilePageState.initState` 同步用它初始化 `_bannerPath`（保留 `_loadBanner` 作兜底/刷新）。可选 `precacheImage(FileImage)` 兜底解码。

**验收**：profile ↔ time 切换不再出现 banner 退化占位帧；首次进入与设置 banner 后行为不变；flutter analyze 干净。

---

## 执行顺序与回填

- 三簇独立，建议顺序：C（最小、主页高频）→ B（声音初始化）→ A（文案最多、收尾）。
- 每簇完成后：① flutter analyze 干净 ② 按 [[feedback_autocommit_on_fix]] 立即 add/commit/push ③ `kvcli todo done <id> --result "..."` 逐条回填。
  - A 簇对应 #1、#4；B 簇对应 #2；C 簇对应 #3。
- id 以 `kvcli todo list --topic fr` 的 open 为准（当前 #1#2#3#4）。
