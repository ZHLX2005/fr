---
name: key_board_3
description: 当用户要求"拆分到references"、"给skill加ref引导"、"把xx沉淀为reference"、"优化skill结构"、"重构skill"、"skill膨胀了"、"合并skill"时触发。本 skill 专用于通过 references 优化已有 skill——把膨胀内容拆到 references/ 子文档并在原 SKILL.md 加加载引导。不创建新 skill、不改变前置 skill (key_board / key_board_2) 的职责。
---

# Key Board 3 — Skill References 优化器

## 触发条件

当用户说以下内容时触发：

- "把 xx 沉淀为 reference" / "拆到 references" / "单独存一下"
- "这个 skill 太大了 / 膨胀了"
- "给 skill 加 ref 引导" / "什么时候读哪个 ref，加一下"
- "按子主题拆分" / "重构 skill 结构"
- "合并 skill" / "把多个 skill 合成一个"
- "统一所有 skill 的 ref 架构"

## 核心原则

**key_board_3 是 skill 的"减肥 + 加路标"手术，不是"建新大楼"。**

| 不做什么 | 做什么 |
|---|---|
| ❌ 不创建新 skill 目录 | ✅ 把已有 SKILL.md 拆瘦 |
| ❌ 不修改前置 skill (key_board / key_board_2) | ✅ 在 SKILL.md 加 ref 加载引导 |
| ❌ 不改 skill 的核心流程/触发条件 | ✅ 允许轻度润色描述、补错误案例 |
| ❌ 不动 skill 的代码实现 | ✅ 只搬文档结构 |

**前置依赖**（不要变）：
- `key_board` — 创建新 skill
- `key_board_2` — 创建 skill 的元模板
- `key_board_3`（本 skill）— 优化已有 skill 的结构

## 与 key_board_2 的核心区别（一句话）

> **key_board_2 创建新 skill，key_board_3 创建 references**。
> 一个是"建新楼"，一个是"拆老楼"。

| 维度 | key_board_2 | key_board_3 |
|---|---|---|
| 动作 | 创建新 skill | 创建 `references/<ref>.md` |
| 输出物 | 独立目录 | 已存在 skill 的子目录 |
| 主 SKILL.md 改动 | 不存在 | 加锚点 + 索引表登记 |

## 触发场景

4 类场景中，**场景 C 是核心**（触发最频繁，占多数）。其余三类是配套。

### 场景 A：SKILL.md 膨胀拆分

**信号**：SKILL.md > 300 行，或多个子主题挤在一起。

1. 列出章节，识别可独立主题
2. 为每个主题创建 `references/<ref-name>.md`
3. 内容迁移 + 留 `[[ref-name]]` 锚点
4. 保留 SKILL.md < 500 行（理想 < 200）

### 场景 B：添加 ref 加载引导

**信号**：已有 `references/` 但没写加载时机。

1. 列出 ref 文档
2. 在 SKILL.md 加"何时读每个 ref"的引导段
3. 用表格：`| ref | 何时读取 | 路径 |`

### ★ 场景 C：把特定主题沉淀为 ref（核心场景）

**信号**：用户明确说"把 xx 沉淀为 reference"。

1. 识别主题在 SKILL.md 里的位置和范围
2. 创建 `references/<ref-name>.md`，完整迁移内容
3. 在原位置留锚点 + 一句话总结
4. 在 SKILL.md 末尾的 ref 索引表里登记

**完整 SOP、常见错误、正反例见 [[场景C-沉淀为ref]]**。

### 场景 D：多 skill 统一 ref 架构

**信号**：用户要求一批 skill 统一结构。

1. 选结构最完善的 skill 作模板
2. 把 ref 模式抽象成清单
3. 逐个 skill 应用
4. 每完成一个做最小验证（行数 < 500、索引完整）

---

## 合并 Skill 场景（特殊优化）

> 用户说"合并 skill / 把多个 skill 合成一个"时，是 key_board_3 的**特殊优化场景**——既涉及"创建新 skill"（合并产生），也涉及"创建 references"（归档原 skill）。

**先走 key_board_3 主流程判断**（是否真要合并？拆出去不行吗？），**再加载 [[merge-skill-专项]]** 获得 4 阶段合并执行细节。

注意：合并产生的"新 skill"是合并动作的**副产品**，不是 key_board_3 的本职动作。本职仍是"创建 references 和加引导"。

---

## 操作 SOP（5 步）

### Step 1: 识别作用域

问用户（或自己推断）：

- 目标 skill 是哪个？（路径）
- 触发的是 A/B/C/D 哪个场景？
- 是否限制不动某些章节？（如"前置 skill 不变"）

