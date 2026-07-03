---
name: key_board_3
description: 当用户要求"拆分到references"、"给skill加ref引导"、"把xx沉淀为reference"、"优化skill结构"、"重构skill"、"skill膨胀了"时触发。本 skill 专用于通过 references 优化已有 skill——把膨胀内容拆到 references/ 子文档并在原 SKILL.md 加加载引导。不创建新 skill、不改变前置 skill (key_board / key_board_2) 的职责。
---

# Key Board 3 — Skill References 优化器

## 触发条件

当用户说以下内容时触发：

- "这个 skill 太大了 / 膨胀了"
- "拆分到 references"
- "把 xx 沉淀为 reference"
- "按子主题拆分"
- "给 skill 加 ref 引导"
- "什么时候读哪个 ref，加一下"
- "重构 skill / 优化 skill 结构"
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

## 触发场景 → 处理流程

### 场景 A：SKILL.md 膨胀拆分

**信号**：SKILL.md > 300 行，或多个子主题挤在一起。

1. 列出当前 SKILL.md 的章节，识别可独立的主题（format 规范、错误案例、反思方法、调用细节等）
2. 为每个主题创建 `references/<ref-name>.md`
3. 把对应内容从 SKILL.md 移到 ref 文档
4. 在 SKILL.md 原地留 `[[ref-name]]` 链接 + 一句话引导（什么时候读这个 ref）
5. 保留 SKILL.md < 500 行（理想 < 200）

### 场景 B：添加 ref 加载引导

**信号**：SKILL.md 里已经有 `references/` 但没有写明加载时机。

1. 列出已有 ref 文档
2. 在 SKILL.md 末尾或合适位置加"何时读取每个 ref"的引导段
3. 用表格形式：`| ref | 何时读取 | 路径 |`

### 场景 C：把特定主题沉淀为 ref

**信号**：用户明确说"把 xx 沉淀为 reference"。

1. 识别主题在 SKILL.md 里的位置和范围
2. 创建 `references/<ref-name>.md`，完整迁移内容
3. 在原位置留锚点 + 一句话总结
4. 在 SKILL.md 末尾的 ref 索引表里登记

### 场景 D：多 skill 统一 ref 架构

**信号**：用户要求一批 skill 统一结构。

1. 选定一个 skill 作为模板（通常是结构最完善的）
2. 把它的 ref 模式抽象成清单（命名规范、加载引导模板、目录层级）
3. 逐个 skill 应用清单
4. 每个 skill 完成后做最小验证：行数 < 500、ref 索引完整

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
| 300–500 | 建议拆分 | 主动提议场景 A |
| > 500 | 必须拆分 | 直接执行场景 A |

### Step 3: 设计 ref 拆分方案

对每个候选主题给出：

- **ref 名称**：kebab-case 或中文，看 skill 用户习惯
- **文件路径**：`references/<ref-name>.md`
- **加载时机**：在 SKILL.md 哪个流程步骤读它
- **预估行数**：拆分后单文件目标 < 300 行

**征求用户确认**后再动手——除非用户已明确说"按你判断拆"。

### Step 4: 执行拆分

按场景执行：

- 场景 A：建 `references/` → 迁移内容 → 留 `[[ref-name]]` 链接
- 场景 B：只加引导段，不动正文
- 场景 C：单主题迁移
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
| 误把 key_board_2 内容写到 key_board_3 目录 | 复制粘贴时没改 name 和内容 | 写入前确认目录对应的 skill 职责 |

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