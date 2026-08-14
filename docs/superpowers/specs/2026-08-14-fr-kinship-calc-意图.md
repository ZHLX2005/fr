# fr 任务意图文档（taskget 领取 · 2026-08-14 · 通用关系计算器 + 亲戚关系预设）

> 来源：kvcli todo `fr` topic，1 条 open（#20）。
> 决策点 1（2026-08-14）：方向=正向链式、范围=常用直系+主要旁系、交互=关系词点按链条。
> 决策点 2（2026-08-14，用户澄清）：**底层必须是通用计算模型（变量系统），亲戚关系只是预设** —— 支持高度自定义 CRUD、无限嵌套。
> 决策点 3（2026-08-14，用户澄清）：**支持其他关系领域**（如公司团队里自定义等级称呼关系、链式传递）；**存储不用 Hive，用简单存储（SharedPreferences）**。
> 前置 skill：flutter-work-flow（本仓库 `.claude/skills/flutter-work-flow`）。

## 任务总览

| 簇 | 主题 | 任务 | 模块 |
|---|---|---|---|
| A | 通用关系计算器（变量系统）+ 内置预设 | #20 | `lib/core/relation_calc/` + `lib/lab/demos/relation_calc/` |

## 用户拍板（2026-08-14）

| 决策点 | 结论 |
|---|---|
| 底层模型 | **通用关系计算模型（变量系统）**：`A 的 B = C` 三元组规则；`C 的 D = E` 继续运算 → 无限嵌套、链式传递 |
| 自定义能力 | **高度自定义 + 完整 CRUD**：实体（A/C/E）、关系词（B/D）、规则（A的B=C）均可增删改查 |
| 领域通用 | 引擎**不感知领域**：亲戚关系只是内置预设；支持任意自定义领域（公司团队等级称呼、宠物、组织…）链式传递 |
| 预设定位 | 亲戚关系计算器**本质上只是一个预设数据集**，底层与自定义数据共用**同一套计算引擎** |
| 存储 | **不用 Hive**；用 SharedPreferences 简单存储（JSON 序列化，参照 team_card 预设 / web_bookmark 先例） |
| 计算方向 | 正向链式叠加（从起点实体开始连续点按关系词，实时更新结果） |
| 关系范围 | 预设内置：常用直系 + 主要旁系（约 50-80 个称谓） |
| 交互形态 | 关系词点按链条（中央结果 + 关系词按钮 + 撤销/清空） |

## 原任务文本

> 亲戚关系计算器，实现各个方向的计算器，不断的加法操作，然后计算计算，实现一个专业的美观的，极度具有设计感的产品，边框强调，zen主题

## 架构（用户澄清后）

### 核心：通用关系计算引擎（变量系统模型）

```
数据模型（图结构）：
  实体 Entity      — 节点，如「我」「爸爸」「爷爷」「组长」；id + 名称 + 可选描述
  关系词 Term      — 有向边的标签，如「爸爸」「妈妈」「上级」；id + 名称
  规则 Rule        — 有向边：EntityA + Term → EntityB  （A 的 B = C）

运算（链式/嵌套，无限传递）：
  起点 A0 + term t1 → A1；A1 + t2 → A2；A2 + t3 → A3 …  无限嵌套
  每一步是图的边查找；中间结果即「变量」，可继续参与运算
  无匹配边 → 该步无法计算，提示用户（可撤销）
```

- 计算引擎**不感知领域**：亲戚、公司团队等级称呼、宠物、组织、游戏…任何「X 的 Y = Z」关系都能算
- 预设 = 一组预置的 Entity + Term + Rule 数据集（内置，可重置/加载）

### CRUD 与存储

- 实体管理：新增/编辑/删除实体
- 关系词管理：新增/编辑/删除关系词
- 规则管理：新增/编辑/删除规则（选择 A + 选择 B + 选择 C）
- 持久化：**SharedPreferences**（整库 JSON 字符串一次读写；参照 team_card `kTeamCardPresetsKey` 存 JSON 先例），不引 Hive
- 预设：内置亲戚关系数据（首次进入自动导入；提供重置回预设）

### UI（zen 主题 + 边框强调 + 设计感）

1. **计算主界面**：起点实体（默认「我」）+ 关系词按钮盘 + 中央实时结果（当前称谓）+ 关系链展示 + 撤销/清空
2. **管理界面**：三个 Tab（实体 / 关系词 / 规则）CRUD
3. **预设入口**：加载亲戚关系预设 / 查看预设说明 / 重置

## 项目上下文摘要（已实地调研）

