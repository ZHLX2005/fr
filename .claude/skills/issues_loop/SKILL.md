---
name: issues_loop
description: loop操作
---

# Issues Loop Skill

每 5 分钟检查 ZHLX2005/is 的 open issues，完成一个后执行 flutter-work-flow 推送并关闭 issue。

## 定时任务设置

**必须使用 CronCreate 设置 recurring cron，不要使用 ScheduleWakeup。**

```bash
CronCreate: */5 * * * *
```

- 错误做法：使用 ScheduleWakeup 创建 one-shot 任务来模拟循环（会变成每天执行，而不是每5分钟）
- 正确做法：CronCreate + recurring:true，每5分钟自动触发

## 工作流

1. `gh issue list --repo ZHLX2005/is --state open --limit 10`
2. 如果有 issues：按顺序处理每个，完成后 flutter-work-flow 推送，再关闭 issue
3. 如果没有 issues：不用 ScheduleWakeup 退避，cron 会在5分钟后自动再次触发
4. 不能取消此 loop

## 关键错误经验

1. **不要用 ScheduleWakeup 模拟循环** — ScheduleWakeup 是 one-shot，到期触发一次就结束，不能替代 cron recurring
2. **CronList 显示 "每天" 是误导** — one-shot schedule 显示为 "每天" 是界面描述，不代表实际频率
3. **正确方式：CronCreate + recurring:true** — 设置后 cron 会按表达式自动重复执行
