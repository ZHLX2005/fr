
# OSSA：单 Skill 序列驱动架构方案 V1.0

设计目标：一个 Skill 统一入口，编码统一管理资产，序列驱动任务执行，知识按需命中，模板插槽完成任务。

本方案将此前讨论收敛为一套可落地的架构规范，适用于项目的新增开发、存量维护、Bug 修复、性能优化和代码分析。

核心决策已经确定：

- 单入口：每个项目仅有一个正式工程 Skill。
- 双资产目录：除 `SKILL.md` 外，参考资产放在 `references/`，可执行工具放在 `scripts/`。
- 统一编码：采用 `Aa01-xxxx.md`，小类字母可选。
- 混合序列：主流程固定，辅助步骤根据任务状态动态插入。
- 自动执行：Agent 自主判定需求、选择序列、检索知识、执行修改和验证。
- 资产分类与执行顺序分离：编码决定资产身份，序列定义决定执行顺序。
- 薄入口、按需加载：不将整个项目的知识和所有流程塞进 `SKILL.md`。

## 一、总体架构

## SKILL.md

唯一入口 · 任务判定 · 序列调度 · 状态机 · 安全规则

### 任务判定器

开发 DEV / 排障 DBG / 优化 OPT / 分析 ANL / 混合 MIX

### 序列调度器

固定主干 + 动态辅助步骤 + 阶段转换

references/

序列、知识、模板、索引、案例

scripts/

检索、分析、校验、测试辅助

### 模板插槽 → 执行 → 验证 → 完成

形成可追踪、可验证、可复用的任务闭环

这里需要区分两种「单」：

- 单 Skill：只有一个对外的正式 Skill 入口。
- 单任务控制面：当前任务只有一个统一的状态与调度逻辑。

内部可以有多条序列、多个知识文件和多个脚本，但不能出现互相竞争的入口规则，也不能让每份资产重新定义一套全局调度机制。

## 二、目录与资产规范

采用标准 Skill 目录结构，内部文件扁平存放。

```
project-engineer/
├── SKILL.md
├── references/
│   ├── A00-资产总索引.md
│   ├── A01-需求判定规则.md
│   ├── A02-任务切换规则.md
│   ├── Ba01-开发序列.md
│   ├── Bb01-Debug序列.md
│   ├── Bc01-优化序列.md
│   ├── Bd01-分析序列.md
│   ├── Ca01-领域模型.md
│   ├── Cb01-接口契约.md
│   ├── Cc01-调用链.md
│   ├── Cd01-架构约束.md
│   ├── Da01-开发模板.md
│   ├── Db01-Debug模板.md
│   ├── Dc01-优化模板.md
│   ├── Ea01-Demo参考.md
│   └── Fa01-验证规范.md
└── scripts/
    ├── search_assets.py
    ├── analyze_impact.py
    └── validate_changes.py
```

这是一份建议性的初始清单，不要求项目第一天就创建全部资产。按实际业务从最小可运行集合开始即可。

### 资产编码规则

统一格式：

# Aa01-xxxx.md

A = 大类 · a = 可选小类 · 01 = 编号 · xxxx = 语义名称

| 规则     | 定义                                       |
| -------- | ------------------------------------------ |
| 大类     | 单个大写字母，定义稳定的资产类别           |
| 小类     | 可选的单个小写字母，用于细分大类           |
| 编号     | 两位数字，默认从 `01` 开始               |
| 名称     | 简洁、明确、方便自然语言检索               |
| 文件位置 | 所有 Markdown 资产统一放在 `references/` |
| 唯一性   | 同一项目内完整编码不得重复                 |
| 执行顺序 | 由序列正文明确声明，不由编号推断           |

大类初始映射：

| 大类 | 名称     | 资产范围                       |
| ---- | -------- | ------------------------------ |
| A    | 调度规则 | 需求分类、路由规则、任务切换   |
| B    | 执行序列 | 开发、Debug、优化、分析流水线  |
| C    | 项目知识 | 模型、契约、链路、架构约束     |
| D    | 任务模板 | 输入插槽、阶段产物、输出格式   |
| E    | 案例参考 | Demo、历史故障、成熟实现       |
| F    | 验证质量 | 测试、质量门槛、回归与风险检查 |

