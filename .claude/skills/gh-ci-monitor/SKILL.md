---
name: gh-ci-monitor
description: GitHub Actions CI 流水线监控，直到构建成功或失败。自动重试失败的构建，监控直到完成。
---

# GH CI Monitor Skill

监控 GitHub Actions 构建状态，直到成功或用户干预。

## 使用方式

当用户要求监控 CI 构建时调用，例如："监控流水线"、"monitor CI build"、"gh 监控"。

## 工作流程

### 1. 检查当前构建状态

先获取当前最新构建列表：

```bash
gh run list --limit 1
```

判断状态：
- `in_progress` → 构建进行中，开始监控
- `completed success` → 构建已成功，通知用户
- `completed failure` → 构建失败，询问是否重试

### 2. 启动 Monitor 监控

使用 Monitor 工具持续监控：

```
描述: GH CI build monitor
timeout_ms: 600000 (10分钟超时)
persistent: true
command: gh run list --limit 1
```

Monitor 返回 `completed` 状态时，检查结果。

### 3. 验证构建结果

```bash
gh run list --limit 1
gh run view <run_id> --log 2>&1 | grep -E "FAILURE|error" | head -5
```

- 成功 → 通知用户，提供 APK 下载信息
- 失败 → 分析错误原因，询问是否重试

### 4. 构建失败处理

```bash
# 重新触发构建
gh run rerun <run_id>

# 或创建新构建（对于 PR）
gh pr checkout <pr_number> && git push
```

## 关键经验

### Monitor 工具使用要点

1. **persistent:true** — 设置为持久模式，持续监控直到 TaskStop 或会话结束
2. **timeout_ms** — 最大监控时间，建议 600000ms（10分钟），正常构建约 13 分钟
3. **不要用 sleep 轮询** — Monitor 会自动在状态变化时通知，不要用 `sleep && gh run list` 轮询
4. **Monitor stream ended** — 这只是意味着轮询停止，不代表构建完成，需要再次检查 `gh run list`

### 危险节点识别

Flutter Android 构建关键时间点：
- **40s 内** → Gradle kotlin-dsl 解析阶段，失败通常为插件仓库问题
- **40s 后** → Gradle 编译阶段，失败通常为代码问题
- **5-7min** → Kotlin 编译阶段
- **10-13min** → APK 打包阶段

### 常见错误诊断

```
Plugin [id: 'org.gradle.kotlin.kotlin-dsl', version: '5.2.0'] was not found
→ CI 环境问题，Gradle 插件仓库网络问题，重新触发可能解决

FAILURE: Build failed with an exception
BUILD FAILED in Xs
→ 代码或配置问题，需要查看具体错误

Gradle task assembleRelease failed with exit code 1
→ 构建失败，需要分析日志
```

### 日志查看技巧

```bash
# 查看失败原因
gh run view <run_id> --log 2>&1 | grep -E "FAILURE|error" | head -10

# 查看 Gradle 构建详情
gh run view <run_id> --log 2>&1 | grep -B5 -A5 "Running Gradle"

# 查看所有注释/警告
gh run view <run_id>  # 显示 ANNOTATIONS
```

### 重试策略

- **kotlin-dsl 插件错误** → 直接重试，通常是临时网络问题
- **代码错误** → 先修复代码再重试
- **超时不响应** → 可能是 gradle daemon 卡死，直接 rerun

## 典型会话

```
用户: 监控流水线
→ gh run list --limit 1
→ in_progress，构建中
→ 启动 Monitor: gh run list --limit 1
→ 持续通知直到 completed
→ 检查结果：success/failure
→ 成功：通知用户 APK 已就绪
→ 失败：分析原因，询问是否重试
```
