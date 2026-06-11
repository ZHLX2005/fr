---
name: project-index-reader-v2
description: 当用户要求分析仓库、生成技术文档或学习某个项目实现时，从 .claude/repo/ 仓库中读取源码并生成结构化技术文档。禁止立即编码。此 skill 仅适用于 .claude/repo/ 下的仓库。
version: 2.0.0
---
# 仓库源码阅读与技术文档生成器

## 核心原则

**先读索引，再挖源码，后出文档**。生成文档前必须先从源码中提取具体证据。

所有对话 必须按照知识主题 进行md文档的落盘

## 工作流程

### Step 1: 定位目标仓库

在 `.claude/repo/` 下查找用户要求的项目：

```bash
ls .claude/repo/
```

若仓库不存在，提示用户先通过 `/mmx-research-gitclone` 克隆。

### Step 2: 扫描仓库索引

读取目标仓库的 `PROJECT_INDEX.md` 快速了解整体结构：

```
Read: .claude/repo/<仓库名>/PROJECT_INDEX.md
```

提取关键信息：

- 项目定位与核心功能
- 主要包/模块划分
- 入口文件位置
- 技术栈

### Step 3: 规划文档结构

根据仓库类型和用户需求，自由决定需要生成的文档主题和数量。一个仓库可生成多份文档，不局限于一份。

**输出位置（强制）**：

```
.claude/repo/_read/<仓库名>/<文档主题>/<文档文件名>.md
```

例如：

```
.claude/repo/_read/happy/架构总览/01-项目架构与模块关系.md
.claude/repo/_read/happy/核心模块/happy-cli-入口与命令解析.md
.claude/repo/_read/happy/核心模块/happy-server-API与路由设计.md
.claude/repo/_read/happy/数据流/端到端加密同步机制.md
```

规划原则：

- 结合用户问题和仓库特点确定分析角度，不要套用固定模板
- 大型仓库（>5个包）至少拆分为 2-3 个主题目录
- 小型仓库可集中在一个主题下
- 主题目录名使用中文，文件编号用于排序

### Step 4: 深入源码提取证据

**真实性铁律**：文档中的每一句话都必须能在源码中找到对应证据。禁止推断、猜测、编造。

挖掘方式：

```
# 读取核心入口文件
Read: .claude/repo/<仓库名>/<入口文件>

# 搜索关键接口定义
Grep: interface|type|class|struct|func.*\(.*\).*

# 搜索方法签名
Grep: func \w+|function \w+|method \w+|async \w+

# 读取关键数据结构
Read: .claude/repo/<仓库名>/<核心数据定义文件>
```

**证据引用格式（强制）**：

所有涉及源码的描述必须包含：

1. 文件路径（相对于仓库根目录）
2. 行号范围（如 `:23` 或 `:45-67`）
3. 原始代码片段

```markdown
- `AuthService` 接口定义了认证核心方法：
  ```typescript
  // 来源: packages/auth/src/service.ts:23-29
  interface AuthService {
    authenticate(credentials: Credentials): Promise<AuthResult>;
    refreshToken(token: string): Promise<string>;
  }
```

```

**禁止行为**：
- 描述一个接口但不提供源码位置和代码片段
- 声称"项目使用了 X 设计模式"而不引用体现该模式的源码
- 描述函数行为但不引用函数体或签名
- 对未读到的文件做任何假设性描述

**追溯原则**：如果读者对文档中的某个结论有疑问，应该能根据文档中给出的文件路径和行号，直接定位到源码并验证。

### Step 5: 生成技术文档

**输出目录（强制）**：`.claude/repo/_read/<仓库名>/<文档主题>/`

生成前必须确保目标目录已创建：
```bash
mkdir -p .claude/repo/_read/<仓库名>/<文档主题>
```

文档撰写原则：

1. **中文撰写**：全文使用中文
2. **源码证据优先（强制）**：涉及接口、类型、函数时，必须引用源码中的具体定义（含文件路径和行号范围）。没有源码证据的结论不得写入文档
3. **真实可追溯**：文档中的每一句话都应该能让读者根据给出的文件路径和行号，在源码中找到对应内容并验证。禁止推断、猜测、编造
4. **自由分析**：结合用户需求和仓库特点进行分析，不套用固定模板。可以包含架构分析、数据流追踪、设计决策评价、核心算法解释等——但所有分析结论都必须有源码支撑
5. **结构化**：使用 Markdown 标题层级组织，但具体结构由分析角度决定

**示例输出路径**：

```
.claude/repo/_read/happy/架构总览/01-项目架构与模块关系.md
.claude/repo/_read/happy/核心模块/happy-cli-入口与命令解析.md
.claude/repo/_read/happy/核心模块/happy-server-API与路由设计.md
.claude/repo/_read/happy/数据流/端到端加密同步机制.md
```

### Step 6: 验证与汇总

生成完成后必须执行以下验证：

1. **验证输出位置**：确认文件确实存在于 `.claude/repo/_read/<仓库名>/<文档主题>/` 下，**不是仓库根目录，也不是其他位置**
2. **检查源码引用**：每个涉及接口/类型/函数的结论都有源码依据
3. **汇总汇报**：向用户列出所有生成的文档路径

验证命令：

```bash
find .claude/repo/_read/<仓库名>/ -type f -name "*.md" | sort
```

## 寻找指令速查

```
# 列出所有仓库
Bash: ls .claude/repo/

# 读取索引
Read: .claude/repo/<repo>/PROJECT_INDEX.md

# 搜索接口/类型
Grep: ^\s*(interface|type|struct|class)\s+\w+

# 搜索函数定义
Grep: ^\s*(func|function|def|async)\s+\w+

# 读取特定文件
Read: .claude/repo/<repo>/<path>
```

## 适用场景

✅ 分析开源项目实现细节
✅ 为团队生成技术参考文档
✅ 学习特定技术方案的内部机制
✅ 提取接口设计作为新项目的参考

❌ 简单文件操作
❌ 用户已指定单个文件
❌ 不依赖源码的通用性说明