- **zen 主题体系**：`lib/widgets/theme/zen_theme.dart`
  - `ZenColors`：bg `#F4F1EA` / ink `#2C2C2C` / hair `#D9D5C8` / secondary `#8A8475` / sage `#7A9A7E` / mutedRed `#A0594A` / surface `#FBF8F1`
  - 组件：`zenCard()`（hair 边框 1px + 圆角 6）、`zenButton(foreground:, border:)`、`ZenSection`、`ZenIconButton`（tint/outline/hero）、`ZenDot`、`ZenEmptyState`、`zenPageScaffold(title:, body:, fab:)`、`ZenConfirmDialog`
  - **边框强调现成通道**：`zenButton(border:)` 描边体系；`lib/core/design/emphasis_button.dart` 的 `EmphasisButton.borderEmphasis()`
- **demo 注册机制**：继承 `DemoPage`（`lib/lab/lab_container.dart`，实现 `title/slug/description/buildPage`，slug 纯 ASCII）→ `void registerRelationCalcDemo() { demoRegistry.register(RelationCalcDemo()); }` → `lib/lab/lab_bootstrap.dart` 加 import + 注册调用。**2 处**，`fr://lab/demo/relation-calc` 路由自动生成。
- **SharedPreferences 先例**：`lib/lab/demos/team_card/constants.dart`（预设存 JSON string key）、`lib/core/novel_reader/novel_reader_storage.dart`、`lib/lab/demos/web_bookmark/providers/bookmark_provider.dart`
- **常量规范**：`lib/lab/demos/relation_calc/const_relation_calc.dart` 配 `RelationCalcConsts` 类统一管理；core 模块用 `relation_calc.dart` 统一 export（参照 `lib/core/word_drag/word_drag.dart`）
- **设计标杆**：`lib/screens/profile/lab/game_center/game_center_cards.dart`（自适应网格/内容平衡）、`lib/lab/demos/stack_card_demo.dart`（景深层次）；assets 有动物 PNG/图标可作头像
- **无既有亲属计算代码**（grep 确认）；日历 `PersonRelation` 只是家庭标签，不可复用
- **Lab 规范**：不加多余返回按钮（DemoPage 已有包装）、+ 按钮只需一个

## 文件落点（已确认）

| 文件 | 内容 |
|---|---|
| `lib/core/relation_calc/relation_calc.dart` | 统一 export（方案 b core 模块入口） |
| `lib/core/relation_calc/relation_calc_models.dart` | Entity / Term / Rule 模型 + toMap/fromMap（手写，避开 Hive adapter 坑） |
| `lib/core/relation_calc/relation_engine.dart` | 图结构 + 链式计算 `resolve`（纯函数可单测） |
| `lib/core/relation_calc/relation_calc_store.dart` | SharedPreferences 持久化（JSON 整库读写） |
| `lib/core/relation_calc/kinship_preset.dart` | 亲戚关系预设数据（50-80 称谓的 Entity/Term/Rule） |
| `lib/lab/demos/relation_calc/relation_calc_demo.dart` | DemoPage 注册 + 主页面（<400 行） |
| `lib/lab/demos/relation_calc/const_relation_calc.dart` | 模块常量 |
| `lib/lab/demos/relation_calc/calc_view.dart` | 计算主界面 |
| `lib/lab/demos/relation_calc/manage_view.dart` | 实体/关系词/规则 CRUD 界面 |
| `lib/lab/lab_bootstrap.dart` | 注册 2 处 |

## 边界

- 计算引擎通用化，不写死亲戚逻辑；亲戚仅作为内置预设；公司团队等级称呼等自定义领域同样可算
- 链式运算无限嵌套（图路径查找），单步无解优雅降级（提示 + 可撤销）
- 不新增 package（SharedPreferences 已有；UI 用 zen 组件库）；不用 Hive
- 不动既有模块；不改路由系统（demo slug 自动注册）
- 数据本地持久化（SharedPreferences），不做云同步

## 验收标准

1. 新 demo `relation-calc` 出现在 Lab 列表，点击进入可用
2. **引擎通用性**：自定义实体/关系词/规则后，能计算任意领域（如公司团队：组长 的 上级 = 经理，链式传递；宠物：猫 的 宝宝 = 小猫）
3. **预设**：首次进入自动导入亲戚关系预设；核心链条抽样验证：爸爸+爸爸=爷爷、爸爸+爸爸+爸爸=太爷爷、妈妈+妈妈=外婆、妈妈+哥哥=舅舅、爸爸+哥哥=伯父、爸爸+弟弟=叔叔、爸爸+姐姐=姑妈、哥哥+儿子=侄子、姐姐+女儿=外甥女
4. **CRUD**：实体/关系词/规则增删改查可用，SharedPreferences 持久化重启不丢；重置回预设可用
5. **UI**：zen 主题 + 边框强调；计算主界面关系链实时更新、撤销/清空可用；自适应布局无溢出
6. 常量集中 `const_relation_calc.dart`；`flutter analyze` 无新增 issue
7. commit 后 push 触发 GitHub APK 流水线
8. 完成后 `kvcli todo done 20 --result "..."` 回填
