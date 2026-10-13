# fr (小豆子)

Flutter 多功能个人应用：时间管理、AI 对话、块编辑笔记、多人游戏（局域网 / 互联网房间）、远程输入与实验性功能实验室。

## 功能特性

### 日常核心

- **番茄钟** — 专注计时器，支持统计记录与科目管理
- **课程表** — 课程时间表管理（Hive 本地存储，支持循环周），通过 home_widget 与 Android 桌面小组件实时同步
- **AI 聊天** — AI 助手与智能体对话（Supabase / pi 后端），含消息策略系统与票据 OCR
- **块编辑笔记** — Block 模型 + RichText 内联格式的块编辑器
- **日历** — 支持农历（Lunar）转换

### 多人游戏中心

游戏中心收录 16 款游戏，双通道联机：

- **Lua 房间游戏（Relay v3 · 互联网）** — 围合大作战、五子棋、围棋、团队卡、俄罗斯方块、Coup、黑白棋、国际象棋、斗兽棋、数独。WebSocket 快照驱动 + 服务端 Lua 状态机，新增房间业务只需写一个 Lua 脚本
- **局域网游戏（LAN）** — 围合、黑白棋、斗兽棋：UDP 多播发现 → HTTP 邀请握手 → 直连对战
- **单机游戏** — 贪吃蛇、2048、音游（节奏线）

### 远程输入（RemoteType）

手机作为 PC 的输入端，端到端加密（RT1 协议，两侧向量测试对齐）：

- 统一登录后列出「我名下的电脑」，点一下即连
- 自绘虚拟键盘 + 快捷键序列宏（多 chord + 毫秒间隔可调）
- 全文同步管线：断线静默重连、焦点丢失一键重放

### 统一登录（authhub）

- 原生登录表单 + PKCE，支持扫码批准（手机扫 PC 上的码）
- token 层双签发方（登录态与业务 token 各归其位）
- e2ekv 客户端加密（PBKDF2 / AES-GCM），服务端只见密文

### Lab 实验室

- **49 个实验性 Demo**，经 IoC 容器（`lab_container`）统一注册，覆盖工具、游戏、UI 原型、网络、AI 等类别
- **可钉选 / 可重排 / 可搜索的快捷底栏**：钉选 demo 直达，钉选未溢出时末位槽直连设置
- **DemoSessionHost 会话托管**：退出页面不断连、回前台自动重连、空闲回收协程
- 48 张主题化 SVG demo 图标（主色 / 强调色随主题重染，启动期预热）

### 主题系统

六套主题：**暮紫 · 茶禅 · 墨白 · 粉雾 · 柠檬鼠尾草 · 宝蓝**

三层架构：`tokens/`（每主题一份 ColorScheme 数据）→ `strategy/`（从 scheme 派生 UI 角色的规则层：全局 6 角色、对弈棋盘 11 角色、国象棋盘 13 角色、俄罗斯方块 / 团队头像 / 灯具护眼）→ `extensions/`（ThemeExtension 注入）。切主题即换 scheme，全角色自动重派生。

### fr:// 路由

全局深链协议，原生与 Flutter 双向可达：

```
fr://lab                  # Lab 页
fr://lab/demo/clock       # 直达指定 demo
fr://timetable            # 课程表
fr://share/receive        # 系统分享接收
```

原生 MethodChannel 调用经 `FrMethodChannelTranslator` 统一翻译为 fr:// URL 后分发。

## 技术栈

- **框架**: Flutter 3.41.4 stable（CI 构建版本）/ Dart SDK ^3.11.1
- **状态管理**: Riverpod 2（Notifier）+ Provider
- **依赖注入**: get_it（Lab IoC 容器）
- **本地存储**: Hive + SharedPreferences
- **网络**: http + web_socket_channel（Relay v3）、UDP 多播（LAN 发现）
- **加密**: crypto + cryptography（e2ekv 客户端加密、RT1 端到端协议）
- **后端**: Supabase（AI 聊天）+ 自建 goframe API（KV / 房间 / 文件 / 下载 / OIDC）+ authhub（统一登录）+ mn-rt（远程输入）
- **游戏 / 动画**: Flame、Rive
- **原生桥接**: MethodChannel、Overlay Window、home_widget、FFI（Oboe 节拍器）
- **图标**: flutter_svg（demo 图标集主题化重染）

## 项目结构

