# Subagent 批量检查 — 风格一致性大规模治理

> 何时读：需要对整个 lab/demos 目录（或某批文件）做统一的样式改造/检查（如 border-emphasis 转换、去 withOpacity、统一按钮风格）时。适用"批量发现 → 并行修复 → 统一验证"的场景。

---

## 一、实现思路

### 五步流程

```
前置扫描 → 精准分组 → 指令注入 → 并行派发 → 统一验证
```

### Step 1: 前置扫描（grep 定位）

先用 grep 定位所有疑似反模式，再用 context 确认是真问题还是误报：

```bash
# 1. 定位所有 ElevatedButton/FilledButton
grep -rn "ElevatedButton\|FilledButton" lib/lab/demos/ --include="*_demo.dart"

# 2. 定位 LinearGradient（区分：icon 容器 vs 背景装饰）
grep -rn "LinearGradient" lib/lab/demos/ --include="*_demo.dart"

# 3. 定位 Container 纯色填充（缩小范围）
grep -rn "Colors\.\w+\.shade\d\d\|color: Colors\.\w+" lib/lab/demos/ --include="*_demo.dart"
```

**关键原则**：不只看一行匹配，一定要 Read 上下文确认使用场景——游戏面板的纯色、色板展示、渐变背景都 **不是** 污染。

### Step 2: 精准分组

按**文件大小 × 改动复杂度**均衡分组，避免一个大文件拖慢整组 agent：

| 因素 | 策略 |
|------|------|
| 文件大小 | 大文件（>500 行）单组 1-2 个；小文件（<100 行）一组 5-6 个 |
| 改动复杂度 | 多处 ElevatedButton 的大文件（如 qr_demo 有 5 处）配少一点 |
| 子目录 | 同一子目录（network/、team_card/）尽量分给同一个 agent |
| 头部/BLE/WiFi 等跨模块 | 按子系统而不是按目录路径分组 |

**分组计算公式**：每组 ≈ `max(2, total_files / num_agents)`，确保没有 agent 空等或过载。

### Step 3: 指令注入（Agent Prompt 设计）

每个 agent 的 prompt 必须**自包含**——不依赖 agent 回问或查阅主 Skill：

```
## Task: Convert pure color blocks to border-emphasis style

FIX these files:
1. <file_path> — Fix: <具体行, 什么模式, 改成什么>

### Border-Emphasis Recipe:
- Button pattern: Replace ElevatedButton/FilledButton with OutlinedButton
  + styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.5)))
- Icon container: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: ...,
  border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5))
- Always use withValues(alpha:) NOT withOpacity()
- Semantic: green=primary, blue=info, red=danger, orange=warning

### Skip rules (do NOT touch):
- Game board cells (reversi, snake, 2048 tiles) — intentional
- Gradient background decorations (card backgrounds, Scaffold backgrounds)
- Color palette displays
- Already-outlined buttons

Return summary of what you changed.
```

**常见选择**：告诉 agent 哪些文件**肯定需要改**（附带行号），哪些**只需核实一次**（可能是误报），以及**明确跳过**的类别。

### Step 4: 并行派发

在同一个 response 里发出所有 Agent 调用——它们并行运行：

```dart
// All agents dispatched in one message for parallel execution
Agent(prompt: "Fix group 1 files: a, b, c, d")
Agent(prompt: "Fix group 2 files: e, f, g")
Agent(prompt: "Fix group 3 files: h, i, j, k")
...
```

**同步/异步选择**：让 agent 在 Background 运行（默认），不会阻塞主流程。用 `description` 参数区分各组的文件列表（方便结果逐个知晓）。

### Step 5: 统一验证

全部 agent 完成后，跑全局检查：

```bash
flutter analyze | grep -E "error|warning"
```

确认无误后再 commit。如果个别文件出 warning，需确认是本次改动引入的还是已有的 pre-existing issue。

---

## 二、踩坑总结

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 代理不做前置扫描，直接让 agent 遍历所有 demo | 大量文件无需修改，浪费 token 和时间 | 先用 grep 定位疑似目标，缩小 agents 覆盖范围 |
| 一个 agent 同时处理 30+ 文件 | 单个 agent 超载（token 溢出/超时） | 按文件大小×复杂度均衡分组，每组 ≤ 6 个文件 |
| agent prompt 里不写"跳过规则" | agent 把游戏面板/色板展示/渐变背景也改了 | 在 prompt 里明确列出哪些类别的纯色**不要碰** |
| 不提供具体的行号 | agent 从头读整个大文件（如 clock_demo.dart 1700+ 行） | 在 prompt 里写明 `Lines XXX-YYY` 精确位置 |
| 让 agent 自己决定语义色 | 出现不一致：有人用蓝，有人用绿，还有人用紫 | 在 prompt 里给死语义色对照表 |
| 用错 `withOpacity` | analyze 报 `deprecated_member_use` | prompt 里强制要求 `withValues(alpha:)` |
| agent 修完后没有统一 flutter analyze | 个别文件引入 break 未被发现 | 必须等全部 agent 完成后跑一次全局 analyze |