这些大类只用于资产分类。例如，`Bb01-Debug序列.md` 是一个序列资产，`Cb01-接口契约.md` 是一个知识资产。它们的字母顺序不代表 Debug 必须在契约读取之前或之后执行。

## 三、需求判定器规范

需求判定器是整个架构的第一道决策关口。它不直接解决任务，而是将自然语言请求转换成可执行的任务对象。

### 3.1 任务分类

| 类型 | 编码    | 主要判断依据                               |
| ---- | ------- | ------------------------------------------ |
| 开发 | `DEV` | 新增功能、扩展能力、新接口、新模块         |
| 排障 | `DBG` | 错误、异常、测试失败、行为不符合预期       |
| 优化 | `OPT` | 性能、稳定性、成本、可维护性改进           |
| 分析 | `ANL` | 理解项目、梳理代码、解释设计、评估方案     |
| 混合 | `MIX` | 多个目标同时存在，或执行中发现任务性质改变 |

判定依据是用户希望达成的结果，而不是单个关键词。

例如：

- 「订单状态偶尔不更新」→ `DBG`
- 「增加订单状态导出能力」→ `DEV`
- 「降低订单查询延迟」→ `OPT`
- 「解释订单状态是如何流转的」→ `ANL`
- 「先修复状态异常，再增加状态审计能力」→ `MIX`，通常先排障，再开发

### 3.2 判定器的输出协议

每个任务都应形成一份结构化任务状态。以下为逻辑示例：

```
task_id: TASK-001
type: DBG
objective: 修复订单状态异常
scope:
  - order-service
constraints:
  - 保持现有接口兼容
acceptance:
  - 异常能够复现并得到修复
  - 相关回归测试通过
sequence_id: Bb01
template_id: Db01
current_step: evidence_collection
slots:
  reproduction:
    status: missing
  actual_behavior:
    status: known
  expected_behavior:
    status: known
  root_cause:
    status: pending
knowledge_refs:
  - Cb01
  - Cc01
```

这份任务状态是运行时数据，不是每次都要新建一个永久文件。若需要持久化任务记录，可以由脚本或 Agent 运行环境保存。

### 3.3 判定器必须遵守的规则

1. 优先使用用户请求和已有项目上下文识别任务。
2. 能从代码、配置、测试、日志获得的信息，先自行调查。
3. 不因为缺少某个插槽就立即向用户提问。
4. 任务存在多个目标时，确定主目标及其依赖关系。
5. 发现任务类型改变时，更新任务状态并切换序列，保留已经收集的证据。
6. 无法确认的事实必须标记为未知，不得当成已验证结论。

## 四、序列 ID 与步骤协议

序列是整个架构的执行引擎。它不等于知识分类，也不是简单的文件读取清单。

### 4.1 序列的定义

序列由以下部分组成：

- 固定主干：每次任务必须遵守的关键阶段。
- 动态步骤：根据条件选择性执行的步骤。
- 知识引用：当前步骤需要的参考资产。
- 模板引用：当前阶段使用的输入输出契约。
- 退出条件：什么情况下可以进入下一阶段或结束任务。

序列 ID 使用资产编码，例如 `Ba01`。执行中的当前步骤另用稳定的 `step_id` 标识，避免把文件编号当成步骤编号。

### 4.2 开发序列：`Ba01-开发序列.md`

S01

需求与验收标准

明确目标、范围、约束和完成条件。

S02

项目认知与参考实现

读取相关代码、Demo 和现有模式。

S03

模型与契约检查

核对领域模型、接口和兼容性。

S04

方案与影响评估

确定修改位置、依赖、风险和实施顺序。

S05

实现变更

按照项目约定执行最小必要修改。

S06

验证与交付

执行测试、检查差异并汇报结果。

固定主干不代表每个阶段都必须进行同等规模的工作。例如，一个局部文案修改可以简化模型与契约检查；但如果改动涉及公共接口，就必须执行兼容性检查。

### 4.3 Debug 序列：`Bb01-Debug序列.md`

S01

问题结构化

确定现象、预期、实际结果和影响范围。

S02

证据收集

获取日志、堆栈、复现步骤和相关代码。

S03

候选根因与验证

结合模型、契约、调用链建立并验证假设。

S04

最小修复

修复已得到证据支持的根因。

S05

回归与风险验证

