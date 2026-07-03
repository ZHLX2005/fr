# Merge-Skill 专项参考（合并/归档场景）

> 本文档来自原 `merge-skill/SKILL.md`，作为 key_board_3 在「**合并多个 skill**」这种**特殊优化场景**下的专项参考。
>
> **使用条件**：当用户说"合并 skill"、"创建统一 skill"、"把多个 skill 合成一个"时，本 ref 是 key_board_3 主流程的**第一阶段操作手册**。
>
> key_board_3 主 SOP 仍负责结构判断（是否真要拆、拆到哪个 ref），本 ref 负责**动手合并时的 4 阶段流程细节**。

---

# Merge Skill — 合并多个 Skill 为统一文档

**REQUIRED SUB-SKILL:** 使用 `superpowers:writing-skills` 或 `/skill-creator` 作为底层流程指导。

如果无法加载，请立刻停止并反馈给用户。

## 核心原则

合并 skill 不是简单拼接，而是：

1. **阅读真实代码** — 确保新 skill 反映最新实现
2. **保留历史参考** — 被合并的 skill 归档到 `references/` 目录
3. **与代码同步** — 文档必须与真实代码一一对应

## 触发条件

- "合并 skill"、"创建统一 skill"
- "把多个 skill 合并成一个"
- "创建 references 目录存放原始 skill"
- "基于真实代码创建新 skill 文档"

---

## 合并流程

### Phase 1: 准备 — 阅读真实代码

```
任务：理解要合并的 skill 所涉及的真实代码

1. 确定 skill 主题对应的代码文件
   → 使用 Glob 搜索相关代码文件
   → 读取 manifest.json 确认 content script 入口

2. 通读所有相关实现代码
   → 按层级顺序阅读：Layer 1 → Layer 2 → Layer 3 → Layer 4
   → 每个关键函数都要读懂实现逻辑

3. 识别代码与现有 skill 文档的差异
   → 对比：函数名、参数、返回值、流程
   → 标记：缺失的说明、过时的示例、不一致的实现

4. 如果发现 skill 文档与代码不符：
   → 【重要】先更新原始 skill 文档使其与代码一致
   → 或者在新 skill 中明确标注"代码已更新"的差异点
   → 绝不能不更正就合并 — 否则错误会被放大
```

**Phase 1 质量检查**：

| 检查项         | 通过标准                          |
| -------------- | --------------------------------- |
| 代码文件完整性 | 所有提到的文件都存在且可读        |
| 函数签名一致   | 文档中的函数签名与代码完全匹配    |
| 示例可运行     | 代码示例复制到 console 能正常执行 |
| 差异已记录     | 每个差异都有明确标注              |

**关键**：不要假设现有 skill 文档是正确的。真实代码才是唯一真相。如果发现问题，先修正再合并。

### Phase 2: 创建新 Skill 主文档

```
任务：基于真实代码创建新的统一 SKILL.md

1. 确定新 skill 名称和目录路径
   → 命名规范：小写字母 + 连字符 (如 video-tracker)
   → 路径：.claude/skills/{新skill名称}/

2. 编写 SKILL.md frontmatter：
   → name：纯小写+连字符
   → description: "Use when..." 开头，描述触发条件（症状），不超过 500 字符

3. 编写文档主体结构：
   ├── Overview (核心原理，一句话)
   ├── 触发条件 (症状列表)
   ├── 核心架构 (层级图或流程图)
   ├── 各层实现 (代码示例 + 说明)
   ├── 文件索引 (文档章节 → 真实代码文件)
   └── 参考资料 (references/ 章节链接)

4. 从真实代码提取关键实现：
   → 复制实际代码片段（不是记忆或推测）
   → 添加行号引用便于定位
   → 代码注释保留（说明 Why）

5. 合并多个 skill 的核心概念：
   → spa-video-detection 的 SPA 路由感知
   → video-progress-tracker 的课程管理
   → 按实际代码架构重新组织
```

**Phase 2 质量检查**：

