# FR 工程 Skill Ref — 质检记录（2026-10-20）

> 适用范围：仅 `.claude/skills/fr-engineer-flowot/` 活动 refs。旧内容如需对照只读 `.claude/skills-archive/pre-fr-engineer-flowot/`；以当前代码/测试为实现证据。归档 refs 不属于活动指导面。
>
> **本轮要求**：每个活动 ref 要有明确触发/用途和读者下一步；事实须能追溯到当前源码、配置、测试或明确链接的外部资料；Error/API 状态码给出症状、检查、修复和验证，仓外无法核实时标待确认。无指导价值且无依据的内容删除；有用的设计建议明确标为建议，不伪装成当前实现。

## 审计基线

- 活动 references 文件数：65（全部为 A–H 序列 refs；`UNMAPPED-REVIEW.md` 已于 2026-10-20 按用户指令移除——标准 SOP 序列文档已就位，后续不再进行迁移，未归序旧材料仅存于归档/Git 历史）。
- 覆盖范围：A 9，B 3，C 9，D 4，E 20，F 5（F00、Fa01–Fa04；专门 Rive refs 已按用户要求删除），G 9，H 6。
- Rive 专门文档 Fb01–Fb19 已从活动 refs 删除；其余应用运行时/资产/依赖不在本次删除范围。
- 当前仓库 server-only Relay/GoFrame 状态码合同不能从 Flutter 客户端源码单独证实，必须标为服务器端来源/真实 E2E 待核实。

## 逐序列审计记录

| 序列 | refs 覆盖 | 结果/本轮更正 | 证据边界 |
|---|---:|---|---|
| A | 9/9 | 修正 A01 的 MethodChannel translator 真路径，移除“原始中文 deep link 必崩”的旧说法；区分 `fr://` deep link 与普通页面 Navigator；重写 A03 以当前 Lab 源码和游戏目录三方登记为准；A06 删掉 Rive 专用 merge demo 内容，仅保留通用 slug alias 工作流；TimePage 主页骨架与 A07（+08:00 时间戳、测试入库口径、uploadByKey 旧契约、401 断言边界、目录例外）也已修正。 | A/B 只读 reviewer 逐份审阅；Notion 真实 HTTP error code 未通过 response-mocking/E2E 验证。 |
| B | 3/3 | 原 Ba 场景路由保留。Ba01 Selection Cancel 的实际代码调用 clear 无 setState，是已核实代码问题，登记为 follow-up，不修改业务行为。Ba02 需要将当前 pi/Hive 入口、Format/receipt 持久化缺口与示范契约区分，见待落实。 | Chat 事实对照当前 `home_page.dart`、`message_strategy_di.dart`、pi repository、receipt OCR flow；本轮未运行 UI 测试。 |
| C | 9/9 | RelayLua 子序列 ref 全审。C00 action 身份传播/HTTP 状态解释需要核对来源；Ca01 `myId` 前缀 fallback 与“只信服务端身份”原则矛盾；Ca03 WIN role sample 与正文冲突；Cb01 旧 `LobbyEntryPage` checklist 与当前 `GameLobbySpec` 不一致；Cb02 补字符集现状与满员处理动作（server body 合同仍标待服务端来源）；Cb03 §4.5 标记斗兽棋专属历史样例；Cb04 状态机生命周期对齐当前控制器；Cc01 已按当前 team_card 脚本对齐。 | Relay service 当前工作树无 Go 服务端实现；状态码/body/隐私 redaction 不做客户端推断。 |
| D | 4/4 | D00–D03 与当前 HiveStore、generated adapter、HiveRepository、StorageRegistry 基本对齐；要明确 StorageManager/导入导出等存储基础边界例外。 | `hive_generator`、TypeIds、repositories、CI build_runner 已核对。 |
| E | 20/20 | 逐份审阅。Ea05 底栏参数、Ea06 游戏中心头部与蒙版、Ea12 try/finally、Ea13/Ea14 序列标号、Eb03 API/path、Eb04 过期审计统计、Eb05 错称 compile-time fail 均需修正；Ea04 的 80px 改为衰减目标；Ea05/Ea06 加当前实现对照；Ea08–Ea11 补链接/共享 CTA 对照；Ea12 补守卫边界；Ea13/Ea14/Eb02/Eb03/Eb04/Eb05 已修正（含 Sudoku 通道 caveat、224/301 快照口径、运行时而非编译期保证、torchProtect.protectPresets）。 | 审阅者核对 `quick_nav_bottom_bar.dart`、`game_center_page.dart`、Notion image host、theme context/strategy 与 tests；不把设计配方自动等同于生产实现。 |
| F | 5/5 | Rive 专门 refs 已依用户指令删除；F00 简化为 Fa 外部资产。Fa02 的脚本与文档资源文件格式契约、gomoku `board` 必选、索引读取失败时继续全量覆盖等需优先校准；Fa03/04 emoji 解析与缓存语义、GameSkinLocalizer 15s timeout、add_skin chess png 约定需修正。 | 未执行任何远端 upload/KV 发布；只静态核对脚本与客户端源码。 |
| G | 9/9 | G00–Gc01 全审。Ga01/GB01 关于 minSdk≥24 与 Gradle `flutter.minSdkVersion` 冲突；Ga02 path fallback 不匹配 URI authority；Ga03 新 widget 路由步骤不完整；Ga04 紧凑尺寸只适用特定场景；Gb03 示例/路径需反映抽取后的 `FloatingWindowScreenshot.kt`；Gc01 sample string/HSL/像素计算/脚本处理不一致。 | 核对 Manifest、Gradle、MainActivity、Widget providers、FloatingWindowScreenshot 与 scripts；未 build/设备验证，minSdk effective value 待解析。 |
| H | 6/6 | 已核实历史 Ha01 `sampleCounter =` / `-=` 用法、MetronomeFFI/Service 所有权混淆；Ha05 WAV hot replace 与 C++ 回调存在竞争风险，文档不得称线程安全；Ha03 Clock/provider/I/O 和 idle shutdown 内容需更新；Ha02 ABI 和 R8/FFI advice需对齐项目 Gradle/C++。 | 核对 C++ callback、Dart service/controller/clock provider、Gradle 配置；不执行 Android build。 |

