---
name: flutter-ui
description: FR 项目 UI 层总入口。覆盖五个子域：①样式方案（样式选型、视觉对齐复刻、docs/prototypes HTML 原型对照、banner/Card/Button/NavigationBar/Modal/胶囊 CTA/Zen 浮卡/商店式内容页/border-emphasis）②主题架构（zen/purple/ink/rose/lemon/cobalt/dark 七主题、ColorStrategy/BoardColorStrategy/ChessColorStrategy 六通道、语义角色扩展、裸 hex 红线、颜色用量审计）③游戏资源管线（新增/更换皮肤/封面/曲库/表情包、chess_skin:index 等 KV 发布、上传脚本、资源不生效排查）④块编辑器（Block 模型、BlockType、RichText/Span、笔记持久化、工具栏、Markdown 导入）⑤Rive 动画（Luau 脚本、状态机、DataBind/ViewModel、Flutter 集成）。做任何 UI 样式、主题配色、游戏皮肤资源、笔记编辑器、动画时加载本 skill。
---

# flutter-ui — UI 层总入口

> 本页只做路由。每个子域是一份完整的「原 skill 文档 + 序列化 refs」，按需进入。

## 子域总览（先读这里）

| 子域 | 路由页 | 内容 | 何时进入 |
| --- | --- | --- | --- |
| 样式方案 | `references/styles/flutter-ui-styles.md` | 13 refs（A00-C01）：A=样式方案 SOP（边框减负/可拉伸 banner/胶囊底栏/商店页/Zen 浮卡/嵌套托盘/方圆角判决/大厅房间）、B=排障（嵌套 sheet race）、C=原型契约（HTML 对照/全主题游戏表面） | 做某种样式/选方案/HTML 原型对齐前 |
| 主题架构 | `references/theme/flutter-ui-theme-architecture.md` | 4 refs（A01-B02）：A01 系统架构与数据流 / A02 扩展 SOP 与迁移 / B01 颜色用量审计 / B02 特例策略 | 改主题配色/扩展语义角色/评审用色合规前 |
| 皮肤管线 | `references/skins/flutter-ui-game-skin-pipeline.md` | 3 refs（A01-A03）：端到端 SOP 与故障排查 / 加载架构与文件地图 / 表情包端到端 | 新增皮肤/封面/歌曲/表情包、资源不生效排查 |
| 块编辑器 | `references/note/block-note-core.md` | 3 refs：types（数据模型）/ persistence（持久化）/ demo-ui（UI 层） | 改 `lib/core/note/` 或 block_editor_demo 任何文件 |
| Rive 动画 | `references/rive/rive-skills.md` | 17 refs：Luau 脚本 API / 状态机 / DataBinding / 各平台 runtime + 本项目 0.14 特化（flutter-databind / project-workflow） | 做 Rive 动画/写 Luau 脚本/Flutter 集成 |

## 路径约定（重要）

- 子域路由页与其 refs **同目录**。路由页正文里写的 `references/xxx.md` 一律按「同目录下的 xxx.md」理解（历史相对路径，迁移后语义不变）。
- 例：`references/styles/flutter-ui-styles.md` 里写 `[[A01-边框强调式减负]]` → 实际文件 `references/styles/A01-边框强调式减负.md`。
- 皮肤管线脚本在层根 `scripts/`（add_skin.py / add_emoji_pack.py / retag_existing.py / migrate_line_from_supabase.py），从项目根执行：`python .claude/skills/flutter-ui/scripts/add_skin.py ...`。

## 跨子域规则（不进子域也要记住）

- **功能型 vs 内容型先定性**——同一条配色规则在两类页面结论相反（详见 styles 主文档核心原则）。
- **`lib/` 新增代码禁止裸 hex**——走 scheme / 六通道；特例（tetris / teamAvatar）走 native const，豁免必须带注释（详见 theme 主文档红线）。
- **KV index 是全量覆盖语义**——改图必须换新 id 或让用户清缓存（详见 skins 主文档踩坑表）。
- 游戏表面禁写死 Zen hex，走 `[[C01-游戏表面ColorScheme契约]]`（styles refs 内）。

## 协作 skill

- `flutter-biz`：业务扩展 SOP（路由注册/Lab 容器/API/Hive）、build / lint / format 流程
- `flutter-platform`：Android 原生桥接（widget/截屏/图标）
- `key_board`：本 skill 的 ref 生命周期（新增子域 ref 按 styles 的 A/B/C 序列惯例续号）
