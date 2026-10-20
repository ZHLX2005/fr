---
name: F00-资产与Rive路由
description: FR 外部资产管理、皮肤/封面/表情包发布、资源自动化与 Rive 的大序列路由。先按 Fa 资源管线或 Fb Rive 子序列选择具体 SOP。
---

# F00 — 外部资产与 Rive 大序列路由

> F 是外部资产管理与自动化大序列。Fa、Fb 是子序列，子序列从 01 开始；本文件统一维护所有子序列路由。

## Fa — 外部游戏资源与公开 KV 管线

| 文档 | 何时读取 |
|---|---|
| [[Fa01-外部游戏资源管线路由]] | 先判断棋类皮肤、游戏封面、歌曲曲库、表情包所属资源管线 |
| [[Fa02-端到端SOP与故障排查]] | 执行发布、验证远端资源或排查资源未生效时 |
| [[Fa03-加载架构与文件地图]] | 了解客户端加载、fallback、KV 和缓存结构时 |
| [[Fa04-表情包端到端SOP]] | 发布或排查表情包专项时 |

脚本在仓库内 `.claude/skills/fr-engineer-flowot/scripts/`：`add_skin.py`、`add_emoji_pack.py`、`retag_existing.py`、`migrate_line_from_supabase.py`。

## Fb — Rive 动画、运行时与项目接入

| 文档 | 何时读取 |
|---|---|
| [[Fb01-Rive路由]] | Rive 总入口、判断编辑器/运行时/API 主题时 |
| [[Fb02-Rive上游资料索引]] | 查阅 Rive 各主题资料目录时 |
| [[Fb03-Rive-Flutter-0.14-DataBind]] | FR Flutter 0.14.5 runtime、ViewModel/DataBind 与状态输入时 |
| [[Fb04-Rive-Flutter项目工作流]] | 添加 FR Rive 资产、Lab demo 和 pubspec 注册时 |
| [[Fb05-Rive动画模式]] | Rive 动画模式编辑时 |
| [[Fb06-Rive约束]] | 使用 Rive constraints 时 |
| [[Fb07-Rive数据绑定]] | 查阅 Rive 通用数据绑定概念时 |
| [[Fb08-Rive编辑器基础]] | 学习编辑器工作流与基础结构时 |
| [[Fb09-Rive事件]] | 配置 Rive events 时 |
| [[Fb10-Rive-FlutterRuntime]] | 查阅 Flutter runtime 通用 API 时，先确认 API 版本 |
| [[Fb11-Rive游戏Runtime]] | 查阅 Unity/Unreal 等游戏 runtime 时 |
| [[Fb12-Rive布局]] | 编排 Rive layout 时 |
| [[Fb13-Rive图形编辑]] | 在编辑器中操作 shapes 时 |
| [[Fb14-Rive移动端Runtime]] | 查阅移动平台 runtime 时 |
| [[Fb15-Rive-ReactRuntime]] | 查阅 React runtime 时 |
| [[Fb16-Rive脚本API]] | 编写 Rive/Luau 脚本时 |
| [[Fb17-Rive状态机]] | 设计或调试状态机时 |
| [[Fb18-Rive文本]] | 处理 Rive text 时 |
| [[Fb19-Rive-WebRuntime]] | 查阅 web runtime 时 |

## 副作用确认与版本约束

- 公开上传或修改远端 KV/file 索引会产生外部副作用；执行脚本前核实目标、认证身份、参数和 dry-run 能力，不默认代用户发布。
- FR 当前项目化 API 以 [[Fb03-Rive-Flutter-0.14-DataBind]] 为准。部分通用材料使用旧版 0.13 API，只能在确认目标 runtime 版本匹配时使用，禁止跨版本混用。
- 样式、主题配色属于 E 序列，不在 F 重复维护；Rive 与 Lab demo 结构可链接到 A 序列。
