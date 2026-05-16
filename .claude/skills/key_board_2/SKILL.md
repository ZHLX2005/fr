---
name: key_board_2
description: 当用户要求"总结成skill"、"保存对话为skill"、"提取提示词"、"做成技能"时触发。这是元技能模板，用于指导创建其他技能，而非被创建的技能本身。
---
# Key Board — Skill 创建元模板

## 触发条件

当用户说以下内容时触发：

- "总结成 skill"
- "保存对话为 skill"
- "提取对话中的提示词"
- "把我的要求存成技能文件"
- "做成 skill"

## 核心原则

**key_board 是"创建 skill 的 skill"，不是要被修改的 skill。**

每次创建新 skill 时，必须：

1. 创建**独立目录** `.claude/skills/<新skill名称>/`
2. 在目录内创建 `SKILL.md`
3. 必须包含 YAML frontmatter

## 创建流程（必须按序执行）

### Step 1: 调用 /sc:reflect 反思

**先调用 /sc:reflect 进行复盘**，整理：

- 成功案例和成功根因
- 错误案例和错误根因
- 坑点和预防方法

### Step 2: Capture Intent

基于反思结果，理解用户意图，回答：

- 这个 skill 要解决什么问题？
- 什么时候触发？
- 输出格式是什么？

### Step 3: 创建目录

```bash
mkdir -p .claude/skills/<skill名称>/
```

### Step 4: 编写 SKILL.md

必须包含：

```yaml
---
name: <skill名称>
description: <触发描述>
---

# Skill 标题
## 内容...
```

### Step 5: 写入内容

基于 /sc:reflect 反思结果，填充成功/失败案例和坑点警示。

## 易错和坑（高频错误）

| 错误                                  | 根因                          | 预防                         |
| ------------------------------------- | ----------------------------- | ---------------------------- |
| 缺少 YAML frontmatter                 | 跳过格式直接写内容            | 写之前先确认文件结构         |
| 在 key_board 目录内创建新 skill       | 混淆元模板职责                | 新 skill 必须在独立目录      |
| frontmatter 的 description 放错误内容 | 没理解 description 是触发描述 | description=触发条件，非总结 |
| 跳过 Capture Intent                   | 急于输出                      | 必须先回答三个问题再动手     |
| 直接修改 key_board 自身内容           | 把元模板当普通 skill          | key_board 是模板，不应被修改 |

## 错误案例记录规范

每个 skill 必须包含错误案例：

```
## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ... | ... | ... |
```

### 我的犯错记录

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把 skill 创建在 `memory/skills/` 目录 | skill 无法被系统识别和触发，分散了记忆与技能的职责 | skill 必须放在 `.claude/skills/<skill名>/SKILL.md` |

**常见坑点类型：**

1. **格式错误** — frontmatter 缺失/错误
2. **目录错误** — 在错误位置创建文件
3. **理解偏差** — 误解用户意图或工具能力
4. **流程跳跃** — 跳过必要步骤

## 成功标准检查清单

- [ ] 创建了独立目录 `.claude/skills/<新skill>/`
- [ ] SKILL.md 包含 YAML frontmatter
- [ ] name 和 description 字段完整
- [ ] description 是触发描述，不是内容总结
- [ ] 内容包含触发场景、核心逻辑
- [ ] 包含错误案例警示（高频坑点）
- [ ] 调用 /sc:reflect 进行复盘

## 调用 skill-creator

创建完 skill 后，可选调用 skill-creator 进行：

- 测试用例编写
- 量化评估
- 描述优化