## 本轮已落实的文档修正（2026-10-20）

| 序列 | 修正 |
|---|---|
| A01 | 重写为 translator 真路径（`lib/app_lifecycle/fr_method_channel_translator.dart`）；删除“原始中文 URL 必崩”错误表述；区分 deep link 与局部 Navigator；检查命令改 rg 并指向唯一翻译器 |
| A03 | 重写为当前 Lab 源码入口表 + 三方登记（Demo registry / kGameMeta / kGameCenterCatalog）；移除“加游戏只改两处”的过时路标；阈值改为评估信号 |
| A04 | 主页骨架改为现状（无 featured/统计入口）；标注 featured 字段未消费；消费 grid 只含 registry 项 + 时间课表 |
| A06 | 删除 Rive 合并/Tab 容器示例与 Fb 链接；重命名为 `A06-Demo-Slug别名.md`；只保留 slug alias SOP（通用版） |
| Ba01 | 重写：入口清单以代码为准；确认态标注“演示态 vs 真实入口”；错误表补检查/修复/验证列；异常处理边界说明 |
| Ba02 | pi/Hive 入口补入矩阵；Format 标为已知 gap；SessionStore 标为目标契约非现存基类；“禁用 Hive TypeAdapter”改为按 D 序列；OCR 失败轮次边界明示 |
| C00 | device_id 注入段落改为当前实现（允许参数覆盖、客户端自报身份）；探针示例去除断言性引用；422/“200 但快照不变”拆成两行排查；迁移矩阵链接改 Ca/Cb/Cc |
| Ca03 | 权限示例表 WIN 改 `non_current_player`；role_check/canPerform 标注 fail-open 现状；删重复 host 行 |
| Cb01 | 新游戏 checklist 改为 `GameLobbyPage`+`GameLobbySpec` 优先，旧 LobbyEntryPage 标历史；deviceId 前缀反模式改服务端权威字段 |
| Cc01 | 头部加“当前实现对照”：setup/OPEN/lobby/START、无 ACK 门、spectator_slots=0=不限量、assignments 共享 context 无协议保密 |
| D02 | 明确 StorageManager legacy fallback 与导入/导出是存储基础设施例外边界，新 feature 不得新增直连 |
| Ea07 | analyzer 管道加 pipefail/退出码警示 |
| Ea12 | try/finally 守卫边界警示（try 前 await 失败不触发 finally） |
| Ea13/Ea14 | 内部 C00/C01 标签改 Ea13/Ea14；Ea14 补 sudokuColors 通道及其 extension 未注入 caveat |
| Eb02/Eb03 | 补 Sudoku 通道现状 caveat；`torchProtect.protectPresets` API、context 路径、Eb04 引用修正 |
| Eb05 | `pieceColors[t]!` 改为运行时非编译期保证；token 路径改 `lib/design_tokens/color/`；特例注释语义收窄 |
| Fa02 | 去 dup 行；chess `.webp`→`.png`（当前脚本实况）；gomoku board 改必选；chess board 历史说明；404/超时行按脚本与 `GameSkinLocalizer` 15s 修正；后端 controller 标待服务端来源 |
| Fa03/Fa04 | GameSkinLocalizer/15s、line_cache 根目录、emoji 统一 `emojis/common/` 缓存、混形态静默丢数据、扩展名/重复行为修正 |
| Ga01 | minSdk≥24 改为“确认 effective minSdk/加 SDK 分支” |
| Ga02/Ga03/Ga04/Gc01 | path fallback 修正（authority 不在 path）；Ga03 快捷步骤限定既有路由；Ga04 40dp/横收缩限定 1×1 widget；Gc01 RGBA 样例、40%≈409px 修正 |
| Gb03 | 文件地图指向抽取后的 `FloatingWindowScreenshot.kt`；示例标模式示意/历史；旋转策略注明未实现 |
| Ha01 | C 导出名改 `play_metronome/pause_metronome`；sampleCounter 指引改 `-=` 保留余数并链 Ha04 |
| Ha02 | ABI 加本项目“禁手加 abiFilters/CI 拆包”约束；R8 与 Dart FFI 无关的排障方向 |
| Ha03 | Clock Provider 全局注册/前台 timer/恢复语义修正；Metronome“单例常驻、流按需 30s idle shutdown”语义对齐 |
| Ha05 | 并发竞态警示（不得宣称热替换安全）；`gSamples`→`gSlots` |
| SKILL.md | F 序列描述去 Rive；A06 名称同步；维护规则 F00 只维护 Fa |

| A07 | Notion 示例补 `+08:00`（对齐 page_endpoint.dart）；测试入库口径统一；notion-cli 来源句改历史决策；401 断言边界改 mock-client 方案；Rule0 例外区记录 room/services 直连 http 遗留 |
| Ca01 | `myId.startsWith('sg-host-')` 前缀推导改为服务端 `snap.hostId == myId` 权威字段 |
| Ca02 | 行号引用改符号引用（const_game_center.dart 的 GameCategory） |
| Cb02 | 字符集声明对齐 `RoomCodeRules.validate` 现状（长度/易混字符）；房间满补具体用户动作 |
| Cb03 | §4.5 标记为斗兽棋专属历史样例，坐标镜像/180° 旋转不通用 |
| Cb04 | moveConfirmed/clearSelection 生命周期按当前控制器修正（点击停留 vs 拖动 reset 不对称） |
| Ea04 | “80px 硬限幅”改为衰减目标语义（BoundedBouncingScrollPhysics 因子渐近 0.02） |
| Ea08/Ea09 | border-emphasis 旧 A01 引用改 Ea03 |
| Ea11 | 就绪 CTA 加共享 `GameReadyCtaStyle` 现行对照 |
| Eb04 | 224/301 两处残留计数标快照时点与重测指引；zen_theme 路径改 `lib/core/ui/zen/` |
| SKILL.md | 维护规则“F00 维护 Fa/Fb”改“F00 维护 Fa” |

