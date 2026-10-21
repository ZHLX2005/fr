---
name: fr-engineer-flowot
description: FR 项目级 Flutter 工程总入口。涉及 FR 模块开发、Lab/游戏中心/Chat、fr:// 路由、API、RelayLua、Hive 仓库与存储、统一 UI/主题、外部资源/皮肤资产、Android 原生组件或 Oboe 音频时加载；先按 A–H 序列路由到对应 SOP。仅适用于 D:\code\a_dart\prj\fr。
---

# FR Engineer Flow — 工程总入口

> **适用范围**：仅适用于 `D:\code\a_dart\prj\fr`。本文档只做工程原则和 A–H 路由；操作细节在 `references/`。
>
> 每项内容以 FR 当前实现为准，不能仅凭旧 skill 或历史示例推断。遇到文档和代码冲突时先核实真实实现，再更新文档。

## 序列路由

| 序列 | 领域 | 入口 | 何时读取 |
|---|---|---|---|
| **A** | FR 入门、模块开发 SOP 与常见业务容器 | [[A00-FR模块开发路由]] | 开始 FR 业务开发、确认模块归属/容器、需要理解 Lab、游戏中心、Chat、登录能力或 `fr://` 时 |
| **B** | 简单业务场景参考模块 | [[B00-业务场景路由]] | 实现较小、可复用的业务功能时；当前收录消息策略与 IM 会话持久化 |
| **C** | RelayLua 多人业务与联机协议 | [[C00-RelayLua路由]] | 编写 Relay-v3 Lua 房间、联机游戏、大厅或 action/snapshot 协议时 |
| **D** | Hive 存储架构与模块接入 SOP | [[D00-Hive存储路由]] | 新增/修改本地持久化、Hive Box、仓库 API、StorageRegistry 或存储面板时 |
| **E** | UI 样式、设计系统与统一色彩 | [[E00-UI与色彩路由]] | 设计/实现 UI、主题配色或评审颜色使用时 |
| **F** | 外部资产管理、皮肤与公开资源管线 | [[F00-外部资产管理路由]] | 导入/发布皮肤、封面、曲库、表情包或排查客户端资源加载/缓存时 |
| **G** | Android 特殊组件与 Flutter/native 桥接 | [[G00-Android与Native路由]] | 改桌面 widget、MediaProjection/悬浮窗、图标、Manifest、Kotlin/C++/JNI/FFI 时 |
| **H** | 音频、Oboe 与节拍器生命周期 | [[H00-音频路由]] | 低延迟音频、Oboe、C++ 音频回调、WAV 采样或跨页面音频 service 时 |

## FR 开发约束速记

1. **先定位再改动**：先读 A00 与 FR 业务地图，再进入对应容器/模块 SOP；不以 demo 数量或旧目录快照代替当前代码核验。
2. **模块形态**：`lib/lab/demos/` 的 demo 默认保持单文件；超过 400 行才按项目约定拆到 `lib/lab/demos/<模块名>/`。高扩展模块放 `lib/core/<模块>/`，由 Lab 页面导入；除非用户明确指定，不擅自选择另一种结构。
3. **路由集中**：新增页面或可被外部入口调用的页面按 A 序列使用 `fr://` 路由注册规范；避免 widget 自行解析 URL 或绕过项目路由中心。
4. **存储封装**：业务 UI 不直接使用 Hive 全局 API。通过 feature repository/项目标准存储 API 暴露需要的操作；初始化、adapter、BoxDescriptor 注册与全局面板按 D 序列统一。
5. **视觉统一**：`lib/` 新增 UI 禁止裸写颜色 hex；使用项目 ColorScheme、ColorStrategy 或明确的颜色特例策略，详见 E 序列。
6. **原生改动验证**：修改 `android/`、Kotlin、C++、Manifest 或资源配置时，`flutter analyze` 不足以验证原生链路；按相关 SOP 执行 `flutter build apk`。
7. **质量与交付**：遵循仓库当前测试、codegen、CHANGELOG、Git 及提交约定；执行提交操作前逐项核对工作区，只处理本次任务文件。不得把现有其他工作区改动混入任务。
8. **文档审查**：存在前置条件、身份/权限、数据流或生命周期不明时，先标注待核验事实；不把“登录功能 demo”写成全局登录守卫，也不把 Lab、游戏中心、Chat 断言为需登录容器，除非真实代码证明如此。

## 维护规则

- `SKILL.md` 只保留原则和 A–H 大序列入口；每份 `references/` 文档直接平铺在同一目录，文件名以其序列编号开头（如 `A01-...md`、`Ca01-...md`、`Ga01-...md`）。
- **只有大序列使用 `00` 总路由**：A00–H00 各自维护所辖全部子序列与成员路由；子序列不创建 `00` 文件，成员从 `01` 开始。
- 编号范围：A00 维护业务 A01–A08；B00 维护 Ba 子序列；C00 维护 RelayLua 的 Ca/Cb/Cc；E00 维护 Ea/Eb；F00 维护 Fa；G00 维护 Ga/Gb/Gc；H00 维护 Ha。D 是单一 Hive 子域，由 D00 维护 D01–D03。
- 同名 A/B/C 在大序列之间不能相互替代：用有命名空间的子序列前缀（如 `Ca01`、`Ea03`、`Fa02`）避免平铺目录时冲突。
