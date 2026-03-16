---
name: git-worktree-sync
description: 同步所有 git worktree 工作树。当用户提到"同步工作树"、"同步所有分支"、"git worktree 同步"、"变基同步"、"worktree rebase"、"分支同步"、"合并所有分支"或类似的 git 同步相关操作时触发此技能。此技能会将各个 worktree 的变更合并到主分支，然后主分支再扇出到其他功能分支，优先使用变基，自动处理冲突并保证编译成功，同时记录冲突处理细节到文档。
---

# Git Worktree 同步技能

这个技能帮助你同步所有 git worktree 工作树，将各个功能分支的变更安全地合并到主分支，然后从主分支扇出到其他分支。整个过程优先使用变基(rebase)，智能处理冲突，验证编译成功，并生成详细的冲突处理文档。

**注意**：此技能仅处理本地 worktree 同步，不涉及远程仓库操作。

---

## 工作流程

### 第一阶段：信息收集

#### 1. 列出所有 worktree

```bash
git worktree list
```

从输出中提取每个 worktree 的路径和分支名称。

#### 2. 检测主分支名称

```bash
git branch -a | grep -E "(main|master|develop)"
git log --oneline --all --graph | head -20
```

常见主分支名称：`main`、`master`、`develop`。选择仓库约定的主分支。

#### 3. 检测构建工具

通过检查项目根目录的配置文件来识别：

| 配置文件 | 构建工具 | 构建命令 |
|---------|---------|---------|
| `Cargo.toml` | cargo | `cargo build --release` |
| `package.json` + `package-lock.json` | npm | `npm run build` |
| `package.json` + `yarn.lock` | yarn | `yarn build` |
| `package.json` + `pnpm-lock.yaml` | pnpm | `pnpm run build` |
| `pom.xml` | maven | `mvn clean package -DskipTests` |
| `build.gradle` / `build.gradle.kts` | gradle | `./gradlew build -x test` 或 `gradle build -x test` |
| `Makefile` | make | `make` |
| `CMakeLists.txt` | cmake | `cmake -B build && cmake --build build` |
| `go.mod` | go | `go build ./...` |
| `pyproject.toml` (含 `[tool.poetry]`) | poetry | `poetry build` |
| `requirements.txt` | pip | 无构建步骤，仅需 `pip install` |

检测方法：
```bash
ls -la | grep -E "Cargo.toml|package.json|pom.xml|build.gradle|Makefile|CMakeLists.txt|go.mod|pyproject.toml"
```

对于 `package.json`，检查 `scripts` 字段中是否有 `build` 命令。

#### 4. 收集每个 worktree 的状态

对每个 worktree 执行：

```bash
cd <worktree-path>
git status --porcelain
git log --oneline -10
git log <main-branch>..HEAD --oneline  # 与主分支的差异
git diff <main-branch>...HEAD --stat
```

---

### 第二阶段：变更分析与评估

对每个有变更的 worktree：

#### 分析变更内容

```bash
# 查看提交图
git log --oneline --graph --all

# 查看与主分支的文件差异
git diff <main-branch>...HEAD --name-only

# 查看具体变更
git diff <main-branch>...HEAD
```

#### 识别变更类型

通过分析变更的文件和内容：

- **新功能添加**：新增文件为主，新增函数/模块
- **Bug 修复**：修改现有文件，commit message 包含 fix/bug
- **重构**：文件移动/重命名，代码结构调整但功能不变
- **文档更新**：只修改 `.md`、`.txt`、`docs/` 等文件
- **依赖变更**：修改 `Cargo.toml`、`package.json`、`pom.xml` 等

#### 评估影响范围

分析：
- 受影响的模块/文件列表
- 可能与哪些其他分支产生冲突
- 是否有破坏性变更（API 变更、依赖版本变化）

---

### 第三阶段：主分支同步（扇入）

**核心原则：主分支必须始终保持可编译状态。每个分支合并前和合并后都要验证编译，只有编译成功才继续。**

#### 步骤 0：验证主分支初始状态（必须）

在任何合并操作之前，必须确认主分支当前可以编译：

