---
name: index-repos
description: |
  使用 subagent 并行机制为多个仓库创建 PROJECT_INDEX.md 和 PROJECT_INDEX.json。
  当用户需要为多个独立仓库同时创建索引时自动触发。
  触发场景：
  - "为 .claude/repo 下所有仓库创建索引"
  - "并行执行 index skill"
  - "批量创建仓库索引"
  - /sc:index-repo 命令但有多个仓库
type: workflow
---
# 请加载 /sc:index-repo 这个 skill !!!!!!!!!

处理 {当前项目}/.claude/repo 当中的项目,每个项目隔离

检查不存在 PROJECT_INDEX.md 和 PROJECT_INDEX.json 的仓库,对于没有 index 的仓库进行并发 /sc:index-repo

system: 排除 _read 目录,这个目录用于存放一些专门的参考分析代码,不需要进行处理

> **⚠️ 重要提醒:`.claude/repo/` 下的仓库通常被 `.gitignore` 排除,git 工具无法获取这些文件。**
>
> 检查仓库列表时必须使用**直接的文件系统工具**:
>
> - `Bash: ls .claude/repo/`
> - `PowerShell: Get-ChildItem .claude/repo/`
> - `Glob: .claude/repo/*`
>
> **不要使用** `git ls-files`、`git status` 或任何依赖 git 索引的命令。

---

# Index Repos - 多仓库并行索引创建(实战版)

## 工作流总览

```
1. 扫描 .claude/repo/ 列出所有仓库(排除 _read)
2. 过滤出缺少 PROJECT_INDEX.md 或 PROJECT_INDEX.json 的仓库
3. 为每个待索引仓库启动一个并行 subagent(general-purpose + run_in_background: true)
4. 每个 subagent 加载 sc:index-repo skill,独立完成该仓库的索引创建
5. 主流程等待所有 subagent 完成,验证文件存在
```

---

## Step 1: 扫描仓库列表

```bash
ls -la .claude/repo/ | grep -v "_read" | awk 'NR>1 && $9 != "" && $9 != "." && $9 != ".." {print $9}'
```

## Step 2: 过滤需要创建索引的仓库

```bash
cd .claude/repo && for dir in */; do
  dir="${dir%/}"
  [ "$dir" = "_read" ] && continue
  if [ -f "$dir/PROJECT_INDEX.md" ] && [ -f "$dir/PROJECT_INDEX.json" ]; then
    echo "SKIP: $dir (已有索引)"
  else
    echo "TODO: $dir"
  fi
done
```

输出形如:

```
SKIP: <repo_a> (已有索引)
TODO: <repo_b>
TODO: <repo_c>
...
```

## Step 3: 加载 sc:index-repo skill(关键)

主流程在启动 subagent **之前**必须先调用 `Skill` 工具加载 `sc:index-repo` skill,让主会话缓存该 skill 的执行规范(并行 5 阶段分析、模板结构等),后续 subagent 可直接沿用。

```
Skill(skill="sc:index-repo")
```

**注意**:实际测试发现,subagent 会自动加载该 skill(因为 `subagent_type: "general-purpose"` 会继承已加载 skill 的指令),但显式加载能让主流程也清楚索引的规范要求。

## Step 4: 并行启动 subagent(核心)

将"待索引仓库"列表转换为**多个 `Agent` 工具调用**。**所有 Agent 必须在同一个消息中并行发起**(系统会自动并发调度)。

```python
# 伪代码示意:实际中每个 Agent 写在独立的 tool_use 块
# 关键参数:
#   - run_in_background: true  → 真正并行
#   - subagent_type: "general-purpose"  → 拥有完整工具集
#   - name: "index-<repo>"  → 方便后续追踪

Agent(
  description="Index <repo_name> repo",
  prompt="""
为仓库 `<绝对路径>` 创建 PROJECT_INDEX.md 和 PROJECT_INDEX.json。

要求:
1. 读取 README.md 了解项目概述
2. 使用 Glob 和 Read 分析目录结构(分多个并发搜索:代码、文档、配置、测试、脚本)
3. 识别核心模块和入口点
4. 生成 PROJECT_INDEX.md(< 5KB,人类可读)
5. 同时生成 PROJECT_INDEX.json(机器可读)
6. 完成后简要报告两个文件的路径和大小

输出到:
- `<绝对路径>/PROJECT_INDEX.md`
- `<绝对路径>/PROJECT_INDEX.json`

⚠️ 必须使用绝对路径,因为 subagent 的工作目录可能与主流程不一致。
""",
  subagent_type="general-purpose",
  run_in_background=true,
  name="index-<repo_name>"
)
```

**为什么要绝对路径?**
主流程的 `cd` 状态在某些场景下会持久化到后续 bash 调用,subagent 如果沿用相对路径,可能写入错误位置。

## Step 5: 等待完成并验证

subagent 完成后,系统会发送 `task-notification`。主流程**不读取** subagent 的 .output 文件(那会爆 context),而是直接验证产物:

```bash
# 切换回主项目根目录(防 cd 状态污染)
cd <项目根绝对路径>

# 逐个验证文件存在与大小
for repo in <repo1> <repo2> ...; do
  md=".claude/repo/$repo/PROJECT_INDEX.md"
  json=".claude/repo/$repo/PROJECT_INDEX.json"
  md_size=$(wc -c < "$md" 2>/dev/null || echo "MISSING")
  json_size=$(wc -c < "$json" 2>/dev/null || echo "MISSING")
  printf "%-15s MD=%-7s JSON=%-7s\n" "$repo" "${md_size}B" "${json_size}B"
done
```

期望输出(具体大小因仓库而异):