### Step 2: 列出当前结构

读取目标 skill 的 SKILL.md，列出：

- 总行数
- 章节大纲
- 是否已有 references/
- 已有 ref 数量

**判断阈值**：

| 行数 | 状态 | 行动 |
|---|---|---|
| < 200 | 健康 | 不动 |
| 200–300 | 警戒 | 看用户意图 |
| 300–500 | 建议拆分 | 主动提议场景 C / A |
| > 500 | 必须拆分 | 直接执行场景 C / A |

### Step 3: 设计方案

- **场景 C/A**：ref 名称、文件路径、加载时机、预估行数
- **场景 B**：只在末尾加引导段
- **场景 D**：先选模板 skill

**征求用户确认**后再动手——除非用户已明确说"按你判断拆"。

### Step 4: 执行

按场景执行：

- 场景 A：建 `references/` → 迁移内容 → 留 `[[ref-name]]` 链接
- 场景 B：只加引导段，不动正文
- **场景 C：单主题迁移 → 留锚点 → 末尾索引登记**
- 场景 D：批处理，每完成一个 skill 报告一次

### Step 5: 校验

- [ ] 目标 SKILL.md 行数 < 500
- [ ] ref 文档与 SKILL.md 之间有清晰的 `[[ref-name]]` 引用
- [ ] ref 加载引导明确（什么时候读这个 ref）
- [ ] 前置 skill（key_board / key_board_2）未受影响
- [ ] 核心流程/触发条件未变
- [ ] 没有遗留空 ref 文档

## 易错和坑（高频错误）

| 错误 | 根因 | 预防 |
|---|---|---|
| 给单 skill 强行套 references/ | 单 skill 不需要 ref 子目录 | 行数 < 300 且无多领域时不要硬拆 |
| ref 文档没有加载引导 | 以为 ref 自己会被读 | SKILL.md 里必须写"何时读这个 ref" |
| 把 ref 名和文件名弄混 | 链接不规范 | `[[ref-name]]` 中的 name 必须等于文件名 |
| 拆得太碎（一个章节一个 ref） | 过度优化 | ref 主题必须有独立价值，不是为了拆而拆 |
| 顺手改了 skill 核心流程 | 越权润色 | 本 skill 只做结构，核心流程/触发条件禁止动 |
| 把前置 skill 也"优化"了 | 忘记边界 | key_board / key_board_2 是不可变的 |
| 把主流程步骤也拆出去 | 误以为所有内容都可沉淀 | 主流程、触发条件、检查清单必须留在主 SKILL.md |
| 拆完忘记登记索引表 | ref 成为孤儿文档 | Step 4 强制末尾索引登记 |

## 错误案例记录规范

每次执行 key_board_3 后，必须在本次操作的 skill 末尾追加一条错误案例（如果有踩坑），模板：

```
### [日期] key_board_3 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ... | ... | ... |
```

## 成功标准检查清单

- [ ] 目标 SKILL.md < 500 行（理想 < 200）
- [ ] 所有 ref 文档有明确加载引导（在 SKILL.md 中可找到）
- [ ] `[[ref-name]]` 链接与文件名一一对应
- [ ] 前置 skill (key_board / key_board_2) 未变
- [ ] 目标 skill 的核心流程/触发条件未变
- [ ] 没有空 ref 文档
- [ ] 用户确认了拆分方案（如未明确授权）

## 何时**不**触发本 skill

- 用户想**创建新 skill** → 用 key_board 或 key_board_2
- 用户想**改 skill 的代码/实现** → key_board_3 不管代码
- 用户想**优化 skill 触发描述**（description 字段） → 用 `skill-creator` 的 description 优化流程
- 用户想**评估/量化 skill 效果** → 用 `skill-creator` 的 eval 流程
- 目标 skill 行数 < 200 且无多领域 → 不要硬拆，劝退

## 与其他 skill 的协作

```
key_board      →  创建新 skill (从 0 到 1)
key_board_2    →  用元模板创建 skill (从 0 到 1 的标准流程)
key_board_3    →  优化已有 skill 的结构 (从 1 到 N 的演化)
skill-creator  →  评估/优化/打包 skill (质量保障)
```

key_board_3 在演化链路上，承接 key_board / key_board_2 创建出来的 skill，做后续结构优化。

## 引用索引（按需加载）

| ref | 何时读取 | 路径 |
|---|---|---|
| [[场景C-沉淀为ref]] | 触发场景 C 时（最频繁） | references/场景C-沉淀为ref.md |
| [[merge-skill-专项]] | 用户说"合并 skill"时 | references/merge-skill-专项.md |