检查相关路径、测试结果及副作用。

S06

结果与残余风险

报告根因、修改、证据、验证及未解决事项。

Debug 的检索顺序不能简单硬编码成「模型、契约、链路」适用于所有问题。建议先使用这些类别作为高优先级候选，再结合具体异常选择路径：

- 数据错误：优先模型、状态约束、数据读写。
- 接口错误：优先契约、序列化、版本兼容。
- 流程错误：优先调用链、分支条件、异步和补偿。
- 性能错误：优先调用链、资源使用、缓存和查询计划。
- 偶发错误：优先并发、时序、超时和重试。

高优先级只影响候选排序，不代表可以跳过反证和验证。

### 4.4 序列文件的统一协议

所有序列文件采用相同的结构：

```
---
id: Bb01
type: sequence
title: Debug序列
version: 1
intent: 定位并修复项目中的缺陷
template: Db01
---

# 目标
定义该序列解决的问题及完成标准。

# 适用条件
明确触发条件、排除条件和切换条件。

# 固定主干
列出必须执行的核心阶段及其依赖顺序。

# 动态步骤
列出可选步骤、触发条件和跳过条件。

# 知识锚点
引用所需的 C 类知识资产及其使用条件。

# 插槽映射
定义每个步骤读取和产生的字段。

# 完成条件
定义验收条件、验证要求和未完成时的处理方式。

# 失败与回退
定义证据不足、验证失败和发现新问题时的处理。
```

序列必须明确回答五个问题：何时触发、做什么、读取什么、产生什么、何时继续。

## 五、知识检索规则：提高命中率，而不是增加阅读量

知识资产采用 C 类编码，但不要求 Agent 每次遍历所有 C 类文件。

### 5.1 知识文件规范

每份知识文件都应包含稳定的元数据和明确的内容边界：

```
---
id: Cb01
type: knowledge
title: 接口契约
version: 1
keywords:
  - API
  - request
  - response
  - schema
entities:
  - Order
  - OrderService
---

# 适用范围
描述知识适用于哪些模块和场景。

# 权威依据
标记对应代码、接口定义、配置或正式规范的位置。

# 约束与事实
记录已确认的字段、状态、接口约束和业务规则。

# 关联资产
列出相关序列、其他知识和验证规范。

# 变更影响
说明哪些模块、调用方、测试可能受到影响。
```

元数据可以采用 YAML front matter 或简单键值格式。重点是整个项目统一使用一种格式，避免解析器和 Agent 同时维护多种约定。

### 5.2 分阶段检索策略

建议采用五步检索，而不是简单的关键词搜索。

01

索引过滤

根据资产类型、模块、实体和适用场景缩小候选范围。

02

语义召回

结合任务描述、错误信息、代码符号和同义表达搜索。

03

候选排序

综合相关度、实体匹配、权威性、版本和变更关联性排序。

04

按需读取

先读最相关的少量资产；若证据不足再扩展检索。

05

证据核验

对照实际代码、测试、配置和运行证据，确认知识是否仍然有效。

如果暂时没有向量数据库，也可以先用前缀过滤、全文搜索、代码符号搜索和 Agent 重排序完成第一版。向量检索是可选的检索实现，不是架构成立的前提。

### 5.3 统一检索评分

可以先用下面的可解释评分模型作为初始排序策略：

\\[ Score(k)=0.35S+0.25E+0.20A+0.10V+0.10I \\]

其中：

- \\(S\\)：语义相关度。
- \\(E\\)：实体、模块或代码符号匹配度。
- \\(A\\)：来源权威性。
- \\(V\\)：版本有效性。
- \\(I\\)：与当前变更的影响关联度。

所有分值归一化到 0～1。权重只是初始假设，后续应使用真实任务的命中数据调整，不能把这个公式视为已经验证的最优参数。

此外，序列阶段可以设置检索优先级，但不能让低优先级知识永远无法被召回。发现证据与预期不符时，Agent 应扩展搜索范围。

### 5.4 知识冲突处理

当知识文件与代码、测试或正式契约发生冲突时：

1. 识别冲突双方的来源、版本和适用范围。
2. 优先核验当前权威实现及正式规范，不能只因某个文件的编码更靠前就相信它。
3. 保留冲突事实，必要时进一步调查。
4. 如果冲突影响安全性、数据完整性或兼容性，不应擅自选择一个结论后继续执行高风险修改。
5. 修复后将已确认的新事实回写到相应知识资产，并更新关联引用。