```
<repo1>           MD=<size>B   JSON=<size>B
<repo2>           MD=<size>B   JSON=<size>B
...
```

最后做一次全量统计,确保 0 缺索引:

```bash
total=0; missing=0
for dir in .claude/repo/*/; do
  dir="${dir%/}"
  name=$(basename "$dir")
  [ "$name" = "_read" ] && continue
  total=$((total+1))
  if [ -f "$dir/PROJECT_INDEX.md" ] && [ -f "$dir/PROJECT_INDEX.json" ]; then
    :
  else
    missing=$((missing+1))
    echo "✗ $name"
  fi
done
echo "总仓库: $total | 缺索引: $missing"
```

---

## 完整可复用 Script 模板

下面是一份**实际可执行**的脚本,可作为未来执行的起点:

```bash
#!/usr/bin/env bash
# index_repos.sh - 批量为 .claude/repo/ 下缺少索引的仓库创建 PROJECT_INDEX
# 用法: 由 Claude 主流程在扫描后,逐个启动 subagent 调用 sc:index-repo

set -e
REPO_ROOT="${REPO_ROOT:-<项目根绝对路径>}"
REPO_DIR="$REPO_ROOT/.claude/repo"

# Step 1: 列出待索引仓库
cd "$REPO_DIR"
TODO=()
for dir in */; do
  dir="${dir%/}"
  [ "$dir" = "_read" ] && continue
  if [ ! -f "$dir/PROJECT_INDEX.md" ] || [ ! -f "$dir/PROJECT_INDEX.json" ]; then
    TODO+=("$dir")
  fi
done

if [ ${#TODO[@]} -eq 0 ]; then
  echo "所有仓库均已有索引,无需处理"
  exit 0
fi

echo "需要创建索引的仓库 (${#TODO[@]}):"
printf '  - %s\n' "${TODO[@]}"

# Step 2-3: Claude 主流程根据 $TODO 列表,
# 为每个仓库发起一个并行的 Agent tool_use,
# 传入绝对路径 $REPO_ROOT/.claude/repo/<name>
```

---


## 经验总结

### ✓ 成功要点

1. **同消息多 Agent 并行**:所有 `Agent` 工具调用必须在**同一条消息**中发出,系统会并发调度,否则变成串行。
2. **`run_in_background: true`**:让 Agent 真正异步运行,主流程不阻塞。
3. **绝对路径**:`prompt` 中写入目标仓库必须用绝对路径,subagent 不会继承主流程的 `cd` 状态。
4. **小仓库可省略模板指令**:对 < 10 文件的极小仓库,subagent 自己知道要读什么;大仓库需要在 prompt 中明确"分多个并发 Glob"。
5. **产物即收据**:subagent 完成后无需读取其 .output 文件,直接 `wc -c` 验证文件存在与大小即可。
6. **5KB 上限可弹性**:略超 5KB 仍可接受,完整性优先。

### ⚠️ 错误教训

1. **git 工具看不到被 .gitignore 排除的仓库**:`git ls-files`、`git status` 会误判目录为空。必须用 `ls`、`Glob`、`Get-ChildItem`。
2. **Bash 的 `cd` 状态可能持久化**:跨多个 Bash 调用时,有时上一次的 `cd` 会延续。**永远用绝对路径**,或在每个 Bash 调用前显式 `cd` 复位。
3. **混合 PowerShell 与 Bash 语法**:PowerShell 5.1 不支持 `&&` / `||` 链式、Bash 不支持 `if (...) { }`。在 Windows 上**默认用 bash 工具**写脚本。
4. **SSH clone 失败回退 HTTPS**:某些仓库首次 clone 时 git 默认走 SSH 失败,需 `git -c "url.https://github.com/.insteadOf=git@github.com:" clone ...` 强制 HTTPS。
5. **subagent 的 .output 文件不能 Read**:那是完整 JSONL 转录,读取会爆 context。**只看 task-notification 摘要**。
6. **跨会话历史不可用**:新会话无法访问之前 subagent 的具体输出,关键结果必须写到共享文件(本例即 PROJECT_INDEX.{md,json})。
7. **大仓库 vs 小仓库 prompt 区别**:大仓库需在 prompt 中显式要求"分多个并发 Glob",小仓库直接说"读 README 和核心源文件"即可。

---

## 索引文件结构(sc:index-repo skill 定义)

每个仓库生成两个文件:

### PROJECT_INDEX.md (人类可读,目标 < 5KB)

```markdown
# Project Index: {project_name}

Generated: {timestamp}

## 📁 Project Structure
{tree view of main directories}

## 🚀 Entry Points
- CLI: {path} - {description}
- API: {path} - {description}
- Tests: {path} - {description}

## 📦 Core Modules
### Module: {name}
- Path: {path}
- Exports: {list}
- Purpose: {1-line description}

## 🔧 Configuration
## 📚 Documentation
## 🧪 Test Coverage
## 🔗 Key Dependencies
## 📝 Quick Start
```

### PROJECT_INDEX.json (机器可读,无明确大小限制)

结构化数据,供后续脚本消费。

---

## 相关 Skill

- **`sc:index-repo`** - 单个仓库索引创建,定义 4 阶段流程(并行 Glob → 提取元数据 → 生成索引 → 验证)
- **`subagent-driven-development`** - 通用并行 subagent 调度模式

## 参考命令

```bash
# 完整执行一遍
cd <项目根绝对路径>
ls .claude/repo/  
for dir in .claude/repo/*/; do
  dir="${dir%/}"; name=$(basename "$dir")
  [ "$name" = "_read" ] && continue
  [ -f "$dir/PROJECT_INDEX.md" ] && [ -f "$dir/PROJECT_INDEX.json" ] || echo "TODO: $name"
done
```
