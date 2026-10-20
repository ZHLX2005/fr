---
name: UNMAPPED-REVIEW
description: 完整归档后仍未按用户确认的 A–H 序列明确分配的 FR Skill 文件与主题，等待用户审核；不擅自归类或丢弃。
---

# UNMAPPED — 待用户审核

> 这些材料已随旧 `.claude/skills/` 完整备份到 `.claude/skills-archive/pre-fr-engineer-flowot/skills/`。当前不在 A–H 活动序列内，不代表内容已过时或删除。用户审核并指定归属后，再按新 Skill 命名、改路由和链接。

## 存在于归档中的待审材料

| 来源路径（相对归档 `skills/`） | 内容 | 未归类原因 |
|---|---|---|
| `flutter-biz/references/workflow/B01-Flutter-Provider双重实例冲突-时钟wipe后数据恢复.md` | Provider 双实例与数据恢复问题案例 | 故障案例，不是当前 B 的简单功能模板；不在用户明示 A/D/H 的边界中 |
| `flutter-biz/references/workflow/B02-Flutter-Hive-TypeAdapter-part文件CI构建失败问题.md` | Hive/codegen CI 失败案例 | D 可接收但此问题文档非用户明确指定；先由用户审核是否作为 D 故障子 ref |
| `flutter-biz/references/workflow/B04-Flutter-CollapsingHeader圆角渐变头部与白色内容区布局.md` | UI 方案案例 | E 有样式域，但未获明确同意此历史 B 文档是否并入 E |
| `flutter-biz/references/workflow/B05-Flutter-Reorderable网格阴影容器拖拽掉帧-RepaintBoundary隔离.md` | 性能/交互问题案例 | 非已定义的 B 业务场景模板，也未明确归 E |
| `flutter-biz/references/workflow/C01-Flutter-TimeTable课表模块-架构与扩展指南.md` | Timetable 子系统 | 用户指定顶层 C 只放 RelayLua，需另行审核是否设新序列或归 A/B |
| `flutter-biz/references/workflow/C02-WebRTC-视频通话基础设施与结构设计.md` | WebRTC 实时通信子系统 | 用户指定顶层 C 只放 RelayLua；不擅自另创序列 |
| `flutter-biz/references/workflow/C03-Flutter-TimeTable-追剧模式专项.md` | Timetable 追剧专项 | 依赖 C01，但 C01 尚待审核 |
| `flutter-biz/references/workflow/C04-Flutter-TimeTable-追剧后端API契约.md` | 追剧后端契约 | 依赖 C01/C03，但其位置待审核 |
| `flutter-ui/references/note/block-note-core.md`、`demo-ui.md`、`persistence.md`、`types.md` | 块编辑器与笔记持久化 | E 定义为 UI/色彩，D 为 Hive；用户未指定是否拆到新一级序列 |
| `flutter-biz/references/debuglog/flutter-debug-logging.md` | debugPrint 诊断方法 | 横跨各序列的通用排障手册，没有明确指定归属 |

## 当前工作树已删除、未包含在备份内容中的条目

工作树在迁移开始前已将以下 tracked 文件删除；用户明确选择“按删除结果迁移”，因此本次没有从 Git 恢复，也没有放进归档快照。Git 历史保留其旧版，可由用户审核是否恢复。

### `.claude/skills/dev-git-flow/`（4 个文件）

- `SKILL.md`
- `references/codegen/codebase-module-generator.md`
- `references/pr/pr-workflow.md`
- `references/release/gh-upstream-release.md`

### `.claude/skills/flutter-biz/references/netp2p/`（5 个文件）

- `net-p2p-protocol-playbook.md`
- `v1-action-driven.md`
- `v2-snapshot-driven.md`
- `v3-lua-state-machine.md`
- `v4-coup-bugfixes.md`

## 已纳入的新入口但其旧入口副本只在归档

旧根 `flutter-biz/SKILL.md`、`flutter-ui/SKILL.md`、`flutter-platform/SKILL.md` 的分流职责已由新 `fr-engineer-flowot/SKILL.md` 与 A00/B00/C00/D00–H00 各序列路由接管；旧文件完整留在归档。当前已删除的 `dev-git-flow/SKILL.md` 不属于已确认 A–H 范围，仍在上方审核。

## 审核处理

用户可对表中每项指定“归 A/B/C/D/E/F/G/H、另设序列、恢复后再纳入、继续归档”。在明确指示前，保持此清单与原始归档，不自行迁移或删除。