```bash
cd <main-worktree-path>
git checkout <main-branch>

# 确保工作区干净
git status --porcelain
# 如果有未提交更改，提示用户处理

# 验证编译
<build-command>
```

**如果主分支初始编译失败**：
- 停止同步流程
- 记录错误到文档
- 提示用户先修复主分支的编译问题
- 不进行任何合并操作

只有主分支初始编译成功，才继续后续步骤。

#### 步骤 1：定位主 worktree

```bash
# 找到主分支所在的 worktree
git worktree list | grep <main-branch>
```

#### 步骤 2：对每个功能分支执行变基

```bash
cd <feature-worktree-path>
git rebase <main-branch>
```

如果遇到冲突，参见冲突处理章节。冲突解决后，必须验证该分支可以编译：

```bash
<build-command>
```

**如果功能分支变基后编译失败**：
- 尝试修复编译错误
- 如果无法修复，中止该分支的合并：
  ```bash
  git rebase --abort
  ```
- 记录失败原因到文档
- 跳过该分支，继续处理下一个分支

#### 步骤 3：将变基后的分支合并到主分支

```bash
cd <main-worktree-path>
git merge --no-ff <feature-branch> -m "Merge <feature-branch> into <main-branch>"
```

#### 步骤 4：验证合并后的编译（必须）

```bash
# 立即验证编译
<build-command>
```

**如果编译失败**：
1. 立即回滚本次合并：
   ```bash
   git reset --hard HEAD~1
   ```
2. 记录失败原因到文档：
   - 合并的分支名称
   - 编译错误详情
   - 可能的冲突点
3. 继续处理下一个分支（主分支仍保持可编译状态）

**只有编译成功**，才记录该分支同步成功，然后继续处理下一个分支。

#### 步骤 5：记录成功的合并

每个成功合并的分支都记录到临时文档中，包含：
- 分支名称
- 合并时间
- 提交数量
- 编译验证结果

---

### 第四阶段：扇出到其他分支

主分支更新后，将更改同步到其他 worktree：

```bash
cd <other-worktree-path>
git rebase <main-branch>
```

处理冲突（如有），然后验证每个 worktree 的编译。

---

### 第五阶段：生成文档

在仓库根目录创建日志目录并生成报告：

**目录**：`<repo-root>/.worktree-sync-logs/`
**文件名**：`YYYY-MM-DD_HH-mm-ss.md`

---

## 冲突处理策略

**核心原则：优先自动解决冲突，只有无法合理解决时才提示用户。每次冲突解决过程必须完整记录到文档。**

### 冲突检测

当 rebase 遇到冲突时：

```bash
# 查看冲突状态
git status

# 列出冲突文件
git diff --name-only --diff-filter=U
```

### 冲突解决工作流

#### 1. 识别所有冲突文件

```bash
git diff --name-only --diff-filter=U
```

对每个冲突文件，执行以下解决流程。

#### 2. 读取并分析冲突

```bash
# 查看冲突内容
cat <conflicted-file>

# 获取双方的版本
git show :2:<file>  # HEAD 版本（当前分支）
git show :3:<file>  # MERGE_HEAD 版本（来源分支）

# 查看冲突双方的提交信息
git log --oneline -1 HEAD
git log --oneline -1 MERGE_HEAD
```

**开始记录冲突解决过程**：在临时文件中记录当前时间、冲突文件、双方变更内容。

#### 3. 根据冲突类型自动解决

**代码逻辑冲突**：
- 分析双方代码的意图和功能
- 理解每个变更的业务逻辑
- 尝试合并双方的合理修改
- 如果功能冲突，选择更完整/更合理的版本
- 必要时重构代码以兼容双方

**配置文件冲突**（JSON/YAML/TOML）：
```bash
# 读取两个版本的配置
# 合并所有键值对，保留双方的配置项
# 如果键冲突，分析哪个值更合理
```

**依赖文件冲突**：
- `package.json`：合并 dependencies，版本冲突时取兼容版本
- `Cargo.toml`：合并依赖项，保留 features 并集
- `pom.xml`：合并依赖声明

**自动生成文件冲突**（如 lock 文件）：
```bash
# 删除冲突文件，重新生成
rm <lock-file>
npm install  # 或 cargo build 等
```

