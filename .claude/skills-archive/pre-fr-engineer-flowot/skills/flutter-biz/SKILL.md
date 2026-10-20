---
name: flutter-biz
description: FR 项目业务层总入口，dart-flutter 任何问题都需要优先加载这个 skill。覆盖六个子域：①主工作流（fr:// 路由注册与 Router 机制、Lab 容器、时间页 Focus、游戏中心扩展、API 模块规范、Hive 存储三件套、课表 Timetable、WebRTC、追剧模式、Provider/Hive/掉帧等问题方案，含项目级开发规范：analyze/commit/文件组织铁律）②联机协议（Relay/LAN/快照/action 流、net_p2p/net_engine、晚加入者错过事件、两端不同步）③Lua 状态机（新增互联网房间业务、on_action 元函数契约、对战游戏模板、棋盘镜像与手势）④音频桥接（节拍器/低延迟音频/C++ Oboe/FFI/音画不同步）⑤消息策略（IMessageData/MessageWidgetStrategy/加新消息类型/会话持久化）⑥调试日志（debugPrint 排查法）。加新功能模块、扩展业务、联机对战、音频同步、消息类型时加载本 skill。
---

# flutter-biz — 业务层总入口

> **dart-flutter 任何问题优先加载本 skill**，再按子域路由。本页只做路由，规范与 SOP 在子域内。
>
> 🗺️ **项目业务板块地图**（A 序列基础：§一骨架树全景速查 + §二 50 demo 定位总表 grep 秒查 + §三板块共享层）→ `.claude/repo/_self/fr-business-map/project/2026-10-18-v2.md`。找「某个 demo 在哪/属于哪个板块」直接 grep 地图 §二；「怎么做」再看下面子域。

## 子域总览（先读这里）

| 子域 | 路由页 | 内容 | 何时进入 |
| --- | --- | --- | --- |
| 主工作流 | `references/workflow/flutter-work-flow.md` | 19 refs（A01-C04）：A=扩展 SOP（fr:// 路由×2 / Lab 容器 / TimePage / 游戏中心 / slug 别名 / API 模块 / Hive×3）、B=问题方案（Provider 双实例 / Hive CI / FloatingWindow / CollapsingHeader / 掉帧）、C=专项（课表 / WebRTC / 追剧×2）。**主文档内嵌项目级开发规范**（analyze 最低成本验证 / commit 逐条确认 / 单文件优先超 400 行才解耦 / const_xxx.dart 集中常量） | 改任何业务模块前；加新页面/写跳转/新 API/新存储时必读对应 ref |
| 联机协议 | `references/netp2p/net-p2p-protocol-playbook.md` | 4 refs：v1-action（LAN 现成）/ v2-snapshot（已删除，历史）/ v3-lua（新功能默认）/ v4-coup-bugfixes（Coup 修复记录） | 提及 Relay/LAN/快照/action 流；排查不同步/丢事件 |
| Lua 状态机 | `references/relaylua/relay-lua-state-machine.md` | 8 refs（A01-C01）：A=通用契约（服务端权威字段 / 命名与 kGameMeta / 权限表）、B=对战游戏族（端到端模板 / 社交房号 / 棋盘镜像 / 棋盘手势）、C=大厅族（团队卡牌） | 新增互联网房间业务/写 Lua 脚本/加 action 类型 |
| 音频桥接 | `references/audio/flutter-android-cpp-audio-bridge.md` | 4 refs：oboe-cpp-synthesis / android-native-c-setup / wav-sample-playback / clock-vs-metronome-lifecycle | 节拍器/节奏游戏/低延迟音频/音画不同步 |
| 消息策略 | `references/message/flutter-message-workflow.md` | 1 ref：im-会话持久化规范 | 加新消息类型到 message_strategy 系统 |
| 调试日志 | `references/debuglog/flutter-debug-logging.md` | 单文档：debugPrint 追踪法（[ClassName] 标签 / 因果链 / 状态完整打印 / 清理纪律） | bug 反复出现根因不明 / UI 状态异常 / 交互不符预期 |

## 路径约定（重要）

- 子域路由页与其 refs **同目录**。路由页正文里写的 `references/xxx.md` 一律按「同目录下的 xxx.md」理解（历史相对路径，迁移后语义不变）。
- 例：`references/workflow/flutter-work-flow.md` 里写 `[[A01-Flutter-fr路由-注册规范与防腐蚀]]` → 实际文件 `references/workflow/A01-Flutter-fr路由-注册规范与防腐蚀.md`。

## 项目级开发规范速记（全文见主工作流子域）

1. 完成代码先 `flutter analyze | grep error` 最低成本验证；改了 Android 目录必须 `flutter build apk`
2. commit 走 Conventional Commits，只 add 自己变更的文件（禁 `add .`），提交前 `git status` 逐条确认归属
3. lab/demos 下 demo 默认单文件；超 400 行才解耦为 `lab/demos/(模块名)/扩展文件.dart`
4. 一个模块的常量统一放 `const_xxxx.dart`；native 桥接统一放 `lib/native`
5. 任何不能立即完成的任务先用 todolist 规划，禁止无流程改代码

## 跨子域规则（不进子域也要记住）

- **新功能联机房间默认走 v3 Lua 状态机**（v2 已删除；LAN 保留 v1）。
- **客户端不自查身份/胜负/房主**——必须用服务端权威字段（`host_id`/`top_player_id`/`winner`），任何 v3 业务先读 relaylua 的 A01。
- ** Lua 全局 `state` 是 snapshot 顶层字段**，不是 `context.state`——改阶段必须同时改 `state = "..."`。
- 加新联机 demo：title 必须「（联机）」后缀 + slug 与 `kGameMeta` 字符级一致（relaylua A02）。

## 协作 skill

- `flutter-ui`：样式/主题/皮肤资源（业务页面的视觉层）
- `flutter-platform`：AppWidget / 悬浮窗截屏 / 图标等 Android 原生桥接
- `key_board`：本 skill 的 ref 生命周期
