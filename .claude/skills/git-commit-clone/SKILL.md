---
name: git-commit-clone
description: |
  为指定 commit 创建项目浅克隆（--depth=1）快照到 .claude/repo/project/。显式触发，无自动 hook。
  适用于存档项目历史版本、对比不同 commit 之间的快照、回滚参考分析。
  触发场景：
  - "为这个 commit 创建快照"
  - "快照当前项目状态"
  - "查看项目历史快照"
  - "管理快照保留数量"
  - "为快照创建索引"
type: workflow
---

# git-commit-clone — 提交即快照（显式模式）

## 核心功能

为**指定 commit** 显式创建浅克隆（`--depth=1`）快照到 `.claude/repo/project/`，形成可浏览的项目快照存档。

**无自动 hook，每次快照都需要显式调用。**

## 命令参考

### `snapshot` — 为指定 commit 创建快照

```bash
# 为当前 HEAD 创建快照
bash .claude/skills/git-commit-clone/reference/clone-snapshot.sh

# 为指定 commit 创建快照
bash .claude/skills/git-commit-clone/reference/clone-snapshot.sh a1b2c3d
```

### `list` — 查看快照列表

```bash
# 查看目录树
ls -la .claude/repo/project/

# 查看索引（如果支持 jq）
jq '.' .claude/repo/project/snapshots.json 2>/dev/null
```

### `show` — 查看某个快照

```bash
SNAP=$(ls -1d .claude/repo/project/*-* | sort | tail -1)
echo "=== Snapshot: $(basename $SNAP) ==="
cat "$SNAP/.snapshot-meta.json"
echo "---"
ls -la "$SNAP/"
```

### `prune` — 清理旧快照

保留最近 N 个快照，删除更早的。默认保留 10 个。

```bash
# 保留最近 10 个
bash .claude/skills/git-commit-clone/reference/prune-snapshots.sh

# 自定义保留数量（保留 5 个）
bash .claude/skills/git-commit-clone/reference/prune-snapshots.sh 5
```

### `index` — 为快照创建索引

为每个快照生成 `PROJECT_INDEX.md` 和 `PROJECT_INDEX.json`，使快照可浏览。

> 复用 `index-repos` skill 的并行 subagent 机制。

## 目录结构

```
.claude/repo/project/
├── 2026-06-04-a1b2c3d/           # 快照目录（日期-短哈希）
│   ├── (项目文件全量浅克隆)
│   └── .snapshot-meta.json       # 快照元数据
├── 2026-06-04-e4f5g6h/
├── 2026-06-05-xyz7890/
├── snapshots.json                # 全局快照索引（机器可读）
└── snapshots.log                 # 快照日志（备选，当 jq 不可用时）
```

## 实现脚本

```
.claude/skills/git-commit-clone/
├── SKILL.md                          # 本文档
└── reference/
    ├── clone-snapshot.sh             # Linux: 创建快照
    ├── clone-snapshot.ps1            # Windows: 创建快照
    └── prune-snapshots.sh            # 清理旧快照
```

## 快速开始

```bash
# 1. 为当前 commit 创建快照
bash .claude/skills/git-commit-clone/reference/clone-snapshot.sh

# 2. 查看快照
ls -la .claude/repo/project/

# 3. 为历史 commit 创建快照
bash .claude/skills/git-commit-clone/reference/clone-snapshot.sh a1b2c3d
```

## 错误处理

| 症状 | 原因 | 解决 |
|------|------|------|
| commit 不存在 | 本地没有该 commit | 先 `git fetch` 拉取目标 commit |
| 快照目录为空 | `file://` 克隆失败 | 检查 `.gitignore` 是否排除自身 |
| 快照太多占用空间 | 保留数量默认 10 个 | 使用 `prune` 命令减少 |
| `jq` 命令未找到 | 未安装 jq | 回退到 `snapshots.log` 文本日志 |
| 快照跳过 | 同一 commit 已存在快照 | 这是预期的幂等行为 |

## 与现有技能集成

| 技能 | 集成方式 |
|------|---------|
| **`index-repos`** | `index` 命令为每个快照创建 `PROJECT_INDEX.md`，实现可浏览的历史存档 |
| **`repo-gitlink`** | 快照元数据包含 `remote_url`，可追加到 `git.remote` |

## 验证清单

- [ ] `snapshot` 后 `.claude/repo/project/` 生成了快照目录
- [ ] 为特定 commit 创建快照成功
- [ ] `list` 能看到所有快照
- [ ] `prune` 正确保留最近 N 个
- [ ] `.snapshot-meta.json` 内容完整