```
lib/
├── main.dart                    # 应用入口（初始化 / 全局错误兜底 / fr:// 分发）
├── app_lifecycle/               # 前后台信号、crash log、APK 启动钩子、MethodChannel 翻译、MainScreen 壳
├── api/                         # API 模块（目录即后端）
│   ├── authhub/                 #   统一登录（PKCE / 扫码批准 / 会话托管）
│   ├── goframe/                 #   自建后端（KV / 房间 / 文件 / 下载 / OIDC / AI / 群组）
│   ├── remotetype/              #   远程输入凭据
│   ├── token/ interceptors/     #   token 双签发方 + 拦截器链
│   └── minimax/ notion/ pi/ github/ user/   # 第三方服务
├── core/                        # 核心功能模块
│   ├── ai_chat/                 # AI 聊天（pi 后端 / 格式化 / OCR / 系统消息）
│   ├── theme/                   # 六主题三层架构（tokens → strategy → extension）
│   ├── nav/                     # 可钉选快捷导航（目录 / 钉选状态 / 图标解析）
│   ├── schema/                  # fr:// 深链导航（FrNavigator）
│   ├── focus/                   # 番茄钟
│   ├── timetable/               # 课程表（DDD 架构：data / domain / presentation）
│   ├── note/                    # 块编辑器笔记
│   ├── game_kit/                # 游戏公共设施（皮肤 / 对局壳）
│   ├── game_audio/              # 游戏音频
│   ├── net_engine/              # 传输引擎（lan / relay_v3 / services）
│   ├── net_p2p/                 # P2P 业务层（LAN 走 pub/sub，Relay 走 v3 快照）
│   ├── message_net/             # 消息网络
│   ├── chess/ go/ gomoku/ jungle_chess/ reversi/ sudoku/    # 棋类业务
│   ├── surround_game/ tetris/ coup/ team_card/ cowrite/     # 房间游戏业务
│   ├── line/                    # 音游（节奏线）
│   ├── body/ doubletime/ gallerymanage/ github/ novel_reader/
│   └── share_receive/ storage/ word_drag/ design/ color/
├── lab/                         # 实验室框架
│   ├── lab_container.dart       # IoC 容器 + DemoPage 注册契约
│   ├── lab_bootstrap.dart       # 49 个 demo 集中注册
│   ├── demo_session_host.dart   # demo 会话托管（不断连 / 空闲回收）
│   └── demos/                   # 49 个 demo 页面
├── native/                      # 原生桥接（home_widget 桌面小组件 / overlay 悬浮窗）
├── screens/                     # 壳层页面（chat / profile / settings，游戏中心与 Lab 入口在此）
├── services/                    # 业务服务（AI 聊天 provider / 远程输入 / 消息策略 / 节拍器 / APK 下载）
└── widgets/                     # 通用组件（lab_demo_icon 主题化 SVG / global_ring / 聊天组件）
```

## 应用导航

主壳为**可钉选快捷底栏**：所有 demo 与系统入口可钉选 / 重排 / 搜索，IndexedStack 保活钉选页；钉选数不超容量且设置未被钉选时，末位槽直连「设置」。桌面小组件与系统分享经 MethodChannel → fr:// URL → `FrNavigator.handle` 分发（CLEAR_TOP 防栈累加）。

## 开发指南

### 环境要求

- Flutter stable（CI 锁定 3.41.4），Dart SDK ^3.11.1
- Android 构建仅保留 arm64-v8a（`abiFilters` 已限定，剔除插件多余 ABI）
- 日常调试以 Web 构建为主验证方式

### 常用命令

```bash
# 获取依赖
flutter pub get

# 代码分析
flutter analyze

# Web release 构建（主要验证方式）
flutter build web --release

# JSON / Hive 序列化代码生成
dart run build_runner build

# 测试（含 RT1 协议两侧向量测试）
flutter test
```

### CI/CD

| Workflow | 触发 | 说明 |
| -------- | ---- | ---- |
| `build-apk.yml` | push / PR 到 master | Flutter 3.41.4 + Java 17，release 签名（keystore 走 secrets），产物上传 artifact |
| `build-apk-v2.yml` | 手动 | 可调试变体，支持 `--split-per-abi` arm64 单架构瘦身构建 |
| `deploy-web.yml` | 提交信息含 `web` 或手动 | Web 构建部署到生产环境 |

### 工作流程约定

1. 代码修改后先 `flutter analyze` 确认无编译错误（本地 analyze 通过 ≠ 远程可编译，注意提交工作区所有关联修复）
2. 变更文件单独 `add` / `commit`（禁止 `git add .`）
3. Conventional Commits 规范，模块前缀与 CHANGELOG scope 一致（`remotetype` / `ui` / `lab` / `auth` / `theme` …）
4. 用户可感知变更同步记录到 `CHANGELOG.md`（feat / fix / refactor，docs / chore 不记）

## 项目 Skill 体系（`.claude/skills/`）

Claude 与项目协作时使用的领域知识索引，按主题采用「主 SKILL.md + references/」渐进式结构：

### 工作流总入口

| Skill | 用途 |
| --- | --- |
| `flutter-work-flow` | Flutter 开发总入口，所有 dart-flutter 问题优先加载（fr:// 路由 / Lab 容器 / 游戏中心 / API 模块等扩展 SOP） |
| `flutter-debug-logging` | 错误 / 异常行为排查（战略性日志） |
| `pr-workflow` | PR 管理工作流 |
| `gh-upstream-release` | Fork 模式下 squash + push + PR 发版 |
| `codebase-module-generator` | 分析模块结构生成防腐蚀规范 skill |

### 功能域

| Skill | 用途 |
| --- | --- |
| `net-p2p-protocol-playbook` | Relay / LAN / 快照 / action 流协议；v1 事件驱动与 v2/v3 快照驱动 |
| `relay-lua-state-machine` | Relay-v3 Lua 状态机接入（新增互联网房间业务） |
| `block-note-core` | 块编辑器核心架构（Block 模型 / RichText / 编辑器策略） |
| `flutter-home-widget-realtime-sync` | home_widget 实时值推送到 Android 桌面小组件 |
| `flutter-message-workflow` | message_strategy 系统添加新消息类型 |
| `flutter-ui-theme-architecture` | 主题三层架构 |
| `flutter-ui-game-skin-pipeline` | 游戏皮肤管线 |
| `flutter-ui-styles` | 样式工程方案 |
| `flutter-android-cpp-audio-bridge` | Android C++ 音频桥接（FFI / Oboe 节拍器） |
| `rive-skills` | Rive 动画（含本项目 Flutter DataBind 特化） |

### 平台 / 原生

| Skill | 用途 |
| --- | --- |
| `android-media-projection-fix` | Android 14+ MediaProjection 悬浮窗截屏排查 SOP |
| `android-icon-processing` | 自适应图标前景图处理（洪泛法 / 岛屿算法） |

## 许可

MIT
