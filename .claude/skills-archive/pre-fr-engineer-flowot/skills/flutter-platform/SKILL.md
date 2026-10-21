---
name: flutter-platform
description: FR 项目平台桥接层——Flutter ↔ Android 原生。覆盖三个子域：①桌面小组件（home_widget 不同步、AppWidget 不刷新、Chronometer 实时走字、widget 进程被杀、ClassNotFoundException、widget 点击深链、后台高耗电判定）②悬浮窗截屏（MediaProjection、Android 14+ Foreground Service、SecurityException/IllegalArgumentException、FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION、权限重复申请、PigmentFloatingManager）③自适应图标（app icon、adaptive icon 前景图处理、边缘去色、居中缩放、flutter_launcher_icons 配置）。涉及 Android 原生桥接、widget、截屏权限、应用图标时加载本 skill。
---

# flutter-platform — 平台桥接层总入口

> 本页只做路由。每个子域是一份完整的「原 skill 文档 + 序列化 refs」，按需进入。

## 子域总览（先读这里）

| 子域 | 路由页 | 内容 | 何时进入 |
| --- | --- | --- | --- |
| 桌面小组件 | `references/widget/flutter-home-widget-realtime-sync.md` | 3 refs：widget-click-deeplink（点击深链）/ widget-style-spec（样式规范）/ widget-label-and-manifest（label 与 manifest 注册） | home_widget 不同步 / widget 不刷新 / 加新 widget |
| 悬浮窗截屏 | `references/projection/android-media-projection-fix.md` | 1 ref：fgs-debug-cases（按异常类型分类排查 SOP） | MediaProjection / 悬浮窗截屏闪退 / FGS 类型不匹配 |
| 图标处理 | `references/icon/android-icon-processing.md` | 单文档：边缘色块分析 → 洪泛去色 → 岛屿算法 → 居中缩放 → adaptive icon XML | 处理应用图标 / 自适应图标前景图 |

## 路径约定（重要）

- 子域路由页与其 refs **同目录**。路由页正文里写的 `references/xxx.md` 一律按「同目录下的 xxx.md」理解（历史相对路径，迁移后语义不变）。
- 图标处理脚本在层根 `scripts/`（flood_fill_cli.py / generate_android_icon.py），从项目根执行：`python .claude/skills/flutter-platform/scripts/flood_fill_cli.py ...`。

## 跨子域规则（不进子域也要记住）

- **`updateWidget` 永远用 `qualifiedAndroidName`**（全限定类名）——`androidName` 对子包下的 Provider 必然 `ClassNotFoundException` 且异常被插件静默吞掉（90% widget bug 的根因）。
- **走字类实时值由原生 `Chronometer` 自走**，Flutter 只在状态切换时推一次——不要退回 1Hz 推送（会被系统判后台高耗电）。
- **MediaProjection FGS 用 `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` 常量 + `SDK_INT >= Build.VERSION_CODES.Q` 分支调 3 参 `startForeground`，低版本走 2 参兜底**——3 参重载 API 29 才存在，minSdk 24 下无条件 3 参会在 API 24-28 抛 `NoSuchMethodError`；不要硬编码 `0x00000020`（与 manifest `foregroundServiceType` 对齐，subset 不匹配见 PROJ 子域）。
- 改了 `android/` 目录任何内容必须 `flutter build apk` 验证（analyze 看不到 Kotlin/原生链路问题）。

## 协作 skill

- `flutter-biz`：业务层（widget 数据源 Provider、音频桥接的业务侧）
- `flutter-ui`：widget 样式走 ui 层皮肤/主题契约
- `key_board`：本 skill 的 ref 生命周期