## 迁移式文档移除（2026-10-20，用户指令）

标准 A–H SOP 序列文档已就位且用户确认后续不再迁移，`references/UNMAPPED-REVIEW.md` 已删除；各 ref 中指向它的链接同步清理。未归序的旧材料（workflow B01–B05/C01–C04、note/、debuglog/、已删除的 dev-git-flow 与 netp2p）只保留在 `.claude/skills-archive/` 归档与 Git 历史中，不再纳入活动 skill，也不再作为指导依据。

## 错误代码/异常指导标准

需逐项核实 Fa02 的 HTTP 401/404 与匿名 KV 404、C00/Cb02 Relay statuses、D01 Hive/runtime failures、Gb02 Android exceptions、Ha02 native/build errors。用户操作必须具有真实的检查与修复动作；服务器端未证的状态码标为 `NEEDS_SOURCE/LIVE_TEST`，不得写“已验证”。

## 未解决的源码级 follow-up（本轮不修改应用代码）

| 优先级 | 位置 | 已核实行为/问题 | 处理边界 |
|---|---|---|---|
| P1 | `lib/services/message_strategy/strategies/selection_message_strategy.dart` | 选择消息取消回调只清 `_selectedIds`，没有 setState，旧选中视觉可能残留至后续 rebuild。 | 文档可提示/链接错误，但修复是 UI 行为；需单独代码修复与 widget test。 |
| P1 | `lib/core/net_engine/relay_v3/relay_v3_transport.dart` | applyAction 注入 device_id 的 spread 次序允许调用参数覆盖身份；C refs 应警示。 | 影响权限/身份边界，不能只格式化；作为独立安全/正确性 follow-up。 |
| P1 | `android/app/src/main/cpp/metronome.cpp` | WAV slot 更新/释放与 callback 并发存在竞态；Ha05 不应宣称 hot replacement 安全。 | 文档先收窄；若需要运行中更换音色，应单独设计同步所有权并测试。 |
| P2 | `lib/core/ai_chat/receipt_ocr/receipt_ocr_page.dart` | OCR 成功才持久化历史；失败轮次仍只在内存。 | 更新 Ba02 的适用范围/已知 gap；是否变更产品持久化行为另行决策。 |
| P2 | `lib/core/ai_chat/receipt_ocr/` | 真实 `MessagePanelController` 存在内存路径；Ba02 的 generic session-store 先定义为新模块要求，不冒充现存通用 API。 | 修正文档契约语气。 |

> 本报告记录已审计发现，不表示未列 ref 已获得逐句合规判定；具体内容更正仍按审计 finding 与代码证据执行。本轮不对应用行为做变更。

---

## 质检 2026-10-23

> 本轮范围：FR **组件复用与组件化**（共享组件层实况 + E 序列文档与代码一致性）。
> 全量证据：`docs/architecture/component-reuse-audit.md`（本轮新增，508 行，含 file:line 证据、28 条收敛项与 8 项待裁决问题）。
> 本轮**未修改应用代码**；源码级问题只登记 follow-up。文档修正集中在 E 序列。

### 审计基线

- 活动 references 文件数：**68**（上轮记 65；本轮新增 Ec01/Ec02 两个 ref，上轮基线数字已失效）。
- 覆盖范围：A 9，B 3，C 9，D 4，**E 22**（E00 + Ea01–Ea14 + Eb01–Eb05 + Ec01–Ec02），F 5，G 9，H 6。本轮只审 E 序列，其余序列未审。
- 组件资产盘点范围：`lib/core/ui/**`（28 文件）、`lib/core/game_kit/**`、`lib/core/*/p2p/**`（12137 行）、`lib/lab/demos/**`（206 文件 / 57114 行）、`lib/design_tokens/**`、`lib/core/*/lobby/**`。
- 组件层采用率基线：全仓 983 个 dart 文件中仅 **62 个（6.3%）**引用 `lib/core/ui/*`；`lib/core`+`lib/screens` 合计 **24 个**；`lib/lab/demos` 独占 **29 个**。
- 证据边界：本轮只运行 `flutter analyze lib/core/ui`（15 issues，0 error，全为既有 `unused_import` 与 deprecated API）；**未运行 `flutter test` / `flutter build` / 设备验证**；未修改任何 `.dart` 文件。

### 逐序列审计记录（2026-10-23）

| 序列 | refs 覆盖 | 结果/本轮更正 | 证据边界 |
|---|---:|---|---|
| E | 22/22 | 新增 Ec 子序列（Ec01 组件分层与复用契约 / Ec02 组件现状与收敛路线）；修正 Ea03/Ea04/Ea05/Ea06/Ea08/Ea09/Ea10/Ea11/Ea12/Ea14/Eb02/Eb03/Eb04/Eb05 共 14 个 ref 的过期陈述；E00 补 Ec 路由与「复用优先于新建」红线；SKILL.md 补第 9 条约束与 Ec 扁平子序列说明 | 逐条比对当前源码（`lib/core/ui`、`lib/core/game_kit`、`lib/core/theme`、`lib/screens/profile/lab`、`lib/lab/demos`）；未运行 UI 测试；两个 subagent 报告的数字经本人复跑校正（chessColors 消费文件实为 9 个，非 5/8） |
| A–D / F–H | — | 本轮未审（沿用 2026-10-20 记录） | — |

### 本轮已落实的文档修正（2026-10-23）

