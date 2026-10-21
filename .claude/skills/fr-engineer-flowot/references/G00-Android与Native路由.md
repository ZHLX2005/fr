---
name: G00-Android与Native路由
description: FR Android 特殊组件与 Flutter/native 桥接的大序列路由。按 Ga 桌面 widget、Gb MediaProjection/FGS、Gc 图标处理子序列定位细节。
---

# G00 — Android 特殊组件与 Native 大序列路由

> G 是 Android/native 大序列。Ga、Gb、Gc 为子序列，均从 01 开始。本文件维护所有子序列成员路由。

## Ga — 桌面 Widget

| 文档 | 何时读取 |
|---|---|
| [[Ga01-桌面Widget实时同步]] | 新建桌面 widget 或排查实时数据不更新/耗电时 |
| [[Ga02-Widget点击深链]] | widget 点击需打开 app 内指定页面时 |
| [[Ga03-Widget标签与Manifest]] | 新增 Provider、label 或 Manifest 配置时 |
| [[Ga04-Widget样式规范]] | 调整 AppWidget/RemoteViews 外观时 |

## Gb — MediaProjection、悬浮窗与前台服务

| 文档 | 何时读取 |
|---|---|
| [[Gb01-MediaProjection前台服务]] | Android 14+ 截屏、权限申请、FGS 初始化顺序时 |
| [[Gb02-FGS异常排查案例]] | SecurityException、服务类型不匹配或设备 APK 行为异常时 |
| [[Gb03-Android14悬浮截屏常驻模式]] | 实现或维护常驻 VirtualDisplay/截屏 service 模式时 |

## Gc — Android 图标资产

| 文档 | 何时读取 |
|---|---|
| [[Gc01-Android自适应图标处理]] | 从原图处理 adaptive icon foreground、去边色或配置图标资源时 |

## Native 工程约束

- Flutter/native bridge 工具统一放在 `lib/native/`，业务层不散落平台通道细节。
- 修改 `android/`、Kotlin、C++、Manifest、Gradle 或 Android 资源后必须执行 `flutter build apk`；`flutter analyze` 不覆盖原生配置链路。
- 核验权限、Foreground Service 类型、SDK 版本分支和实际 service lifecycle，不机械复制历史修复片段。
- 图标辅助脚本在 `.claude/skills/fr-engineer-flowot/scripts/`：`flood_fill_cli.py`、`generate_android_icon.py`。