## 六、模板插槽协议

模板是任务的输入输出契约。它既不是执行序列，也不是一份单纯的最终报告。

### 6.1 插槽的标准结构

每个插槽应具备：

| 字段            | 作用                   |
| --------------- | ---------------------- |
| `slot_id`     | 插槽唯一标识           |
| `purpose`     | 需要解决的问题         |
| `required`    | 是否为必需项           |
| `source`      | 数据来源或证据获取方式 |
| `status`      | 当前填充状态           |
| `value`       | 已获取的内容           |
| `evidence`    | 支持该内容的依据       |
| `next_action` | 缺失时如何继续         |

统一使用以下状态：

- `known`：已获取并确认。
- `inferred`：有依据的推断，尚未完全确认。
- `missing`：尚未获取。
- `pending`：等待验证。
- `not_applicable`：当前任务不适用。
- `blocked`：由于依赖、权限或环境问题无法继续。

不应将 `missing` 直接当作失败，也不应将 `inferred` 当作已经证实的事实。

### 6.2 Debug 模板示例

文件：`Db01-Debug模板.md`

```
template_id: Db01
task_type: DBG

slots:
  - id: problem
    required: true
    fields:
      - symptom
      - expected_behavior
      - actual_behavior
      - impact_scope

  - id: evidence
    required: true
    fields:
      - logs
      - stack_trace
      - reproduction
      - relevant_code

  - id: root_cause
    required: true
    fields:
      - hypothesis
      - supporting_evidence
      - counter_evidence
      - verification_result

  - id: fix
    required: true
    fields:
      - changed_files
      - fix_description
      - compatibility_impact

  - id: validation
    required: true
    fields:
      - tests_run
      - test_results
      - residual_risks
      - rollback_plan
```

模板中的必需项不意味着每个字段都必须由用户提供。Agent 应优先自动收集证据；对于不适用的字段，允许有依据地标记 `not_applicable`。

### 6.3 插槽驱动执行

Agent 每次推进任务时，都应先判断当前步骤需要哪些插槽：

1. 已满足：直接使用。
2. 缺失但可自动获取：检索代码、测试、日志或知识。
3. 缺失且需要验证：执行可用的测试或检查。
4. 缺失且无法自动获取：判断是否阻塞当前任务。
5. 非必需或不适用：跳过，并保留理由。

这避免了两个极端：一是每次任务都重复询问用户，二是信息不足时凭空补全。

## 七、状态机：固定主干与动态步骤如何协作

序列负责描述允许的流程，状态机负责决定 Agent 当前处于哪个阶段，以及下一步可以做什么。

### 7.1 标准状态

| 状态         | 含义                           |
| ------------ | ------------------------------ |
| `CLASSIFY` | 识别任务类型和目标             |
| `PLAN`     | 选择序列、模板与初始步骤       |
| `GATHER`   | 收集证据并检索知识             |
| `EXECUTE`  | 执行当前步骤或修改             |
| `VERIFY`   | 验证假设、修改和验收条件       |
| `REPLAN`   | 根据新证据更新计划或切换序列   |
| `BLOCKED`  | 存在无法自行解决的阻塞         |
| `DONE`     | 满足完成条件                   |
| `FAILED`   | 达到明确失败条件，无法完成任务 |

### 7.2 状态转换