| 检查项           | 通过标准                              |
| ---------------- | ------------------------------------- |
| frontmatter 完整 | name + description 存在且格式正确     |
| description 规范 | 以 "Use when..." 开头，描述症状非流程 |
| 代码可定位       | 每个代码片段都有文件路径和行号        |
| 层级清晰         | Layer 1/2/3/4 与实际架构一致          |
| 无臆测内容       | 所有内容都可追溯到真实代码            |

### Phase 3: 创建 References 目录

```
任务：将原始 skill 归档为参考文档

1. 创建 references 目录：
   → .claude/skills/{新skill名称}/references/

2. 读取每个原始 skill 的完整 SKILL.md：
   → 读取原始文件内容
   → 保持原有结构不变
   → 在文件开头添加 reference frontmatter

3. 写入归档文件：
   → references/{原始skill名称}.md
   → frontmatter 添加：name: {原始名}-reference, description: Reference — {描述}

4. 在主文档末尾添加"参考资料"章节：
   → 说明原始文档归档位置
   → 列表形式展示：文件名 → 内容描述
```

**Phase 3 质量检查**：

| 检查项                | 通过标准                          |
| --------------------- | --------------------------------- |
| references 目录存在   | .claude/skills/{name}/references/ |
| 所有原始 skill 已归档 | 数量与合并的 skill 数量一致       |
| frontmatter 正确      | 每个归档文件有 reference name     |
| 主文档有参考章节      | "参考资料" 章节在文档末尾         |

### Phase 4: 删除原始 Skill

```
任务：清理被合并的原始 skill

1. 最终确认：
   → references/ 中所有原始 skill 已完整归档
   → 新 skill 主文档已验证无误

2. 删除原始 skill 目录：
   → 使用 rm -rf 命令删除整个目录
   → 包括 SKILL.md 和所有子目录

3. 验证删除成功：
   → Glob 确认原始目录不存在
   → 新 skill 目录完整存在
```

**Phase 4 质量检查**：

| 检查项          | 通过标准                               |
| --------------- | -------------------------------------- |
| references 完整 | 所有原始 skill 内容都在 references/ 中 |
| 删除成功        | 原始目录不存在于 .claude/skills/       |
| 新 skill 可用   | 主文档可正常读取                       |
| 目录结构正确    | 只有 SKILL.md 和 references/           |

---

## 文件索引模板

每个合并后的 skill 必须包含文件索引：

```markdown
## 文件索引（与文档对应的真实代码）

| 文档章节 | 对应文件 |
|---------|---------|
| Layer 1 | `content/videoTracker.js` |
| Layer 2 | `content/content.js` |
| Layer 3 | `background/videoProgress.js` |
| Layer 3 normalizeUrl | `background/utils.js` |
| Layer 4 Popup UI | `popup/modules/videoProgress.js` |
| Layer 4 Popup 捕获 | `popup/modules/videoCapture.js` |
| Layer 4 完整页面 | `modules/video-progress/view.js` |
| Layer 4 进度工具 | `modules/video-progress/progress-utils.js` |
| Layer 4 HTML | `modules/video-progress/video-progress.html` |
```

---

## References 章节模板

```markdown
## 参考资料

原始 skill 文档（已归档至 `references/` 目录）：

| 文件 | 内容 |
|------|------|
| `references/spa-video-detection.md` | SPA 路由感知三层防护架构原始版本 |
| `references/video-progress-tracker.md` | 视频课程进度追踪完整实现原始版本 |

**说明**：主文档基于真实代码重新编写，合并了两个原始 skill 的核心概念，并更正了与实际代码的差异。原始文档保留作为历史参考。
```

---

## MEMORY.md 更新

```markdown
- [新skill名称](新skill名称/SKILL.md) — 简短描述（含 references/ 说明）
```

---

## 详细操作步骤

### Phase 1: 阅读真实代码

