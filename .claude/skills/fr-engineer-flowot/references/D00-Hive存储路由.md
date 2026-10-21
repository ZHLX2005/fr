---
name: D00-Hive存储路由
description: FR Hive 持久化架构与新模块接入入口。新增本地存储、box、TypeAdapter、repository 或 Lab 存储面板能力前先读取；强制经标准 repository/API 封装，不让业务/UI 散调 Hive 全局 API。
---

# D00 — Hive 存储与 repository 路由

> 适用范围：仅适用于 `D:\code\a_dart\prj\fr`。当前实现真实路径在 `lib/core/storage/`。

## 核心原则

**Hive 是存储实现细节；全局业务代码只消费 feature/repository 提供的标准 Dart API。** `Hive.openBox`、`Hive.box`、adapter 注册等集中在 `lib/core/storage/hive/` 的 store/repository 或明确的存储适配边界内；不要从 widget、页面或任意业务模块直接访问 Hive 全局 API。标准 API 应使用有领域语义的 repository 方法，不将 Box 句柄作为全局接口泄露。

- 当前共享基础：`lib/core/storage/hive/hive_store.dart`（统一初始化与打开句柄）、`hive_repository.dart`（仓库标记接口）、`lib/core/storage/storage_registry.dart`、`box_descriptor.dart`。
- 真实范例：`body_record_repository.dart`、`timetable_repository.dart`、`price_compare_repository.dart`。新增模式先比对它们及模型 adapter 生成方式。
- 新 Box 须通过 `StorageRegistry.register(BoxDescriptor<T>(...))` 注册，让 Lab 存储分析面板读取；不要为每个业务修改 `storage_manager.dart` 或面板 UI。

## 何时读哪个文档

| 文档 | 何时读取 |
|---|---|
| [[D01-Hive存储工作流与排障]] | typed box/API、打开/关闭、删除 key、面板显示或旧例子迁移时 |
| [[D02-Hive-BoxDescriptor注册制]] | 理解 Registry/Descriptor/StorageManager 的责任边界时 |
| [[D03-Hive新模块Checklist]] | 新建带 Hive 持久化的 feature/repository 时 |

## 校验优先级

1. 先检查当前 `pubspec.yaml` 与同类模型，确认 adapter 是 `hive_generator` / build_runner 生成，还是本项目明确的手写适配器例外；不得仅照抄历史文档中的手写示例。
2. typeId 使用 `lib/core/storage/hive_type_ids.dart` 集中常量；Box 名、展示名、formatter 使用模块唯一真相源。
3. `HiveStore` 负责基础打开/adapter 生命周期，repository 封装业务读写，StorageRegistry 描述面板可见能力；三者职责不得倒置。
4. 新 feature 的消费方只调用 repository 的 typed/domain API，不缓存或持有全局 Hive box。
5. `flutter analyze`/相关测试按变更范围执行；需要生成代码时按仓库流程运行 build_runner。禁止 `flutter run`。