\#chatgpt-mermaid-\_r_tr\_{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;fill:rgb(13, 13, 13);}@keyframes edge-animation-frame{from{stroke-dashoffset:0;}}@keyframes dash{to{stroke-dashoffset:0;}}#chatgpt-mermaid-\_r_tr\_ .edge-animation-slow{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 50s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_tr\_ .edge-animation-fast{stroke-dasharray:9,5!important;stroke-dashoffset:900;animation:dash 20s linear infinite;stroke-linecap:round;}#chatgpt-mermaid-\_r_tr\_ .error-icon{fill:rgb(243, 243, 243);}#chatgpt-mermaid-\_r_tr\_ .error-text{fill:rgb(13, 13, 13);stroke:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .edge-thickness-normal{stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .edge-thickness-thick{stroke-width:3.5px;}#chatgpt-mermaid-\_r_tr\_ .edge-pattern-solid{stroke-dasharray:0;}#chatgpt-mermaid-\_r_tr\_ .edge-thickness-invisible{stroke-width:0;fill:none;}#chatgpt-mermaid-\_r_tr\_ .edge-pattern-dashed{stroke-dasharray:3;}#chatgpt-mermaid-\_r_tr\_ .edge-pattern-dotted{stroke-dasharray:2;}#chatgpt-mermaid-\_r_tr\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_tr\_ .marker.cross{stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_tr\_ svg{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:16px;}#chatgpt-mermaid-\_r_tr\_ p{margin:0;}#chatgpt-mermaid-\_r_tr\_ .label{font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .cluster-label text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .cluster-label span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .cluster-label span p{background-color:transparent;}#chatgpt-mermaid-\_r_tr\_ .label text,#chatgpt-mermaid-\_r_tr\_ span{fill:rgb(13, 13, 13);color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .node rect,#chatgpt-mermaid-\_r_tr\_ .node circle,#chatgpt-mermaid-\_r_tr\_ .node ellipse,#chatgpt-mermaid-\_r_tr\_ .node polygon,#chatgpt-mermaid-\_r_tr\_ .node path{fill:rgb(222, 234, 251);stroke:rgb(83, 154, 248);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .rough-node .label text,#chatgpt-mermaid-\_r_tr\_ .node .label text,#chatgpt-mermaid-\_r_tr\_ .image-shape .label,#chatgpt-mermaid-\_r_tr\_ .icon-shape .label{text-anchor:middle;}#chatgpt-mermaid-\_r_tr\_ .node .katex path{fill:#000;stroke:#000;stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .rough-node .label,#chatgpt-mermaid-\_r_tr\_ .node .label,#chatgpt-mermaid-\_r_tr\_ .image-shape .label,#chatgpt-mermaid-\_r_tr\_ .icon-shape .label{text-align:center;}#chatgpt-mermaid-\_r_tr\_ .node.clickable{cursor:pointer;}#chatgpt-mermaid-\_r_tr\_ .root .anchor path{fill:rgb(143, 143, 143)!important;stroke-width:0;stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_tr\_ .arrowheadPath{fill:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_tr\_ .edgePath .path{stroke:rgb(143, 143, 143);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .flowchart-link{stroke:rgb(143, 143, 143);fill:none;}#chatgpt-mermaid-\_r_tr\_ .edgeLabel{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_tr\_ .edgeLabel p{background-color:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_tr\_ .edgeLabel rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_tr\_ .labelBkg{background-color:rgba(252, 252, 252, 0.5);}#chatgpt-mermaid-\_r_tr\_ .cluster rect{fill:rgb(243, 243, 243);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .cluster text{fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ .cluster span{color:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ div.mermaidTooltip{position:absolute;text-align:center;max-width:200px;padding:2px;font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";font-size:12px;background:rgb(243, 243, 243);border:1px solid rgba(0, 0, 0, 0.1);border-radius:2px;pointer-events:none;z-index:100;}#chatgpt-mermaid-\_r_tr\_ .flowchartTitleText{text-anchor:middle;font-size:18px;fill:rgb(13, 13, 13);}#chatgpt-mermaid-\_r_tr\_ rect.text{fill:none;stroke-width:0;}#chatgpt-mermaid-\_r_tr\_ .icon-shape,#chatgpt-mermaid-\_r_tr\_ .image-shape{background-color:rgb(252, 252, 252);text-align:center;}#chatgpt-mermaid-\_r_tr\_ .icon-shape p,#chatgpt-mermaid-\_r_tr\_ .image-shape p{background-color:rgb(252, 252, 252);padding:2px;}#chatgpt-mermaid-\_r_tr\_ .icon-shape .label rect,#chatgpt-mermaid-\_r_tr\_ .image-shape .label rect{opacity:0.5;background-color:rgb(252, 252, 252);fill:rgb(252, 252, 252);}#chatgpt-mermaid-\_r_tr\_ .label-icon{display:inline-block;height:1em;overflow:visible;vertical-align:-0.125em;}#chatgpt-mermaid-\_r_tr\_ .node .label-icon path{fill:currentColor;stroke:revert;stroke-width:revert;}#chatgpt-mermaid-\_r_tr\_ .node .neo-node{stroke:rgb(83, 154, 248);}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node rect,#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].cluster rect,#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node polygon{stroke:url(#chatgpt-mermaid-\_r_tr\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].swimlane.cluster rect{filter:none;}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node path{stroke:url(#chatgpt-mermaid-\_r_tr\_-gradient);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node .outer-path{filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node .neo-line path{stroke:rgb(83, 154, 248);filter:none;}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node circle{stroke:url(#chatgpt-mermaid-\_r_tr\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].node circle .state-start{fill:#000000;}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].icon-shape .icon{fill:url(#chatgpt-mermaid-\_r_tr\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_tr\_ [data-look="neo"].icon-shape .icon-neo path{stroke:url(#chatgpt-mermaid-\_r_tr\_-gradient);filter:drop-shadow( 1px 2px 2px rgba(185,185,185,1));}#chatgpt-mermaid-\_r_tr\_ .node text{font-size:14px;font-weight:600;letter-spacing:normal;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_tr\_ .edgeLabels text{font-size:13px;font-weight:600;letter-spacing:-0.08px;fill:rgb(0, 79, 153);}#chatgpt-mermaid-\_r_tr\_ .node tspan[font-weight="normal"],#chatgpt-mermaid-\_r_tr\_ .edgeLabels tspan[font-weight="normal"]{font-weight:600;}#chatgpt-mermaid-\_r_tr\_ .edgeLabel .label rect{opacity:1;rx:13px;ry:13px;fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .node rect,#chatgpt-mermaid-\_r_tr\_ .node circle,#chatgpt-mermaid-\_r_tr\_ .node ellipse,#chatgpt-mermaid-\_r_tr\_ .node polygon,#chatgpt-mermaid-\_r_tr\_ .node path{fill:rgb(229, 243, 255);stroke:rgba(0, 0, 0, 0.1);stroke-width:1px;}#chatgpt-mermaid-\_r_tr\_ .node rect{rx:16px;ry:16px;}#chatgpt-mermaid-\_r_tr\_ .node.mermaid-decision .label-container{fill:rgb(245, 250, 255);stroke:rgb(206, 219, 229);stroke-dasharray:2,2;}#chatgpt-mermaid-\_r_tr\_ .edgePaths .flowchart-link{stroke:rgb(143, 143, 143);stroke-width:1px;stroke-linecap:round;stroke-linejoin:round;}#chatgpt-mermaid-\_r_tr\_ .marker{fill:rgb(143, 143, 143);stroke:rgb(143, 143, 143);}#chatgpt-mermaid-\_r_tr\_ :root{--mermaid-font-family:-apple-system-body,ui-sans-serif,-apple-system,system-ui,"Segoe UI",Helvetica,"Apple Color Emoji",Arial,sans-serif,"Segoe UI Emoji","Segoe UI Symbol";}CLASSIFY 需求判定PLAN 选择序列与模板GATHER 检索知识和证据前置条件满足？BLOCKED 阻塞处理EXECUTE 执行当前步骤VERIFY 验证结果满足当前阶段条件？DONE 完成REPLAN 更新计划否，可自动获取否，无法获取是是，还有步骤是，任务完成否，可修正否，无法继续

