# D03 — 创建 FR Hive 持久化模块 Checklist

> **适用范围**：仅适用于 `D:\code\a_dart\prj\fr`。新增本地持久化 feature 时配合 [[D00-Hive存储路由]]、[[D01-Hive存储工作流与排障]] 和 [[D02-Hive-BoxDescriptor注册制]] 使用。
>
> **架构红线**：Hive 是实现细节。业务 UI 只调用领域 repository API，不接触 Hive 全局 API，不持有 Box 句柄。

## 1. 先定数据模型和 API

- [ ] 查找当前 feature、相似 repository 与既有持久化模型，确定本地数据是否应由 Hive 管理。
- [ ] 先设计调用方需要的操作（load/list/create/update/delete），不要以 `getBox()` 或 Box 暴露代替领域 API 设计。
- [ ] 选择 typed model 或已有 untyped Map/List 模式；定义缺失记录、无效旧值、key 格式和数据兼容策略。
- [ ] 约定谁负责初始化、谁持有唯一 repository；避免 UI 创建另一个 repository/Provider 实例竞争写入。

## 2. Typed Model 与 TypeAdapter

- [ ] 确认 `pubspec.yaml` 中当前 codegen 工具和同类模型写法。
- [ ] 在 `lib/core/storage/hive_type_ids.dart` 中分配未使用的 `HiveTypeIds.xxx` 常量；禁止在注解、adapter、注册表中写 typeId 数字字面量。
- [ ] 使用 `@HiveType(typeId: HiveTypeIds.xxx)`、稳定的 `@HiveField(n)` 和 `part '<model>.g.dart';`，按项目流程生成 adapter。
- [ ] 修改持久化字段时保留已有 field id；若需兼容旧数据，制定 migration 而不是复用/删除 field id。
- [ ] 不照搬旧文档中的手写 Adapter / 日历 90、91 示例，除非用户明确要求并经代码库验证为批准例外。

## 3. Feature Repository（唯一业务存储 API）

- [ ] Repository 内部持有私有 Box；所有 box 打开走 `HiveStore.instance.openTyped<T>(...)` 或 `openUntyped(...)`。
- [ ] typed adapter 注册、box open 和缓存统一交给 HiveStore；避免每个 feature 自己 `Hive.initFlutter()`。
- [ ] repository 对外只暴露语义化 API 和领域类型，不返回 `Box`，不要求调用方 import `hive_flutter`。
- [ ] async 写操作返回 `Future`，处理错误与重入；读取和删除对 key 类型/schema 保持一致。
- [ ] repository 命名、构造方式和初始化方式沿用同类 FR 实现；状态 singleton 或 DI 由业务架构决定，不将任意全局变量当成 Hive API。
- [ ] 多 box feature 仍由同一个 feature repository 或明确的 store/repository 组合管理，不让每个 widget 单独 open box。

## 4. StorageRegistry 面板注册

在 repository 初始化期间注册 `BoxDescriptor`：

- [ ] `name` 与 repository 的唯一 box 名一致；`displayName`/boxName 使用模块 metadata 常量。
- [ ] typed box 提供正确 `typeId`、`openTyped` callback 和 formatter；callback 必须按 storage boundary 方式打开该 box。
- [ ] untyped box 使用 untyped opener，不能用 typed 回调冒充。
- [ ] `formatValue` 返回易读 `String`；复杂逻辑拆到 formatter；不放 Widget、theme 色值或过长业务转换。
- [ ] 注册成功后不新增 `storage_manager.dart`、存储面板 UI 或硬编码 box-name 分支。

## 5. 应用集成与验证

- [ ] 把 repository init 加到当前 feature/应用的既有启动流程，避免页面 build 的隐式全局副作用。
- [ ] 全仓检查调用方没有直接 Hive API：`Hive.box(`、`Hive.openBox(`、`Hive.registerAdapter(` 只允许出现在存储基础设施/Repository 边界。
- [ ] 按需要测试首次初始化、重复初始化、增删改查、重启恢复、畸形旧数据、类型兼容和多实例行为。
- [ ] 修改 typed model/adapter 时运行 `dart run build_runner build --delete-conflicting-outputs`，再运行相关测试和 `flutter analyze`。
- [ ] 不运行 `flutter run`。此清单是实现流程，不要求每种 feature 都在面板 UI 中手动验证；用当前项目可用的测试/集成路径验证。
- [ ] 若同时改 `android/` 原生实现，按 G00 执行 `flutter build apk`。

## 当前实现参考

- `lib/core/storage/hive/hive_store.dart`：Hive 初始化、typed/untyped open、adapter guard 与 box cache。
- `lib/core/storage/hive/hive_repository.dart`：标识 Hive repository 的 `boxName` 契约。
- `lib/core/storage/hive/body_record_repository.dart`：generated adapter + `HiveStore.openTyped` + `BoxDescriptor`。
- `lib/core/storage/hive/price_compare_repository.dart`：私有 untyped box 与语义化 repository API。
- `lib/core/storage/hive/timetable_repository.dart`：多 box 与持久化兼容范例。
- `lib/core/storage/hive_type_ids.dart`：TypeId 唯一真相源。

## 禁止模式

| 禁止模式 | 应采用 |
|---|---|
| 页面直接 `Hive.box/openBox/registerAdapter` | 页面调用 feature repository API |
| repository getter 把 Box 交给 widget/global caller | 只返回领域模型或操作结果 |
| widget 自行判断 Hive init/open 状态 | repository/store 封装初始化、开箱与错误 |
| 每个 feature 自己写重复 adapter/硬编码 typeId | codegen + `HiveTypeIds` 常量 + HiveStore |
| `StorageManager` 针对业务 Box 加 if/else | repository 注册 `BoxDescriptor` |
| 新代码依赖未注册 box fallback | 在 feature init 注册 descriptor |