| ref | 修正 |
|---|---|
| E00 | 新增 Ec 子序列路由段（扁平子序列说明 + 覆盖范围界定：Ea 管视觉模式、Eb 管颜色通道、组件资产分层归 Ec）；全局红线新增「复用优先于新建」条；frontmatter description 补组件复用 |
| SKILL.md | 序列路由 E 行「何时读取」补「或做组件复用/组件化决策时」；FR 开发约束速记新增第 9 条「组件复用」；维护规则补 `Ec01-...md` 文件名示例与「Ec 为扁平子序列，成员由 E00 直接登记」；frontmatter description 补「组件复用与组件分层决策」 |
| Ec01（新增） | 组件分层契约（L1 token → L6 业务装配）与依赖方向硬约束；复用判定顺序（查清单 → 查漏用 → 查分叉 → 才新建 → 下沉或留原地）；新建组件的命名/参数化/结构/健康度契约；review 验收清单 10 条；Top5 反模式；与 Ea/Eb 的分工边界 |
| Ec02（新增） | 组件现状清单（7 个 atomic 的采用率与处置、L5 域内件清单、11 类缺失件与预计净减行数）；三大热点（漏用 / 视觉分叉 / 联机层未收敛）；S1–S4 分阶段收敛路线；与 `plan/game-kit-unification.md` Phase 4 的衔接与「存量不强迁」修订建议；重跑命令集 |
| Ea03 | 补 frontmatter；新增「已有共享实现」段（`EmphasisButton` 三档语义、84 处调用、圆角取自 `cardTheme.shape`）；把手写 `_outlinedBtnStyle` 模板降为反模式并要求改用共享件；错误案例新增「手写 helper 与 EmphasisButton 分叉」 |
| Ea04 | 「80px 硬限幅」改「衰减目标」语义（`bounded_bouncing_scroll_physics.dart:45-48` 渐近 factor，永不触到 80） |
| Ea05 | 底栏参数全部改为 `quick_nav_bottom_bar.dart` 真值（外壳高 64 / barBottomGap 16 / 胶囊高 48 / 380ms / 内边距 28 / 胶囊宽 clamp(56,88) / primary@0.14 / 未选中 0.42 / 曲线 `1-exp(-5.2t)cos(7.5t)`）；「禁止用 LayoutBuilder 取实际宽度」反转；删除全仓不存在的 `XiaoDouZiBottomBar` 与 k/ω 描述；legacy 段改为现状（`Cubic(0.65,0,0.35,1)`、几何 52/68）；曲线类名 `_QQCurve` → `_IosSpringCurve` |
| Ea06 | Step 4 重写为「搜索框即头（H3R-C）+ 滚动后毛玻璃细条」；Step 3「顶部横向精选」改「我的收藏」；四层封面改三层（压暗蒙版整层 2026-09-22 已移除）；坑 1–4 按新设计重写 |
| Ea08 | 去旧编号「A06」；「A01 描边减负」改 `[[Ea03-边框强调式减负]]`；补 `surfaceTintColor: Colors.transparent` 12 处手抄（10 处在 remotetype）与 `ZenFloatCard` 建议；补 frontmatter |
| Ea09 | 去旧编号「A07」；「实心滑动分段」标注**无生产落点**（remotetype 下 `AnimatedPositioned` 0 命中）；补托盘配方落地位置 `rt_shortcut_bar.dart:51-56` 与 `RecessedTray` 建议；坑表 A01 → Ea03；补 frontmatter |
| Ea10 | 去旧编号「A08」；判决表新增「当前实现」列（房内就绪 CTA = `StadiumBorder` 全胶囊，`game_ready_style.dart:190,200`）；原「房内方圆角 12」降为未落地建议并加更正提示；大厅主 CTA 色改 `primary`（`_lobby_form.dart:245` 注释「禁止 tertiary 反色抢戏」）；补圆角 token 错位告警（10/11/14/18/20/22/28 均不在 `AppRadius` 档位）与抽 `AppShapeExtension` 的前置条件 |
| Ea11 | 去旧编号「A09」；新增「已有共享实现」段（`GameReady*` 六件套行号、core 4 页全用 vs 7 个 demo 手写、房间号胶囊实测分叉：core 走 `primaryContainer`/字号 22/字距 6/无边框，demo 走 `theme.btnText`/字号 24/字距 8/带边框）；房间就绪卡规格改为代码真值；匹配笔刷转场标注**已下线**（`GameEnterTransition` 已移除，commit `bb3e94dc`）；踩坑表补「demo 侧用皮肤色」「按文档改房内 CTA」两条 |
| Ea12 | 行号改正（`:1046` `_loadingCache` / `:1080-1104` try-catch-finally / `:1204-1220` `_pickDatabase`）；新增 caveat：`SharedPreferences.getInstance()` 的 await 在 try 之外（`:1085`），异常时 `_loadingCache` 卡死 true；补 frontmatter |
| Ea14 | `context.torchProtect` 改「扩展已注册（`app_theme.dart:156`）但无 context 入口」（`lib/core/theme/context/` 无该文件、`get torchProtect` 0 命中）；补 frontmatter |
| Eb02 | 源码地图与消费链移除 `torchProtect` 通道并补 caveat；文末新增「本文章节结构」节，标注 `Eb02 §5.8 / §6 / §6.2 / §6.3 / §6.4` 是过期断链及其正确去处（Eb04 §7 / §6.5）；补 frontmatter |
| Eb03 | §0/§3 的组件样式落点由 `lib/core/ui/zen/zen_theme.dart` 改为 `lib/core/ui/`（通用件）/ `lib/core/game_kit/`（域内壳层），指向 `[[Ec01-组件分层与复用契约]]`；修正指向不存在 Eb02 章节的引用（→ Eb04 §6.5 / §7）；补 frontmatter |
| Eb04 | 文件头加「本文数字为快照，以 §5 命令为准」；§1 目录表按实跑重写；§2 使用点数改正（chessColors 0→**9 个文件**、boardColors 2→4 个文件、tetrisColors 4→3 处）；§3 Top20 按实跑重排；§4 残留 `Color(0xFF` 224→**664**（排除 `lib/core/theme/`）、tetris 改单文件并按目录重写归属表；§5 补可复跑命令；§6.5 三处断链改正；§8 路径改 `lib/design_tokens/radius.dart`；补 frontmatter |
| Eb05 | §1.2 tetris token 代码块按 `lib/design_tokens/color/tetris.dart:12-34` 重写（真实是 **3 个颜色角色 + 1 个 7 色 Map**，旧文写的「4 角色 / slate-900 / cyan-400」全错）；「4 角色」表述全改；补 frontmatter |