### 7.3 动态切换规则

例如，Debug 执行到一半，发现真正问题是一个从未实现的业务能力：

- 保留已收集的日志、代码位置和假设验证结果。
- 更新任务目标和分类。
- 根据原任务是否已解决，选择开发序列作为主序列或辅助序列。
- 重新检查开发模板所需插槽。
- 避免重复执行已经完成且仍然有效的检查。

动态切换不能抹掉证据，也不能绕过原序列的安全与验收条件。

### 7.4 完成条件

不能因为 Agent 已经走到最后一个步骤就判定任务完成。

完成状态必须依据任务类型验证：

- 开发：需求实现，关键验收条件满足，必要测试通过。
- Debug：修复有证据支撑，相关回归完成，剩余风险明确。
- 优化：与基线比较，目标指标得到验证或差距得到解释。
- 分析：问题得到回答，关键判断有来源支撑。
- 混合：所有必需子目标均完成，或明确标记未完成项。

如果测试环境不可用，任务可以进入受限完成或阻塞状态，但不能谎称验证通过。

## 八、唯一入口 `SKILL.md` 的正式职责

这是整套架构最重要的文件。它不应该变成所有知识的集合，而应该成为所有任务执行时唯一可信的调度规范。

建议入口包含以下内容：

01

身份与目标

