---
name: A08-FR工程开发与验证规范
description: FR 项目级 Flutter 业务实现、布局、代码生成、测试与交付检查清单。动手修改 FR 代码或准备验证/提交时读取。
---

# A08 — FR 工程开发与验证规范

> 适用范围：仅适用于 `D:\code\a_dart\prj\fr`。先定位模块并读取 A00/对应领域 SOP，再按本文件完成实现、验证和交付。应用代码和仓库当前指令优先于旧文档示例。

## 实现前

- [ ] 查看 `git status`，区分本任务改动与已有在制品；只编辑/提交本任务拥有的文件，不覆盖其他修改。
- [ ] 多文件/多阶段任务先列步骤、模块边界和验证项；避免无计划跨层重构。
- [ ] 先读目标功能附近实现、容器/注册机制与对应序列文档；复用真实项目模式，不从旧文档猜路径。
- [ ] `lib/lab/demos/` 下 demo 默认单文件；大于 400 行才拆到 `lib/lab/demos/<模块名>/`。用户指定高扩展方案时采用 `lib/core/<模块>/`，由 demo 页面组装调用。
- [ ] 模块常量按项目既有约定集中在对应 `const_*.dart`；native bridge 集中在 `lib/native/`；Hive 只经 D 序列 repository API。
- [ ] Lab demo 使用外层 DemoPage 提供的返回壳；不要重复添加返回按钮，例外模式按 A03/现有 demo 处理。

## UI 与布局

- 优先采用约束/自适应、百分比或可重排布局，避免窄屏溢出；可居中内容使用稳定的居中布局。
- 网格多行均分时，行内数量差距尽量不超过 1；不硬编码只适合当前宽度的绝对尺寸。
- `lib/` 新增 UI 不写裸 hex，消费项目 ColorScheme/Strategy，见 E00。
- 选择现成依赖前先核查项目是否已有等效组件或工具；新增依赖需检查 Android 权限/平台配置需求。

## 实现后验证

1. Dart 变更运行 `flutter analyze`；相关 feature 测试按变更范围运行。新建但未被当前导入图覆盖的 Dart 文件，也要纳入分析或显式编译/测试路径。
2. 提交代码前运行仓库当前 codegen 命令：`dart run build_runner build --delete-conflicting-outputs`。codegen/analyzer 版本可能不同，必须关注 CI Generate code 结果。
3. 不运行 `flutter run`。
4. 改 Android/Kotlin/C++/Manifest/Gradle/原生资源时，额外运行 `flutter build apk`；`flutter analyze` 无法验证该链路。
5. 核验依赖、权限、platform channel、Manifest、service type 与实际设备行为；只看 Dart 分析通过不代表原生配置已落地。
6. 新增功能或修复产生代码提交时，按仓库 `CHANGELOG.md` 当前格式追加记录，更新放在功能提交之前/同批。

## Git 与交付

- 修改前后都看 `git status`，提交前逐条核实每个路径都属于本任务。
- 只 `git add` 本任务明确拥有的文件；禁止 `git add .` / `git commit .`，避免把既有工作树删除或其他人的未提交改动混进提交。
- 使用仓库当前 Conventional Commits 约定；提交后遵循该项目已授权的 push/CI 流程。任务只要求文档/规划时，不擅自提交、推送或触发外部服务。
- 运行完成后如有未验证项，明确写在交付说明中，不把“文件已保存”声称为“构建通过”。

## 常见反模式

| 反模式 | 问题 | 修正 |
|---|---|---|
| demo 只有一个页面也先拆成多文件 | 注册/状态流散落，调试成本上升 | 单文件优先；超过约定阈值或职责确实独立再拆 |
| 为简单页面引入完整 core 抽象 | 过早架构化，与 Lab 入口脱节 | 先用 demo 级结构，用户指定高扩展项目除外 |
| 只跑 `flutter analyze` 就提交 generated model 改动 | CI codegen 使用不同 analyzer，可能失败 | 同步执行 build_runner 并检查生成文件与 CI |
| 调整 Android 原生文件后只看 Dart analyze | Kotlin/CMake/Manifest 错误漏检 | 必须 `flutter build apk` |
| `git add .` | 混入工作树现有删除/其他任务文件 | 明确 add 自己的文件列表 |