### 未解决的源码级 follow-up（2026-10-23，本轮不修改应用代码）

| 优先级 | 位置 | 已核实行为/问题 | 处理边界 |
|---|---|---|---|
| P0 | `lib/lab/demos/*_lua/widgets.dart`（7 处） | 手写就绪卡 / 房间码胶囊 / 就绪徽章 / `_ReadyAvatar`，与 core 的 `GameReady*` 分叉：色源（皮肤色 vs `colorScheme`）、字号（24 vs 22）、字距（8 vs 6）、有无边框均不同 | 改 demo 调用点即可，不动 `game_ready_style.dart`（除非决定加 BoardTheme 变体） |
| P0 | `lib/core/ui/atomic/base_dialog.dart:20-21` | `BaseConfirmDialog` 默认 `confirmLabel='Delete'` / `cancelLabel='Cancel'` 为英文；7 个调用点无一传 `cancelLabel` | 推广到 29 处确认弹窗前必须先参数化并本地化；属代码改动 |
| P1 | `lib/core/ui/atomic/base_{dialog,dot,empty_state,icon_button,swipe_action}.dart` | 5 处自引用 import；`flutter analyze lib/core/ui` 的全部 warning 由此产生 | 删 import 即可，零风险，可独立提交 |
| P1 | `lib/core/ui/atomic/base_button.dart` | 零业务引用；`_LocalOverrideStrategy.surface` 为死字段；`icon` / `fullWidth` 在唯一调用点未使用；与 `zenButtonTheme` 的 `styleFrom` 逐项相同 | 先裁决去留（删除 or 补齐采用），再谈其它按钮治理 |
| P1 | `lib/core/ui/renderers/image_picker_widget.dart` | 10 条 analyze info：4 处 `withOpacity`、4 处 `MaterialStatePropertyAll`、2 处 `use_build_context_synchronously` | 纯 API 迁移，可独立提交；文件 555 行可另行拆分 |
| P1 | `lib/core/ui/shell/app_notification.dart:244-299` | 33 处 hex；根因是 `lib/core/theme/context/` 缺 `app_colors.dart` 访问器（`AppColorsExtension` 已有 13 个语义角色并按主题注入） | 需先补约 20 行访问器，再决定是否吃 `AppColorsExtension`（属产品取舍） |
| P1 | `lib/lab/demos/{coup,cowrite,go,gomoku,jungle_chess,reversi,surround_game,team_card,tetris}_lua/*_script.dart`（9 个） | 未接 `assembleLuaScript` 与聊天/表情共享段（CHAT/EMOJI 计数均为 0），这 9 个游戏**收不到聊天与表情** | 功能补齐；需逐脚本回归 export 表与 `definition.functions` |
| P2 | `lib/core/surround_game/board_theme.dart:43` | `BoardThemeData` 定义在游戏模块内却被 21 个文件跨游戏消费；`reversi/board_theme.dart` 另起一套平行令牌 | 需先定归属（审计报告 §9 问题 7）；`plan/game-kit-unification.md` Conventions 早已明令消灭此模式 |
| P2 | `lib/core/timetable/service/config/advanced/shared/zen_controls.dart:11,160` 与 `timetable_settings_page.dart:391,431` | `ZenSegmentButton` / `ZenActionButton` 与私有 `_Zen*` 逐行等价 | 归一到一份（下沉只做了一半） |
| P2 | `lib/core/ui/global_ring/const_global_ring.dart:26,51` | 注释指向已删文件 `lib/core/ui/xiaodouzi_bottom_bar.dart`；且声称与底栏曲线同公式，实际 `1-exp(-4.5t)cos(9.425t)` vs `1-exp(-5.2t)cos(7.5t)` 不同 | 注释修正即可 |
| P2 | `lib/core/theme/context/` | 缺 `torch_protect_colors.dart` 与 `app_colors.dart` 两个消费入口；前者导致 Ea14/Eb02 反复引用不存在的 API，后者导致通知组件硬编码 hex | 补文件或改文档，二选一 |
| P2 | `lib/core/novel_reader/novel_reader_page.dart:765,807,825` | 浅色常量（`0xFFEEE6D8` / `0xFFF8F1E6` / `0xFFE4D5C0`）直接作页面底，dark theme 下出现亮色块 | 需 ThemeExtension 承载位；豁免本身合理，改承载方式 |
| P2 | `lib/lab/demos/tetris_lua/widgets.dart` | 唯独未用 `RelayConnectionBar`，自建 disconnect 处理（`:150` 自行订阅 `closeEvents`、`:244` 自行 `rejoin()`、`:439` 自绘重连 SnackBar） | 属壳层不统一导致的行为差异，与其余 6 个 demo 不一致 |

### 本轮新增的非 ref 产出

| 文件 | 说明 |
|---|---|
| `docs/architecture/component-reuse-audit.md` | 组件复用与组件化审计全量证据：结论摘要、组件层清单与采用率、漏用清单、缺失件清单、联机层同构分析、demo 层重复分析、主题通道断层、超大文件拆分、28 条收敛项、8 项待裁决问题、重跑命令 |

### S1 采纳批落地记录（2026-10-23，同日第二轮）

> 用户在审计交付后选择「S1 采纳批」落地。改了应用代码；逐 Phase 验证。