声明该 Skill 是项目开发、维护、排障和分析的统一入口。

02

资产协议

定义编码格式、资产类别、索引位置和引用规则。

03

任务判定

定义分类方法、混合任务处理及动态切换规则。

04

序列调度

定义如何选择序列、执行固定主干、触发动态步骤。

05

知识检索

定义按需加载、证据核验、冲突处理与扩展检索。

06

模板插槽

定义插槽状态、缺失处理、产物契约和完成条件。

07

执行与安全

定义工具调用、文件修改、测试、权限及破坏性操作边界。

08

任务闭环

定义验证、失败回退、交付汇报和知识更新规则。

下面是可以直接用作第一版入口的核心骨架。

---

# Project Engineer

## 1. 核心规则

本 Skill 是当前项目唯一的工程任务入口。

所有任务统一遵循：

需求判定 → 序列选择 → 插槽检查 → 知识检索 → 执行 → 验证 → 交付。

不得为不同任务创建互相竞争的顶层 Skill，也不得将资产编码顺序当成任务执行顺序。

## 2. 资产定位

- 入口规则：当前 SKILL.md
- 资产索引：references/A00-资产总索引.md
- 序列资产：references 中 B 类文件
- 知识资产：references 中 C 类文件
- 模板资产：references 中 D 类文件
- 案例资产：references 中 E 类文件
- 验证资产：references 中 F 类文件
- 可执行工具：scripts 中的脚本

读取资产前，先确认其 ID、用途和适用条件。
仅加载当前任务所需内容，不默认读取全部资产。

## 3. 任务判定

识别主任务类型：

- DEV：开发与功能扩展
- DBG：缺陷定位与修复
- OPT：性能、稳定性或可维护性优化
- ANL：项目理解、代码分析与方案评估
- MIX：多个目标并存

以用户期望的结果为主要判断依据。
混合任务应识别目标依赖关系，选择主序列并按需引入辅助序列。

## 4. 序列选择

通过资产索引定位匹配序列，读取完整序列定义后再执行。

序列决定固定主干、动态步骤、前置条件、知识引用、插槽映射和完成条件。

不得仅凭文件编号推断执行顺序。

## 5. 插槽与证据

执行每个步骤前：

1. 检查该步骤的必需输入和输出插槽。
2. 优先从项目代码、配置、测试、日志及参考资产中获取信息。
3. 为关键事实保留来源和验证状态。
4. 缺失信息可自动获取时，先自行调查。
5. 无法获得必要证据时，继续调查或进入阻塞处理，不得编造。

插槽状态统一使用：
known、inferred、missing、pending、not_applicable、blocked。

## 6. 知识检索

根据当前步骤选择相关知识资产。
优先考虑语义相关度、代码实体匹配、来源权威性、版本有效性和变更影响。

高优先级只影响检索顺序，不构成排除其他证据的理由。

知识文件与实际代码、正式契约或测试结果发生冲突时，应核验来源、版本和适用范围。

## 7. 执行规则

- 先理解现有实现和项目约定，再修改代码。
- 优先采用最小、可验证的变更。
- 遵守项目现有的测试、格式和兼容性要求。
- 根据需要调用 scripts 中的工具，并检查实际执行结果。
- 未经授权，不执行不必要的破坏性、不可逆或外部副作用操作。
- 不将计划执行、尝试执行和已验证成功混为一谈。

## 8. 状态推进

任务状态按以下流程推进：

CLASSIFY → PLAN → GATHER → EXECUTE → VERIFY。

根据验证结果，可以继续下一步骤、补充证据、切换序列、重新规划或进入阻塞状态。

任务目标改变时保留已有有效证据，并重新检查序列与插槽。

## 9. 完成与交付

只有满足当前任务的验收条件，才能标记为完成。

交付时说明：

- 任务目标与处理结果
- 关键修改或分析结论
- 实际执行的验证及结果
- 未验证事项与残余风险
- 尚未完成的阻塞项

不得将未运行的测试报告为通过，也不得将推断报告为已证实根因。

## 10. 知识维护