```
Step 1.1: 确定代码文件
  → Glob {pattern: "**/*video*"}  搜索相关代码
  → Grep "videoTracker|video-progress" manifest.json 确认入口

Step 1.2: 读取代码
  → Read content/videoTracker.js  (Layer 1)
  → Read content/content.js        (Layer 2)
  → Read background/videoProgress.js (Layer 3)
  → Read modules/video-progress/view.js (Layer 4 前端)

Step 1.3: 对比 skill 文档
  → Read 原skill1/SKILL.md
  → Read 原skill2/SKILL.md
  → 逐函数对比：实现 vs 文档

Step 1.4: 记录差异
  → 列出：函数名/参数/流程 不一致处
  → 决定：修正原文档 或 在新文档标注
```

### Phase 2: 创建主文档

```
Step 2.1: 创建目录
  → Bash: mkdir -p .claude/skills/{新skill名称}/references/

Step 2.2: 编写 SKILL.md
  → Write .claude/skills/{新skill名称}/SKILL.md
  → 包含：frontmatter + Overview + 各层实现 + 文件索引

Step 2.3: 代码片段标注
  → 每个代码块标注来源：
     ```javascript
     // content/videoTracker.js:44-72
     ```
```

### Phase 3: 创建 references

```
Step 3.1: 读取原始 skill
  → Read 原skill1/SKILL.md
  → Read 原skill2/SKILL.md

Step 3.2: 写入归档
  → Write references/原skill1.md (加 reference frontmatter)
  → Write references/原skill2.md (加 reference frontmatter)

Step 3.3: 添加参考章节
  → Edit 主文档末尾添加 "## 参考资料" 章节
```

### Phase 4: 删除原始

```
Step 4.1: 验证归档
  → Read references/原skill1.md 确认完整
  → Read references/原skill2.md 确认完整

Step 4.2: 删除
  → Bash: rm -rf .claude/skills/原skill1
  → Bash: rm -rf .claude/skills/原skill2

Step 4.3: 验证
  → Glob .claude/skills/原skill1  确认不存在
  → Glob .claude/skills/新skill  确认存在
```

---

## 质量检查清单

### Phase 1 完成标准

- [ ] 所有相关代码文件已通读
- [ ] 差异清单已记录（代码 vs 原始 skill）
- [ ] 发现的不符之处已标注或修正

### Phase 2 完成标准

- [ ] 新 skill 目录已创建
- [ ] frontmatter: name + description 完整
- [ ] description 以 "Use when..." 开头
- [ ] 包含文件索引表（文档章节 → 真实代码文件）
- [ ] 代码示例与真实代码完全一致
- [ ] 每个代码片段有文件路径和行号引用

### Phase 3 完成标准

- [ ] references/ 目录已创建
- [ ] 所有原始 skill 已归档（内容完整）
- [ ] 每个归档文件有 reference frontmatter
- [ ] 主文档末尾有"参考资料"章节
- [ ] MEMORY.md 已更新

### Phase 4 完成标准

- [ ] 原始 skill 目录已删除
- [ ] 验证删除成功（Glob 确认）
- [ ] 新 skill 可正常加载

---

## 常见错误

| 错误                    | 后果           | 正确做法               |
| ----------------------- | -------------- | ---------------------- |
| 不读代码直接拼接        | 文档与实现脱节 | 先通读相关代码文件     |
| 删除原始 skill 前未归档 | 历史版本丢失   | references/ 完整后再删 |
| 文件索引不完整          | 读者找不到代码 | 列出所有涉及的代码文件 |
| 复制粘贴不做验证        | 错误示例误导   | 代码必须来自真实文件   |

---

## 与 key_board_3 主流程的衔接

key_board_3 主 SKILL.md 负责**结构判断**（是否要拆、拆到哪个 ref），本 ref 负责**动手合并时的执行细节**。

调用顺序：

1. 先走 key_board_3 主流程 → 判断要"合并"是个特殊优化场景
2. 加载本文档 → 获得 4 阶段合并流程
3. 合并过程中**仍要遵循 key_board_3 的核心原则**：不创建 skill（这次创建新 skill 是合并的副产品）、不修改前置 skill、主 SKILL.md < 500 行

注意：本 ref 中的"创建新 skill"指的是**合并产生的新 skill**，不是 key_board_3 的本职动作。