| Phase | 改动 | 验证 |
|---|---|---|
| A · GameReady 采纳 | 6 个 lua 对局页换用 `GameReady*` 六件套、删 6 份 `_ReadyAvatar`；`coup`（6 人局）按计划保留；净减约 750 行 | 各目录 `flutter analyze` 0 issue |
| B · 确认弹窗 | `base_dialog.dart` 默认文案改中文「确认/取消」、`onConfirm` 改可选、删自引用 import；收编 19 处 / 16 文件 | `flutter analyze lib/core lib/screens` 0 新增 |
| C · SnackBar | 收编 144 处 / 31 文件到 `AppNotification`（按 success/warning/error/info 语义分型）；残留 13 处全部为带 `SnackBarAction` 或 `lib/core/ui` 自身 | 同上；带 action 项在册保留 |
| D · 空态 | `base_empty_state.dart` 扩展 `title`/`message?`/`iconSize` 并删自引用 import；收编 10 处；`pi_chat_page._EmptyChatView`（交互式 starter）与 `rt_pairing_view`（表单内嵌提示）有意保留 | 同上 |
| 附带 | `base_dot` / `base_icon_button` / `base_swipe_action` 的自引用 import 一并清除；`flutter analyze lib/core/ui/atomic` 归零 | `flutter analyze lib/core/ui/atomic` → No issues |

**测试结果**：全量 `flutter test` = +1252 通过 / ~3 跳过 / **-10 失败，与改动前基线一致**。本轮新增 2 个失败（`xiangqi_ready_gate_test` 认输二次确认、`chess_game_record_list_page_test` 删除确认），原因是测试 finder 找 `FilledButton` 而收编后确认按钮为 `TextButton`——已把两处 finder 改为 `find.widgetWithText(TextButton, …)` 并复跑通过（21/21）。剩余 -10 均为既有失败：notion ×7（setUpAll 需真实令牌）、`line/judge_service_test` ×2（判定窗口阈值与测试预期漂移，纯逻辑，S1 未触碰 line 逻辑）、`relay_v3_integration_test` ×1（需真实服务端）。

**行为语义保留说明**：确认弹窗收编后「先关窗再执行动作」的时序与原实现一致；带撤销窗的删除（`pi_session_list_page`）完整保留 SnackBar+action 原样。

### 导航组件抽离（2026-10-24，用户指令）

按用户要求「远控设置页 nav 作为普通导航规范，其他特殊样式 nav 作为不同样式变体」落地：

| 动作 | 结果 |
|---|---|
| 新组件 | `lib/core/ui/shell/app_nav_bar.dart` —— `AppNavBar` 三样式：`standard`（AppBar 规范，样板 = RtSettingsPage；`transparent`/`centerTitle` 变体）、`floating`（全出血浮层行：`backStyle: solid/plain`、`title` 插槽、`centerTitleSlot`、`leading` 覆盖、`floatingActions`）、`pill`（浮卡胶囊条：豁免色走显式参数）。配套 `BaseIconButton` 补 `tooltip` |
| 迁移 8 处 | RtSettingsPage（standard 样板）、rt_page `_sharedHeader`（floating + 玻璃钮走 leading 插槽）、line game_page/game_result/song_select/line_settings（floating plain）、focus_timer 头部（floating + centerTitleSlot）、novel_reader `_ReaderTopBar` 类删除改 pill（纸质豁免色留调用点）、word_detail（standard transparent+centerTitle） |
| 不迁移（判定） | surround/jungle local 的「返回」在**底部操作行**（操作按钮非导航）；team_card / gomoku_opening / snake 属 lab demos（业务面之外）；app_settings `_Header` 是内容头部非页头导航 |
| 验证 | 迁移目录 `flutter analyze` 0 error / 0 warning（全 lib 的 3 error 为 `rt_canvas_dpad.dart`——**另一会话的用户 WIP**，八向轮盘改造中断态，不属于本轮）；line/novel/focus/nav 测试 29 过 / 2 败（均为基线既有 judge 阈值漂移） |
| 文档 | Ec03 目录树与找组件速查、Ec02 缺失件表（BaseTopBar → AppNavBar 已落地）+「导航抽离记录」节 |

### UI 三篇重构（2026-10-24，用户指令）

按用户要求把 UI 知识收敛为「主题系统 / token 字典 / 组件位置」三篇：

| 动作 | 结果 |
|---|---|
| 合并 | 旧 `Eb01-主题架构路由`（25 行纯路由）+ `Eb02-系统架构与数据流`（83 行）→ 新 **`Eb01-主题系统简述`**（7 套主题表 + 分层链路 + 取色通道速查 + 切换数据流 + Eb 路由 + 红线；torchProtect/AppColorsExtension 无 context 入口的 caveat 保留） |
| 新增 | **`Eb06-token变量定义`**：几何（AppRadius 6 档 / AppSpacing 7 档）、字体（AppFontFamily/Weight）、颜色（7 palettes、ColorScheme、AppColorsExtension 12 角色、ColorStrategy 6 角色、6 个域内 strategy 规模）、消费判定与「要不要进 token」判据——全部数值经源码核实（含 tetris 七色 hex、torch 4 角色） |
| 新增 | **`Ec03-组件内聚位置`**：`lib/core/ui/` 七个子目录实况树（含 game/ 8 件）、周边层次位置表、新组件三问速查、现存错位清单（RtRoundIconButton / RtConnDot / ios_dialog / BoardThemeData 等 6 项）、找组件速查 |
| 登记 | E00 的 Eb/Ec 路由表更新；Ea13/Ea14 的旧 Eb01 名称改链；活动 refs 总数 68 → **69**（-2 合并 +3 新增，E 序列 22 → 23） |
| 验证 | 全部 `[[…]]` 链接与文件名一一对应（仅 Gc01 两处既有 `[[0, -1]]` 矩阵记法误报） |
# 质检 2026-10-24（第二轮全量复检）

## 审计基线

- 活动范围：`references/` 66 份 ref（A 10 / B 3 / C 9 / D 4 / E 20 / F 5 / G 9 / H 6）+ `SKILL.md` + `scripts/` 6 个脚本；自上轮（2026-10-20）后仓库新增 40+ 提交（remotetype 迁入 `lib/core` 并分层 data/protocol/ui/canvas、A09 新增、设置页/布局系统大改、全局导航栏紧凑化等）。
- **方法变更**：本轮计划的 9 个序列 subagent 因 API 额度不足（insufficient credits）全部未产出 → 改为主线程机械化四层扫描 + 重点重测：
  1. 链接层：66 份 ref 全部 `[[锚点]]` 与文件名一一比对（**全部可解析**，8 个 `00` 路由成员表覆盖所有成员，无孤儿 ref）；
  2. 路径层：提取 ref 中全部 `lib/ android/ test/ scripts/ res/ docs/` 路径 248 条逐一存在性比对（git ls-files + 实盘目录）；
  3. 行号层：提取 `文件:行号` 引用 15 处逐条与当前文件行号比对；
  4. 符号层：提取反引号内 PascalCase/类符号 301 个回源码 rg 比对（剔除 Flutter/Android 框架符号与序列代号误报后人工复核）。