**纯文本/文档冲突**：
- 合并双方的文字修改
- 如果修改同一段落，尝试理解语义并合并

#### 4. 编写解决后的文件

```bash
# 使用 Write 或 Edit 工具写入解决后的内容
# 确保文件中不再有 <<<<<<< HEAD 标记
```

#### 5. 标记冲突已解决

```bash
git add <resolved-file>
```

#### 6. 记录解决过程

在临时文件中追加：
```
解决策略：<描述如何分析和解决的>
解决结果：<最终保留的逻辑/代码片段>
验证方法：<如何确认解决正确>
```

#### 7. 继续 rebase

```bash
git rebase --continue
```

如果有更多冲突，重复步骤 1-7。

### 冲突解决详细示例

#### 示例 1：函数签名冲突

**冲突内容**：
```rust
// HEAD (main 分支)
fn process_data(data: Vec<u8>) -> Result<Data, Error> {
    // ...
}

// MERGE_HEAD (feature 分支)
fn process_data(data: &[u8]) -> Result<Data, Error> {
    // ...
}
```

**分析**：
- main 分支改为 `Vec<u8>` 参数
- feature 分支改为 `&[u8]` 切片参数

**解决策略**：
- `&[u8]` 更灵活，可以接受 `Vec` 的切片
- 但 main 的实现可能依赖 `Vec` 的所有权
- 检查函数体实现，选择兼容方案

**解决结果**：
```rust
fn process_data(data: &[u8]) -> Result<Data, Error> {
    // 合并 feature 的函数体，适配切片参数
    let owned_data = data.to_vec();
    // ... 使用 owned_data
}
```

**记录**：
```
冲突文件：src/processor.rs
冲突类型：代码逻辑冲突 - 函数签名
我们的变更：使用 Vec<u8> 参数
他们的变更：使用 &[u8] 切片参数
解决策略：采用切片参数（更灵活），内部转换
解决结果：保留切片参数，内部适配
验证：cargo build 成功
```

#### 示例 2：配置合并冲突

**冲突内容**（config.toml）：
```toml
# HEAD (main 分支)
[database]
host = "localhost"
port = 5432

[cache]
enabled = false

# MERGE_HEAD (feature 分支)
[database]
host = "db.internal"
port = 5433
timeout = 30

[logging]
level = "debug"
```

**解决策略**：
- 数据库配置：feature 分支使用生产环境地址，保留
- cache 配置：main 分支禁用了缓存，保留
- logging 配置：feature 分支新增，保留

**解决结果**：
```toml
[database]
host = "db.internal"
port = 5433
timeout = 30

[cache]
enabled = false

[logging]
level = "debug"
```

**记录**：
```
冲突文件：config.toml
冲突类型：配置文件冲突
解决策略：合并双方配置项，保留所有唯一键
解决结果：完整合并所有配置节
```

### 仅在以下情况提示用户

1. **语义冲突无法判断**：双方修改同一逻辑，无法确定哪个正确
2. **依赖版本不兼容**：两个版本存在破坏性变更，无法自动选择
3. **大型重构冲突**：整个模块被重写，无法简单合并
4. **安全相关冲突**：涉及认证、权限等敏感代码

即使需要用户介入，也要：
1. 先尝试部分解决，减少用户工作量
2. 清晰记录冲突点和建议方案
3. 在文档中标注"需用户确认"

### 冲突处理文档记录

每解决一个冲突，记录以下信息到临时文件，最后汇总到报告：

```
冲突文件：<文件路径>
时间：<时间戳>
分支：<功能分支> → <主分支>
冲突类型：<代码/配置/依赖/其他>

我们的变更：
- <描述变更内容和原因>

他们的变更：
- <描述变更内容和原因>

影响评估：
- 受影响模块：<模块列表>
- 潜在风险：<风险评估>

解决策略：<描述采用的解决方式>
解决结果：<最终保留的代码逻辑>
```

---

## 文档输出格式

同步完成后生成 Markdown 报告：

