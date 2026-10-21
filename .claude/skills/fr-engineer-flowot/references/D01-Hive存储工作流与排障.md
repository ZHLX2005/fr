---
name: D01-Hive存储工作流与排障
description: FR Hive repository 接入、数据读写、BoxDescriptor 面板注册和常见错误排查。任何 feature 需要本地持久化时读取；调用方只消费领域 API，不直接调用 Hive 全局 API。
---

# D01 — Hive 存储工作流与排障

> **何时读取**：新增本地持久化、Hive 数据读写/删除异常、typed adapter/typeId 冲突、StorageRegistry 面板未出现、旧存储代码迁移时。
>
> 关联：[[D00-Hive存储路由]]、[[D02-Hive-BoxDescriptor注册制]]、[[D03-Hive新模块Checklist]]。

## 核心原则

Hive 是实现细节。UI/业务调用方只依赖 repository 的领域 API，不得直接调用 `Hive.box()`、`Hive.openBox()`、`Hive.registerAdapter()`，也不得从 repository 取得 `Box` 句柄。

在存储基础层内部：

- `HiveStore.instance.openTyped/openUntyped` 负责 Hive 初始化、typed adapter 注册、box 打开及句柄缓存。
- Feature repository 持有私有 Box，负责数据 schema、读写转换和领域 API。
- `StorageRegistry` + `BoxDescriptor` 让 Lab 存储分析面板能观察已注册的 box；新 feature 的面板支持不是散落添加面板分支。

真实文件：`lib/core/storage/hive/hive_store.dart`、`hive_repository.dart`、`lib/core/storage/box_descriptor.dart`、`storage_registry.dart`；示例见 `body_record_repository.dart`、`price_compare_repository.dart`、`timetable_repository.dart`。

## 新增持久化模块步骤

1. **查现有实现**：对照同类 model/repository 和 `hive_type_ids.dart`，确认是否需要 typed adapter，避免重复存储域。
2. **定义领域 API**：列出业务需要的 load/save/update/delete 方法；调用方不传 Hive Box，也不依赖 Hive key 操作。
3. **建立 model/schema**：typed model 使用 `@HiveType(typeId: HiveTypeIds.xxx)`、稳定的 `@HiveField` id；当前项目走 `hive_generator` + build_runner 生成 `.g.dart`。
4. **实现 repository**：内部通过 `HiveStore.instance.openTyped<T>(..., adapter: TAdapter(), typeId: HiveTypeIds.xxx)` 或 `openUntyped()` 打开；Box 句柄私有。
5. **注册存储描述**：repository 初始化时注册 `BoxDescriptor`；typed descriptor 用正确的 TypeId 和 HiveStore 打开回调，formatter 单独提供可读字符串。
6. **接入应用初始化**：沿用当前项目 feature 启动路径，只初始化一次；初始化失败应显式处理，不在 widget build 中补 init。
7. **验证**：按变更运行 build_runner、repository 测试和 `flutter analyze`；不执行 `flutter run`。面板验证按项目批准的集成/设备测试路径。

完整逐项 checklist 与可复用结构见 [[D03-Hive新模块Checklist]]；Registry 责任边界见 [[D02-Hive-BoxDescriptor注册制]]。

## 故障排查

| 症状 | 优先检查 | 修复方向 |
|---|---|---|
| `HiveError: You must provide your type` | 当前 repository 是否通过 typed `HiveStore.openTyped<T>`；descriptor 是否匹配 typed box | 从调用方删除直接 Hive 访问；检查 adapter/typeId/descriptor 的泛型一致性 |
| `HiveError: Cannot read from closed box` | repository 是否初始化、是否存在私自关闭或绕过 Store 打开的路径 | 修复 repository 生命周期；统一经 HiveStore 获取句柄 |
| typeId 冲突或旧数据解码失败 | `hive_type_ids.dart` 是否重复、字段编号是否改变、生成文件是否同步 | 恢复稳定 typeId/field 编号并按项目流程重新生成；必要时实现迁移 |
| 新 box 未出现在 Lab 存储分析 | feature repository init 是否执行、Registry 是否注册、descriptor name 是否与 boxName 相同 | 在初始化时注册 `BoxDescriptor`；不添加 storage manager 特判 |
| 显示 `Instance of ...` | typed descriptor 是否提供 formatter，返回值是否为可读文本 | 增加 `formatValue` 或 formatter helper |
| 删除后数据仍在 | repository 是否使用了与保存时相同的 key 类型/规范化 | 在 repository 内把显示 key 转为真实领域 key；不要让面板/UI直接猜 key 类型 |
| Hive write/read `part` 或 `.g.dart` CI 失败 | 依赖版本、builder 支持语法、生成文件是否更新 | 跑仓库规定的 build_runner，按 CI 报错定位 builder 不兼容语法；历史排障文档已随旧 skill 归档，以当前报错输出为准 |

## 存储面板边界

已注册 box 的 details/delete/clear 由 BoxDescriptor 提供的内部适配操作执行。`Hive.box<T>()` 等 Hive API 只允许在这类存储基础实现内按对应 generic 类型使用；业务层不因面板能力而获得直连 Hive 的许可。

- 面板不负责编辑业务对象；如需复杂查询/编辑，应添加 repository API 与业务 UI。
- 不再给 `StorageManager` 维护 per-feature typed 分支。
- 新模块不可依赖“未注册 box”的 legacy fallback。

## 历史文档注意

曾有手写 TypeAdapter、字面量 typeId、`CalendarHive.events`、页面直接 `Hive.box()` 的示例。这些反映旧演进节点，不是当前 FR 新模块范本。当前 TypeAdapter 用 `hive_generator`，当前 repository 通过 `HiveStore` 封装打开和全局注册。