- 重点深测：Eb04（颜色审计快照全部重算）、Ea05（生产底栏参数）、Cb01/Cb02（房间模板提案名、易混字符）。
- 证据边界：纯文档轮，未运行 `flutter test` / `build`；C/F 序列服务端合同仍标 `待服务端来源 / NEEDS_SOURCE`；上轮 P1/P2 follow-up 本轮抽查确认全部仍在原状。

## 逐序列审计记录

| 序列 | 抽查/扫描 | 结果 |
|---|---|---|
| A | 路径/行号/符号全扫 + A01 translator、A04 kTimePageMeta/featured、A05 kGameMeta/kGameCenterCatalog、A09 全部 15 处 `文件:行号` 逐条核验 | **A09 行号全部命中当前代码**（nav_catalog 49/91/116/141/150/152、pins 15/21/45–59/76/103–147、main_screen 39/47/254/261/267/276/287/313）；A01 translator 真路径、`=> 'fr://` 检查命令可跑通；A04 featured 仍仅声明未消费（文档如实）；A05 符号全部存在。未发现需改写项。 |
| B | Ba01 selection setState、Ba02 pi/Hive 入口抽查 | 与上轮结论一致：Ba01 的取消回调只 `clear()` 不 setState 仍在（`selection_message_strategy.dart:114`），维持 follow-up 不改码；Ba02 的 OCR 持久化 gap 表述仍准确。 |
| C | Cb01 提案组件名、Cb02 房间号、applyAction 身份注入抽查 | Cb01 §7 的 `RoomLobbyView`/`RoomFinishedOverlay`/`RoomBottomActionBar`/`VersusRoomShell`/`LobbyEntryPage` 在仓库**不存在同名类**（现行 `GameLobbyPage`+`GameLobbySpec`），已加警示注；Cb02 补「易混字符不拦截」产品决定（见下）；`applyAction` 的 `device_id` 可被 `params` 覆盖（`relay_v3_transport.dart:477` spread 次序）仍在，维持 follow-up。 |
| D | BoxDescriptor/StorageRegistry/HiveStore.openTyped/room 签名核验 | 与当前源码一致（`openTyped(name, {required adapter, int? typeId})`、`StorageRegistry.register` 幂等覆盖、D02 的 StorageManager 例外边界表述准确）。无需修正。 |
| E | **Eb04 全量重算** + Ea 子序列逐份结构检查 | Eb04 快照漂移最重：`chessColors` 消费点 0→**9 文件**、`colors` 通道 57→**82 文件**且重心 lab→core、热点 Top20 大换血、残留计数口径失效——已全部按 2026-10-23/24 实测回填；Ea08–Ea11 的 H1 还挂着旧编号 A06–A09、三处把 Ea03 写成「A01 描边」；Ea09 落地路径/现状过时（发送/换行已移设置页）；Ea13 自称「子序列元数据」且缺 3 个新原型的映射；Ea05 生产参数与代码不符（胶囊高 50→48、宽固定 90→动态 56–88、primary 20%→14%）。均已修。 |
| F | 脚本 CLI 签名逐一比对 argparse | Fa02/Fa04/Gc01 示例命令与 `add_skin.py`/`add_emoji_pack.py`/`retag_existing.py`/`migrate_line_from_supabase.py` 实际参数**全部一致**；Gc01 的 scripts 相对路径已补全为 skill 全路径。 |
| G | Manifest 行号、widget 资源路径、minSdk | Ga01 `AndroidManifest.xml:180-190`（时钟 receiver + APPWIDGET_UPDATE）命中；minSdk=`flutter.minSdkVersion` 与 Ga01「确认 effective 值」口径一致；Ga03/Ga04 的 `res/...` 短路径补全为 `android/app/src/main/res/...`。 |
| H | metronome 导出名、gSlots、Ha01 反例 | `play_metronome/pause_metronome`（.h/.cpp/FFI binding 三处一致）、`gSlots` 命名与 Ha05 警示表述仍准确。无需修正。 |

## 本轮已落实的文档修正（2026-10-24）