```markdown
# Git Worktree 同步报告

**执行时间**：<开始时间> - <结束时间>
**主分支**：<main/master/develop>
**参与同步的分支**：<分支列表>

---

## 主分支编译状态追踪

| 检查点 | 状态 | 备注 |
|--------|------|------|
| 初始状态 | ✓ 成功 | 主分支在同步开始前可编译 |
| 合并 feature-a 后 | ✓ 成功 | - |
| 合并 feature-b 后 | ✓ 成功 | - |
| 最终状态 | ✓ 成功 | 主分支始终保持可编译 |

**保护机制**：每次合并后立即验证编译，失败则自动回滚，确保主分支始终可用。

---

## 同步概览

| 分支 | 变更提交数 | 冲突数 | 编译状态 | 合并结果 |
|------|-----------|--------|----------|----------|
| feature-a | 3 | 1 | ✓ 成功 | ✓ 已合并 |
| feature-b | 5 | 0 | ✓ 成功 | ✓ 已合并 |
| feature-c | 2 | 0 | ✗ 失败 | ✗ 已跳过 |

**跳过分支详情**（如有）：
- `feature-c`：合并后编译失败，已回滚
  - 错误：类型不匹配 `src/utils.rs:45`
  - 建议：手动检查 API 变更

---

## 详细变更记录

### 分支：feature-a

**变更概述**：添加用户认证功能

**变更文件**：
- `src/auth/login.rs` (新增, +120 行)
- `src/auth/token.rs` (新增, +85 行)
- `src/main.rs` (修改, +15/-3 行)

**提交列表**：
- `a1b2c3d` - feat(auth): add login module
- `e4f5g6h` - feat(auth): add token validation
- `i7j9k0l` - refactor: integrate auth into main

**冲突处理**：共 2 个冲突，已全部自动解决（详见下方）

---

### 分支：feature-b

**变更概述**：优化数据库查询

**变更文件**：
- `src/db/queries.rs` (修改, +45/-12 行)
- `src/models/user.rs` (修改, +8/-2 行)

**提交列表**：
- `m2n3o4p` - perf(db): optimize user queries

**冲突处理**：无冲突

---

## 冲突处理详情

### 冲突 1：src/main.rs（来自 feature-a）

**时间**：2024-01-15 14:32:00
**冲突类型**：代码逻辑冲突

#### 原始冲突内容

```rust
// <<<<<<< HEAD (main 分支)
fn main() {
    config::load();
    // <<<<<<< feature-a
    logging::init();
    // =======
    database::connect();
    // >>>>>>> main
    run_app();
}
// =======
// >>>>>>> feature-a
```

#### 变更详情

**我们的变更（feature-a 分支）**：
- 在 main 函数中添加日志初始化
- 位置：config::load() 之后
- 原因：需要先加载配置才能正确初始化日志

**他们的变更（main 分支）**：
- 在 main 函数中添加数据库连接
- 位置：config::load() 之后
- 原因：新功能需要数据库支持

#### 影响评估

- 受影响模块：应用启动流程
- 潜在风险：初始化顺序可能影响日志记录数据库连接事件
- 依赖关系：logging 和 database 模块无直接依赖

#### 解决过程

1. 分析双方代码意图：
   - logging::init() 需要配置信息
   - database::connect() 也需要配置信息
   - 两者无依赖关系

2. 确定解决策略：
   - 保留双方修改
   - 调整顺序：先日志后数据库
   - 原因：可以在数据库连接时记录日志

3. 编写解决代码

#### 解决结果

```rust
fn main() {
    config::load();
    logging::init();    // 来自 feature-a
    database::connect(); // 来自 main
    run_app();
}
```

#### 验证

- 编译状态：✓ 成功
- 测试状态：✓ 通过（运行 `cargo test`）
- 功能验证：✓ 日志正确记录数据库连接事件

---

### 冲突 2：Cargo.toml（来自 feature-a）

**时间**：2024-01-15 14:35:12
**冲突类型**：依赖文件冲突

#### 原始冲突内容

```toml
# <<<<<<< HEAD (main 分支)
[dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.0", features = ["full"] }
# =======
[dependencies]
serde = { version = "1.0", features = ["derive", "rc"] }
jsonwebtoken = "0.16"
# >>>>>>> feature-a
```

#### 变更详情

**我们的变更（feature-a 分支）**：
- 为 serde 添加 "rc" feature
- 新增 jsonwebtoken 依赖

**他们的变更（main 分支）**：
- 新增 tokio 依赖

#### 解决过程

1. 分析依赖关系：
   - serde：合并 features
   - jsonwebtoken：feature-a 需要
   - tokio：main 需要

2. 确定解决策略：
   - 合并所有依赖项
   - 合并 serde 的 features

#### 解决结果

```toml
[dependencies]
serde = { version = "1.0", features = ["derive", "rc"] }
tokio = { version = "1.0", features = ["full"] }
jsonwebtoken = "0.16"
```

#### 验证

- 编译状态：✓ 成功
- 依赖解析：✓ 无版本冲突

---

## 编译验证

- **构建工具**：cargo
- **构建命令**：`cargo build --release`
- **构建结果**：成功
- **编译警告**：2 个（已记录）

---

## 后续建议

1. 考虑为 feature-a 分支添加集成测试
2. 建议在 CI 中增加编译警告检查

---

## 完整操作日志

<记录所有执行的 git 命令及其输出>
```

---

## 错误处理

### 主分支编译保护（最高优先级）

**核心原则：主分支必须在任何时刻都保持可编译状态。这是不可妥协的约束。**

保护机制：
1. **合并前验证**：任何合并开始前，必须验证主分支可编译
2. **合并后验证**：每次合并后立即验证，失败则回滚
3. **失败隔离**：单个分支合并失败不影响其他分支的处理
4. **完整回滚**：如果需要，提供回滚到初始状态的选项

### 编译失败处理流程

#### 功能分支变基后编译失败

1. **记录错误**：
   ```bash
   <build-command> 2>&1 | tee /tmp/build_error.log
   ```

2. **尝试自动修复**（仅限简单问题）：
   - Import 路径错误：检查并更新导入语句
   - 明显的类型不匹配：检查 API 变更

3. **无法修复时**：
   ```bash
   git rebase --abort  # 回滚变基
   ```
   - 记录该分支跳过的原因
   - 主分支状态未改变，继续处理下一个分支

#### 合并到主分支后编译失败

1. **立即回滚合并**：
   ```bash
   cd <main-worktree-path>
   git reset --hard HEAD~1
   ```

2. **验证回滚后状态**：
   ```bash
   <build-command>  # 确认主分支仍可编译
   ```

3. **记录失败详情到文档**：
   - 分支名称
   - 编译错误日志
   - 可能的冲突文件
   - 建议的手动解决步骤

4. **继续处理下一个分支**（主分支仍保持可编译）

### 无法自动解决的冲突

1. 如果冲突发生在功能分支变基阶段：
   - 尝试解决冲突
   - 如果无法解决，执行 `git rebase --abort`
   - 跳过该分支，主分支不受影响

2. 如果冲突发生在合并阶段：
   - 执行 `git merge --abort`
   - 主分支保持合并前状态
   - 记录冲突详情供用户手动处理

### 全部失败的恢复

如果所有分支都无法合并：

```bash
# 确认主分支状态
cd <main-worktree-path>
git status
<build-command>

# 主分支应仍处于初始可编译状态
# 生成报告说明所有分支都跳过的原因
```

---

## 使用触发词

用户可以使用以下方式触发此技能：

- "同步所有工作树"
- "同步 git worktrees"
- "把各分支改动合并到主分支"
- "rebase 所有工作树"
- "同步分支并记录冲突"
- "合并所有 worktree 的改动"
- "扇入扇出同步"

---

## 注意事项

1. **备份重要**：执行前建议为重要分支创建备份
   ```bash
   git branch backup/<branch-name> <branch-name>
   ```

2. **工作区干净**：确保各 worktree 没有未提交的重要更改
   ```bash
   git stash  # 暂存未提交的更改
   ```

3. **依赖更新**：合并后可能需要重新安装依赖
   - Node.js: `npm install` / `yarn` / `pnpm install`
   - Rust: `cargo build` (自动处理)
   - Python: `pip install -r requirements.txt`

4. **测试验证**：同步后建议运行测试套件
   ```bash
   npm test
   cargo test
   pytest
   ```