只有在新事实得到确认后，才更新对应知识资产。

修改知识后检查相关序列、模板、索引和引用是否仍然有效。
保持资产职责单一，避免在入口、序列和知识文件中重复维护同一份正文。

## 九、scripts 的设计边界

脚本负责确定性操作，不代替 Agent 做高层任务判断。

| 脚本                    | 主要职责                               | 建议阶段   |
| ----------------------- | -------------------------------------- | ---------- |
| `search_assets.py`    | 编码过滤、全文搜索、候选资产排序       | 第一阶段   |
| `analyze_impact.py`   | 分析文件引用、代码符号、测试及依赖影响 | 第二阶段   |
| `validate_changes.py` | 校验编码、元数据、失效引用及文件格式   | 第一阶段   |
| 测试辅助脚本            | 调用项目已有测试工具并结构化结果       | 按项目需要 |

建议优先实现两个脚本：资产检索和资产校验。

这两个脚本可以直接改善系统的基础可靠性：

- 检索脚本避免 Agent 遍历整个知识库。
- 校验脚本避免重复编码、格式错误和引用失效。
- 影响分析脚本可以后续接入 AST、依赖图或 Git 差异分析。
- 测试脚本应复用项目已有测试框架，不要重新发明测试系统。

## 十、实施顺序与验收指标

建议分三个阶段落地，而不是一次性编写大量参考文件。

阶段一：最小闭环

创建唯一 `SKILL.md`、`A00` 总索引、需求判定规则、开发序列、Debug 序列、对应模板和资产校验脚本。

验收：能正确区分任务类型，选对主序列，并完成至少一个开发和一个 Debug 任务。

阶段二：提高命中率

补充项目模型、契约、调用链、架构约束和 Demo 知识；接入全文检索、实体过滤和影响分析。

验收：能找到相关代码与约束，减少无关知识加载，且根因判断有证据支撑。

阶段三：量化与迭代

使用真实任务构建评测集，比较不同检索策略、序列和模板配置的效果。

验收：能够用真实数据衡量命中率、执行成功率、上下文成本和验证完整性。

建议跟踪以下指标：

| 指标              | 衡量内容                        |
| ----------------- | ------------------------------- |
| 任务分类准确率    | 主任务类型是否判断正确          |
| 序列 Top-1 命中率 | 第一选择的序列是否适合该任务    |
| 知识 Recall\@K    | 必需知识是否出现在前 K 个候选中 |
| 根因验证率        | 报告的根因是否经过有效验证      |
| 任务成功率        | 任务是否满足实际验收条件        |
| 上下文成本        | 每次任务实际读取的内容规模      |
| 回归覆盖率        | 必需的验证步骤是否执行并记录    |

初始阶段先建立基线，不建议直接承诺某个固定命中率或 Token 降幅。等积累足够的真实任务数据后，再制定量化目标。

## 十一、最终架构约束

为了防止系统随着项目发展重新变厚，建议把以下约束作为长期规则：

1. 一个项目只有一个正式工程 Skill 入口。
2. 资产统一存放在 `references/` 与 `scripts/`，不再为每类任务建立独立 Skill。
3. 编码前缀代表资产类别，不代表执行顺序。
4. 序列只描述流程和引用，不复制知识正文。
5. 知识只保存事实、约束、证据与来源，不承担全局调度。
6. 模板只定义插槽契约，不承担流程控制。
7. 脚本负责可重复执行的确定性操作，Agent 负责根据任务和证据决策。
8. 所有任务必须经过适当的验证，不能只以生成了答案或修改了代码为完成标准。
9. 新增资产必须有明确用途、稳定编码、适用条件和必要的关联引用。
10. 通过实际任务评测持续调整检索策略，而不是不断堆叠规则。

最终结论： 你的架构不是「单个超大 Skill」，而是一个薄入口控制面，加上编码化参考资产、混合序列引擎、结构化任务插槽和确定性脚本工具。它把复杂性放在可独立维护的资产中，把统一决策和任务闭环留在唯一入口中。

这就是 OSSA V1.0 的核心设计。下一步最合理的落地顺序是：先定稿 `SKILL.md` 与 `A00-资产总索引.md`，再创建 `Ba01-开发序列.md` 和 `Bb01-Debug序列.md`，最后按真实项目的代码结构补充知识资产。