| 文件 | 修正 |
|---|---|
| Eb04 | 头部加快照时点声明；§0 残留分类表改 2026-10-23 实测口径（色板源 301 / S 90 / 特例 33 / 调用点残留 384，**明确旧「未分类 0」不可再引用**）；§1 表重测（core Theme.of 82→133）+ 加 sudoku 列；§2 通道消费点全量重列（chessColors 0→9 文件、colors 57→82、boardColors 2→4）+ 补 `context.sudokuColors` 一节（含未注入 caveat）；§3 Top20 重测重排 + 新旧对比注；§4 改「384 处调用点残留」新口径表 + **待归类 71 处**（chess 35 / xiangqi 30 / remotetype 6）显式标出；§5 自检命令修 `lib/widgets`（不存在）→ `lib/services`+`lib/core/ui`、grep→rg、补按目录拆分命令；§6.5 calendar 历史案例标注「demo 已重写为占位页、旧类已删」、word_drag/markdown/zen 三行路径修正；§7 BoardTheme 86→90；§8 标时点快照、player_strip 路径修正 |
| Ea05 | 开头视觉目标区分 legacy/生产两套几何；Step 3 加生产对照注（`_capsuleH=48`、`capsuleW=(itemW-8).clamp(56,88)`、primary@14%、不固定宽度） |
| Ea08/Ea09/Ea10/Ea11 | H1 旧编号 A06/A07/A08/A09 → Ea08/Ea09/Ea10/Ea11（与文件名对齐） |
| Ea08/Ea09/Ea10 | 「A01 描边减负」错指 → Ea03 |
| Ea09 | 落地参考路径补全（`lib/core/remotetype/ui/rt_shortcut_bar.dart`、`canvas/template/`）；加 2026-10 重构现状注记（发送/换行已移设置页「回车行为」，分段控件配方现役于设置页） |
| Ea13 | 去误标的「Ea 子序列元数据」（Ea01/Ea02 才是路由）；原型表补 `rt-canvas-gamepad` / `rt-canvas-layouts-manage` / `rt-settings-layouts-card` 三个新原型映射（指向 Ea09/Ea10/A09/Ea06）+ 标注当前原型文件数 10；补「原型增删先回本表补一行」纪律 |
| Ga03/Ga04 | `res/values/strings.xml`、`res/xml|layout|drawable/notion_widget*` 短路径 → `android/app/src/main/res/...` 全路径 |
| Gc01 | Bundled Scripts 相对路径 → `.claude/skills/fr-engineer-flowot/scripts/` 全路径 |
| Cb01 | §7 加警示注：5 个组件名是提案、仓库不存在，现行按 `GameLobbyPage`+`GameLobbySpec` |
| Cb02 | §2.1 服务端响应表加 `待服务端来源` 注；易混字符行改小写 l→大写 L 对齐客户端常量；**错误表 #3 改写为产品决定（2026-10-24）：客户端不拦截 0/O/1/I/L**，不做输入过滤与提交前校验，现行 `RoomCodeRules` 拦截已登记 follow-up |

## 未解决的源码级 follow-up（本轮不修改应用代码）

上轮 P1/P2 五项（selection setState / applyAction device_id / metronome WAV 竞态 / OCR 失败轮次 / SessionStore 契约）本轮抽查确认仍在，处理边界不变。本轮新增：

| 优先级 | 位置 | 已核实行为/问题 | 处理边界 |
|---|---|---|---|
| P2 → **已落地（2026-10-24）** | `lib/core/game_kit/lobby/game_lobby_spec.dart`（`RoomCodeRules.validate`） | 用户确认「不拦截」后已移除 `kConfusingChars` 字段与校验分支，validate 只校验长度；原先无测试覆盖，无需调整测试。 | 服务端对易混字符的真实行为仍未核实（待服务端来源；后端仓库 dev_ctr_hello 已登记进 nx-kv fr 看板，可去那核实）；`_lobby_form.dart` 的随机生成 pool 仍避开易混字符——生成偏好，非拦截。 |
| P3 | `lib/core/xiangqi/`（30）/ `lib/core/chess/`（35）/ `lib/core/remotetype/`（6） | 2026-10 新模块引入的裸 hex 尚未按 Eb04 的 S/E/特例口径逐项归类（本轮已测得数量并登记在 Eb04 §4「待归类」）。 | 下次颜色专项或迁移时按 Eb04 §5 命令逐文件定性回填；不阻塞功能开发。 |
| P3（模式级） | 22 份 ref 的错误案例表 | 表头 5 种变体（症状/错误/现象/错误操作/错误想法 × 检查/后果/排查/风险…），未统一为「症状→检查→修复→验证」四列；行数 4–14 不等，未严格执行 Top5。 | 下轮按 ref 逐份统一；优先 Fa02（12 行）/Ha01（14 行）/Ga02（10 行）三份最长的。 |

## 可代码化建议（本轮新提，均未落地）

1. **Eb04 §5 残留 hex 计数进 CI/本地门禁**：命令已是现成单行 rg，包一层 `scripts/color_hex_gate.py`（阈值 + 新增即红），可把「防止漂移」从人工纪律变成机器门禁。
2. **D03 新模块 Checklist 脚本化**：校验「BoxDescriptor 已注册 / TypeId 无冲突 / adapter 生成文件存在」三件事各是一条 rg/grep，收进 `scripts/hive_check.py`，新模块提交前跑一遍。
3. **Ga03 widget label 校验**：Manifest 每个 `<receiver>` 必有独立 label + strings.xml 键存在，可脚本化（当前靠 checklist 人查）。
4. **Ea 样式配方的组件化**：Ea09 实心分段、Ea10 CTA、Ea03 描边按钮仍是「配方文档」，每处使用靠人照抄；若再出现第 3 个使用点，建议沉淀为 `lib/core/ui/atomic/` 下的组件（`SolidSegmented` / `RoundedRectCta` / `BorderEmphasisButton`），skill 只留组件名 + 参数表——把同步成本从「读文档抄代码」降到「引用组件」。

## 操作教训

- subagent 派发前先确认 API 额度；失败时主线程「链接/路径/行号/符号」四层机械扫描能覆盖大部分漂移，人工深读留给重灾区（本轮 = Eb04/Ea05）。
- 行号引用（`文件:行号`）漂移最快但可机器校验，A09 式写法建议保留——下轮质检可直接复用本轮的比对方法。

> **rebase 注记（2026-10-24，与上节 10-23 质检的合并说明）**：本轮与远端并行的 10-23 组件复用质检改写了同一批 E 序列 ref。冲突按「远端为准」解决：Eb04 的通道/热点/残留计数以 10-23 版口径为准（**残留 664 处**，含分类表：xiangqi=S、remotetype=E、chess=E——本节下文 P3「待归类 71 处」一条已被该分类取代）；Ea05 / Ea08 / Ea09 / Ea10 / Ea11 取远端重写版（frontmatter + 行号真值，覆盖本节对应的 H1 编号与 A01→Ea03 修正）；Ea13 保留远端并补回本轮新增的 3 个原型映射行；ref 总数以 10-23 节的 **69** 为准（本节基线写 66 是冲突前快照）。本轮独有的存活增量：Cb01 提案名警示、Cb02「不拦截易混字符」产品决定、Ga03/Ga04/Gc01 路径补全、可代码化建议与操作教训。
