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
