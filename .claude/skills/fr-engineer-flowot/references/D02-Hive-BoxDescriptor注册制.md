---
name: D02-Hive-BoxDescriptor注册制
description: FR Hive StorageRegistry 与 BoxDescriptor 的职责边界、存储面板自动接管机制。理解面板读写/删除/清空或迁移历史注册代码时读取。
---

# D02 — Hive Registry、BoxDescriptor 与 StorageManager

> **适用范围**：仅适用于 FR 项目。此文只说明存储注册和 Lab 存储面板架构。新模块实现步骤见 [[D03-Hive新模块Checklist]]；常见读写排障见 [[D01-Hive存储工作流与排障]]。
>
> **实现真相**：`lib/core/storage/box_descriptor.dart`、`lib/core/storage/storage_registry.dart`、`lib/core/storage/storage_manager.dart`、`lib/core/storage/hive/hive_store.dart`。

## 责任边界

```text
UI / 业务模块
    │ 领域 API（listTopics / getRecords / saveDraft 等）
    ▼
Feature Repository
    ├── 私有 Box 句柄
    ├── HiveStore.instance.openTyped/openUntyped()
    └── StorageRegistry.register(BoxDescriptor(...))
                          │
                          ▼
StorageManager → Lab「存储分析」面板
                 列举 / 格式化 / 删除 / 清空
```

1. **Feature Repository**：掌握领域 schema、私有存储句柄和读写行为；向调用方暴露语义化的 Dart 方法，不暴露 `Box`，也不要求调用方了解 Hive。
2. **HiveStore**：唯一的基础 Hive 打开入口，统一 `initFlutter`、typed adapter 注册、typed/untyped box open 与句柄缓存。
3. **BoxDescriptor**：用名称、展示名、可选 typeId、打开回调、格式化/size 回调描述一个 box，并封装面板需要的查询与管理操作。
4. **StorageRegistry**：保存 feature 已注册的 descriptors；同名覆盖是幂等注册行为。
5. **StorageManager**：仅依注册表枚举 box 并汇总面板数据；不是业务 repository，也不应成为新增 feature 的硬编码分支目录。

## 新 Box 如何出现在面板

1. Feature repository 初始化时通过 HiveStore 打开自己的存储。
2. Repository 注册对应 `BoxDescriptor<T>` 到 `StorageRegistry`。
3. StorageManager 遍历注册表；descriptor 提供 key/value、formatter 与管理操作。
4. Lab 显示已注册 Box 的数量、大小、逐条内容，并按 descriptor 执行支持的删除/清空操作。

注册后通常无需编辑 `storage_manager.dart` 或 `storage_analyze_demo.dart`。如果面板未出现条目，检查 feature 初始化、descriptor name、storage open callback 和注册顺序。

## 实现约束

- UI 与一般业务代码**不得直接调用 Hive 全局 API**，包括 `Hive.box()`、`Hive.openBox()`、`Hive.registerAdapter()`；不得把 box 句柄当作全局服务 API。存储基础设施（`StorageManager` 的 legacy fallback、导入/导出子系统）是例外边界，新 feature 不得新增类似直连。
- HiveStore、repository、BoxDescriptor 是存储基础实现边界，内部为履行职责可通过对应泛型/descriptor 回调访问 Hive。
- 已注册 typed box 的 descriptor 必须保持正确的泛型、TypeId 与打开回调一致；untyped box 使用 untyped descriptor 路径。
- formatter 只生成可读文本，不返回 Widget、不承担颜色/主题设计。
- 新业务必须注册 descriptor，不能依赖 StorageManager 对未注册 box 的 legacy fallback。

## TypeAdapter 与 Box API 的当前规则

FR `pubspec.yaml` 使用 `hive_generator` 和 `build_runner`。当前 typed model 以 `@HiveType(typeId: HiveTypeIds.xxx)` 与 `@HiveField(...)` 声明，adapter 由生成流程产生。新模块：

1. 先查 `lib/core/storage/hive_type_ids.dart` 分配唯一 TypeId。
2. 参照当前模型与 repository 样式定义 schema，使用 codegen 生成 `.g.dart`。
3. 由 repository 把生成 adapter 交给 `HiveStore.instance.openTyped<T>(..., adapter: ..., typeId: HiveTypeIds.xxx)`。
4. 业务方调用 repository 的领域 API，不直接调用 Hive API 或持有 Box。
5. 初始化时注册 descriptor；typed descriptor 的 open callback 使用同一 repository/store 约定。

目前可核对的实现：

- `lib/core/body/models/body_record.dart` / `.g.dart`：generated TypeAdapter 与集中 typeId。
- `lib/core/storage/hive/body_record_repository.dart`：typed model repository，内部经 HiveStore 打开并注册 descriptor。
- `lib/core/storage/hive/price_compare_repository.dart`：untyped Map repository，box 句柄私有，仅暴露语义化方法。
- `lib/core/storage/hive/timetable_repository.dart`：多 untyped box、多空间与兼容逻辑，所有打开仍经 HiveStore。

## 面板能力边界

由 descriptor/manager 已提供的面板能力包括查看 key/value、formatter、估算大小、删除单条记录及清空整个 box。面板不是业务编辑器；复杂编辑、跨 box 查询、导入/导出应由专用 repository API 与 feature UI 实现。

## 历史实现不要复用

旧文档曾展示手写 `TypeAdapter`、日历 `typeId=90/91`、`CalendarHive.events` 静态 getter、repository 直接打开 Hive box，以及未注册 box fallback。这些用于解释历史演进，不是当前新增模块范本。当前 typeId 集中表只分配了实际现行项；不要将已经释放的历史值复制到新模型。
