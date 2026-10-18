---
name: codebase-module-generator
description: 阅读任意目录，分析模块结构，生成防腐蚀规范 skill（不生成孤儿文档）
---

# Codebase 模块规范生成器

调用 /writing-skills 或 /skill-creator 获得 skill 规范。

给出 bad_example 和 good_eg 的正反案例。

## 触发场景

- "为这个项目创建模块规范"
- "防止代码腐蚀，生成规范 skill"
- "分析这个目录，输出 skill 文件"
- 开始一个新的代码模块/项目

## 核心原则

**只生成 `.claude/skills/<name>/SKILL.md` 文件，不生成孤儿 markdown 文档。**

---

## 核心流程

### Step 1: 读取目录结构

```powershell
# 获取所有源文件
ls -File -Recurse *.js,*.ts,*.py,*.go

# 查看文件树（含行数）
Get-ChildItem -Recurse -File | Select-Object FullName, @{N='Lines';E={(Get-Content $_.FullName | Measure-Object -Line).Lines}}
```

**分析维度：**

| 维度 | 说明 |
|------|------|
| 文件数量 | 判断模块复杂度 |
| 文件大小 | 找出过于臃肿的文件（>300行标记） |
| 命名模式 | 识别模块划分（如 `xxx.js` + `xxx-utils.js`） |

### Step 2: 模块依赖分析

对每个源文件提取：

```javascript
// 导入分析
import ... from './xxx.js'   // 相对导入
import ... from 'xxx'        // 包导入

// 导出分析
export function xxx()         // 命名导出
export default class xxx      // 默认导出
export { xxx, yyy }          // 多导出
```

**生成依赖矩阵：**

```markdown
## 模块依赖矩阵

| 文件 | 导入模块 | 被导入次数 | 行数 | 状态 |
|------|---------|----------|------|------|
| index.js | commands, groups, utils | 0 | 50 | ✅ |
| groups.js | utils | 3 | 160 | ✅ |
| utils.js | (无) | 5 | 80 | ✅ |
| timeline.js | utils | 2 | 450 | ⚠️ 过大 |
```

### Step 3: 代码异味识别

#### 3.1 模块大小检查

```powershell
# 超过 300 行的文件
foreach ($f in Get-ChildItem . -Recurse -Filter "*.js") {
  $lines = (Get-Content $f | Measure-Object -Line).Lines
  if ($lines -gt 300) {
    Write-Host "⚠️  $($f.FullName): $lines 行"
  }
}
```

#### 3.2 循环依赖检测

```javascript
// 如果 A→B→C→A，则存在循环依赖
function detectCycle(moduleGraph) {
  // Tarjan 算法或简单 DFS
}
```

#### 3.3 重复代码检测

```powershell
# 查找重复函数名
grep -rn "function openTabboard" . --include="*.js"

# 查找重复的常量
grep -rn "DEFAULT_COLORS\|const DEFAULT_" . --include="*.js"
```

#### 3.4 违反单一职责

```javascript
// 一个文件处理多种职责
const hasStorage = content.includes('chrome.storage');
const hasUI = content.includes('document.createElement');
const hasNetwork = content.includes('fetch') || content.includes('XMLHttpRequest');

if (hasStorage && hasUI) {
  warnings.push(`${file}: 同时处理存储和 UI，违反单一职责`);
}
```

### Step 4: 生成 Skill 文件

**只生成 skill 文件，不生成独立的 markdown 文档。**

#### 4.1 目录结构

```
.claude/skills/<模块名>/
└── SKILL.md   ← 唯一的输出物
```

#### 4.2 Skill 文件结构

```markdown
---
name: <模块名>-standards
description: <触发描述>
---

# {项目名} {模块名} 模块规范

## 模块职责边界

| 模块 | 职责 | 禁止混入 |
|------|------|---------|
| index.js | 入口/组装 | 业务逻辑 |

## 反正面案例

### bad_example
[错误代码]

### good_eg
[正确代码]
```

---

## 决策树：何时生成什么规范

```
开始分析目录
    │
    ├─► 目录包含 background/ 或 service-worker/
    │       └─► 生成 chrome-ext-background-standards skill
    │
    ├─► 目录包含 popup/
    │       └─► 生成 chrome-ext-popup-standards skill
    │
    ├─► 目录是独立工具库（utils/）
    │       └─► 生成 utils-module-standards skill
    │
    ├─► 目录是前端组件（components/）
    │       └─► 生成 frontend-component-standards skill
    │
    └─► 通用的多模块项目
            └─► 生成通用的 module-standards skill
```

---

## 反正面案例 (bad_example / good_eg)

### 案例 1: 生成孤儿文档

#### bad_example

```bash
# ❌ 生成独立的 markdown 文档
生成 BACKGROUND_STANDARDS.md
生成 MODULE_STANDARDS.md
# 这些文档无人维护，最终成为孤儿
```

#### good_eg

```bash
# ✅ 只生成 skill 文件
.claude/skills/chrome-ext-background-standards/
└── SKILL.md   ← 唯一的输出物

# skill 文件本身就是规范，可被 /skill-discovery 发现和复用
```

---

### 案例 2: 工具函数重复定义

#### bad_example

```javascript
// utils.js 中没有定义 normalizeUrl
// A.js 自己定义了一份
function normalizeUrl(url) { ... }

// B.js 也自己定义了一份（稍有不同）
function normalizeUrl(url) {
  // 略有差异的逻辑
}
```

#### good_eg

```javascript
// utils.js 中唯一定义
export function normalizeUrl(url) { ... }

// A.js 和 B.js 都导入使用
import { normalizeUrl } from './utils.js';
```

---

### 案例 3: 违反模块边界

#### bad_example

```javascript
// groups.js 直接调用 timeline.js 的函数
import { collectCurrentWindowTabs } from './timeline.js';

function addGroup(name) {
  collectCurrentWindowTabs(); // ❌ 违反模块边界
}
```

#### good_eg

```javascript
// groups.js 通过消息与 timeline.js 通信
async function addGroup(name) {
  // ✅ 通过 chrome.runtime.sendMessage 通信
  await chrome.runtime.sendMessage({ action: 'collectCurrentWindowTabs' });
}
```

---

## 错误案例警示

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 生成独立的 markdown 文档 | 文档无人维护，最终成为孤儿 | 只生成 SKILL.md 文件 |
| 不读取文件就制定规范 | 规范与实际脱节，无法执行 | 先完整遍历目录 |
| 规范过于宽泛 | "要保持代码整洁" 无法执行 | 给出具体检测方式和阈值 |
| 只分析表面命名 | `utils.js` 可能不是真正的工具模块 | 分析实际 import/export 依赖 |
| 遗漏 package.json | 不知道外部依赖，无法判断是否应该引入 | 同时读取 package.json |

## 成功标准检查清单

- [ ] 读取了目录**所有**源文件
- [ ] 生成了模块依赖矩阵
- [ ] 识别了代码异味（过大文件、循环依赖、重复代码）
- [ ] 规范包含**可执行**的检测方式（如 grep 命令）
- [ ] 规范输出了具体违规位置（如 `groups.js:130`）
- [ ] 只生成了 `.claude/skills/<name>/SKILL.md` 文件
- [ ] **没有生成独立的** `.md` 文档文件
- [ ] 给出了正反案例（bad_example / good_eg）
