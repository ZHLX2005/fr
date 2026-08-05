# Hive 存储 + 集中可视面板设计

> **主题**：在 Flutter 项目中使用 Hive 做结构化存储，并通过 StorageManager 集中观察所有 Hive Box 的内容。
> **适用场景**：需要多个自包含的 typed box、并希望在 Lab → 存储分析 页面统一观察数据时。
>
> **架构演进**：2026-07-27 之前 `StorageManager` 是硬编码 + if-else 分支的（每加一个 typed box 要改 4-5 处）。之后重构为 **BoxDescriptor 注册制**：每个 feature 只在自己的 `init()` 里注册一次，StorageManager 变成纯查询代理，不再需要修改。

## 架构总览

```
项目
├── Hive Boxes（每个 feature 一个或几个）
│   ├── timetable_config     (非 typed, key-value)   ← 遗留
│   ├── timetable_items      (非 typed, key-value)   ← 遗留
│   ├── body_records         (typed, BodyRecord)     ← 已注册
│   ├── calendarEvents       (typed, Event)          ← 已注册（日历 demo）
│   ├── calendarPeople       (typed, Person)         ← 已注册（日历 demo）
│   └── calendarViewState    (非 typed, key-value)   ← 已注册（日历 demo）
│
├── core/storage/
│   ├── hive_type_ids.dart    ← typeId 集中表（唯一真相源；@HiveType(typeId:) 必引用此）
│   ├── box_descriptor.dart   ← BoxDescriptor<T>（自描述：name/displayName/typeId/openTyped/formatValue）
│   ├── storage_registry.dart ← 全局注册表（feature 只需注册一次）
│   └── storage_manager.dart  ← 纯查询代理（遍历 registry，不再有 if-else）
│
└── Lab → 存储分析（storage_analyze_demo.dart）
    自动展示：每个已注册 box 一个卡片 + keyCount + size + 展开后按 formatValue 显示
```

## 1. 设计 Hive 存储（以日历 demo 为例）

### 1.1 手写 TypeAdapter

TypeAdapter 是 Hive 序列化 typed object 的方式。不需 build_runner，手写：

```dart
// event_adapter.dart（typeId=90，避开项目已有 0-9）
class EventAdapter extends TypeAdapter<Event> {
  @override
  final int typeId = 90;

  @override
  Event read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var i = 0; i < count; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return Event(
      id: fields[0] as String,
      type: EventType.values[fields[1] as int],
      title: fields[2] as String,
      // ... 按 write 的顺序读
    );
  }

  @override
  void write(BinaryWriter writer, Event obj) {
    writer
      ..writeByte(15) // 字段总数
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.type.index)
      // ... 顺序必须和 read 一致
      ..writeByte(14)..write(obj.createdAt);
  }
}
```

**规则**：write 和 read 的 field byte 顺序必须完全一致；字段总数在写的前面用 `writeByte(N)` 标记，读时同样先读 `reader.readByte()` 做校验。

### 1.2 集中初始化 + 注册到 Registry

所有 box 统一在一个地方注册 adapter、打开 box、**并调 `StorageRegistry.register` 一次性告知面板**：

```dart
// calendar_hive.dart
import '../../../../core/storage/box_descriptor.dart';
import '../../../../core/storage/storage_registry.dart';

class CalendarHive {
  static const eventsBoxName = 'calendarEvents';
  static const peopleBoxName = 'calendarPeople';
  static const viewStateBoxName = 'calendarViewState';

  static const _eventTypeId = 90;
  static const _personTypeId = 91;

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    // Hive Flutter 兜底（如果 StorageManager 已经 init 过则忽略）
    try { await Hive.initFlutter(); } catch (_) {}

    // 注册 adapter（幂等）
    if (!Hive.isAdapterRegistered(_eventTypeId)) {
      Hive.registerAdapter(EventAdapter());
    }
    if (!Hive.isAdapterRegistered(_personTypeId)) {
      Hive.registerAdapter(PersonAdapter());
    }

    // 打开 box（已开则跳过）
    if (!Hive.isBoxOpen(eventsBoxName)) {
      await Hive.openBox<Event>(eventsBoxName);
    }
    if (!Hive.isBoxOpen(peopleBoxName)) {
      await Hive.openBox<Person>(peopleBoxName);
    }
    if (!Hive.isBoxOpen(viewStateBoxName)) {
      await Hive.openBox(viewStateBoxName);
    }

    // ★ 关键：注册到 StorageRegistry —— 面板自动接管
    StorageRegistry.register(BoxDescriptor<Event>(
      name: eventsBoxName,
      displayName: '日历事件',
      typeId: _eventTypeId,
      openTyped: () => Hive.openBox<Event>(eventsBoxName),
      formatValue: (v) {
        final e = v as Event;
        return '标题: ${e.title}\n类型: ${e.type.name}\n日期: ${e.month}月${e.day}日';
      },
    ));
    StorageRegistry.register(BoxDescriptor<Person>(
      name: peopleBoxName,
      displayName: '人物档案',
      typeId: _personTypeId,
      openTyped: () => Hive.openBox<Person>(peopleBoxName),
      formatValue: (v) {
        final p = v as Person;
        return '姓名: ${p.name}\n关系: ${p.relation.name}';
      },
    ));
    StorageRegistry.register(BoxDescriptor(
      name: viewStateBoxName,
      displayName: '日历视图状态',
      openUntyped: () => Hive.openBox(viewStateBoxName),
    ));

    _initialized = true;
  }

  // 泛型 getter
  static Box<Event> get events => Hive.box<Event>(eventsBoxName);
  static Box<Person> get people => Hive.box<Person>(peopleBoxName);
  static Box get viewState => Hive.box(viewStateBoxName);
}
```

### 1.3 Provider 读写（不手动全量 save）

Hive Box 每次 `put/delete` 自动持久化，不需要全量序列化：

```dart
// ✅ 正确方式
Future<Event> add(Event e) async {
  await CalendarHive.events.put(e.id, e);  // 自动写磁盘
  return e;
}

// ❌ 错误方式（SharedPreference 思维）
List<Event> _events = [];
Future<void> save() async {
  final json = _events.map((e) => e.toJson()).toList();
  await prefs.setString('key', jsonEncode(json));  // 全量重写
}
```

## 2. StorageManager 集中面板（注册制原理）

`storage_analyze_demo.dart` 是 Lab → 存储分析 的入口。**StorageManager 本身不需要修改，它只是 Registry 的查询代理。**

### 2.1 BoxDescriptor —— 单个 box 的自描述结构

```dart
// core/storage/box_descriptor.dart
class BoxDescriptor<T> {
  final String name;                                    // Hive 真实 box 名
  final String displayName;                             // 面板卡片显示的中文名
  final int? typeId;                                    // null 表示非 typed
  final Future<Box<T>> Function()? openTyped;           // typed 打开器
  final Future<Box> Function()? openUntyped;            // 非 typed 打开器
  final String Function(dynamic)? formatValue;          // 每条 key 的显示格式
  final int Function(dynamic)? estimateSize;            // 字节大小估算（可选）

  bool get isTyped => typeId != null;

  Future<void> ensureOpen() async { ... }               // 若未打开则打开
  BoxBase getBox() => isTyped ? Hive.box<T>(name) : Hive.box(name);  // 自动泛型
  Iterable<dynamic> get keys => getBox().keys;
  dynamic get(dynamic key) => isTyped ? Hive.box<T>(name).get(key) : Hive.box(name).get(key);
  int get length => getBox().length;
  Future<void> delete(dynamic key) => getBox().delete(key);
  Future<void> clear() => getBox().clear();
}
```

**关键设计**：`isTyped` 分支封装在 BoxDescriptor 内部；外部调用者（StorageManager）不需要知道 T 是什么，就能获取值、遍历、删除。

### 2.2 StorageRegistry —— 全局注册表

```dart
// core/storage/storage_registry.dart
class StorageRegistry {
  static final Map<String, BoxDescriptor> _boxes = {};

  static void register<T>(BoxDescriptor<T> d) {
    _boxes[d.name] = d;  // 幂等：重复注册会覆盖
  }

  static Iterable<BoxDescriptor> get all => _boxes.values;
  static BoxDescriptor? get(String name) => _boxes[name];
  static bool has(String name) => _boxes.containsKey(name);
}
```

### 2.3 StorageManager —— 纯查询代理

`StorageManager` 遍历 `StorageRegistry.all`，通过 `BoxDescriptor.get/keys/formatValue` 展开每个 box 的详情：

```dart
// storage_manager.dart 核心逻辑
List<String> _allBoxNames() =>
    StorageRegistry.all.map((d) => d.name).toList();  // 全部来自注册表

Future<List<KeyDetail>> getKeyDetails(StorageType type, {String? boxName}) async {
  for (final name in boxName != null ? [boxName] : _allBoxNames()) {
    final d = StorageRegistry.get(name);
    if (d != null) {
      for (final key in d.keys) {
        final value = d.get(key);
        result.add(KeyDetail(
          key: '$name/$key',
          value: d.formatValue != null && value != null
              ? d.formatValue!(value)     // ← feature 自定义的格式化
              : _formatValue(value),
          rawValue: value,
          size: d.estimateSize != null && value != null
              ? d.estimateSize!(value)
              : _estimateSize(value),
        ));
      }
    }
    // else: 遗留非注册 box，走 Hive.box(name) 兜底
  }
}
```

**对比旧架构**：
- 旧：`_typedBoxNames` set + `_readTypedBox` if-else + `_formatValue` if-else + boxNames 数组 —— 加一个 typed box 要改 4-5 处
- 新：feature 调一次 `StorageRegistry.register` —— 零分支、零修改 StorageManager

### 2.4 面板行为（自动）

- **卡片列表**：每个注册 box 一个卡片，含 keyCount + size；`_getHiveInfo()` 遍历 registry
- **展开详情**：点击卡片 → 用 `d.formatValue` 显示每个 value 的字段
- **删除/清空**：走 `d.delete(key)` / `d.clear()`，自动泛型
- **0-key 卡片过滤**：`storage_analyze_demo.dart` 里 `info.keyCount == 0` → `SizedBox.shrink()`，避免遗留空 box 混淆

## 3. 添加一个新 feature 的 Hive 存储（4 步）

### Step 1：定义模型

```dart
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
}
```

### Step 2：手写 TypeAdapter

typeId 避开已有：0(BodyRecord)、90(Event)、91(Person)。选 92+。

```dart
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 92;
  // write/read 实现（同 §1.1 模式）...
}
```

### Step 3：集中初始化 + **注册到 Registry**

```dart
// note_hive.dart
class NoteHive {
  static const boxName = 'notes';
  static const _typeId = 92;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    try { await Hive.initFlutter(); } catch (_) {}

    if (!Hive.isAdapterRegistered(_typeId)) {
      Hive.registerAdapter(NoteAdapter());
    }
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Note>(boxName);
    }

    // ★ 注册即接管，无需改 StorageManager
    StorageRegistry.register(BoxDescriptor<Note>(
      name: boxName,
      displayName: '笔记',
      typeId: _typeId,
      openTyped: () => Hive.openBox<Note>(boxName),
      formatValue: (v) {
        final n = v as Note;
        return '标题: ${n.title}\n内容: ${n.content}\n时间: ${n.createdAt}';
      },
    ));

    _initialized = true;
  }

  static Box<Note> get notes => Hive.box<Note>(boxName);
}
```

### Step 4：Lab → 存储分析 验证

刷新页面，应看到：
- 新增卡片"笔记"（keyCount / size）
- 点击展开，每条 key 按 formatValue 输出
- 长按删除单条 / 卡片操作清空

**不需要修改：**
- ❌ `storage_manager.dart`
- ❌ `storage_analyze_demo.dart`
- ❌ 任何 boxNames 数组或 typed 分支

## 4. 常见踩坑（BoxDescriptor 注册制下依然会遇到）

| 坑                                              | 原因                                    | 解决                                                                 |
| ----------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------- |
| 面板卡片不显示                                  | feature init() 没被调用                 | 确保 `main.dart` 或首屏加载了 `FeatureHive.init()`               |
| 展开显示 "Instance of xxx"                      | 忘了传 `formatValue`                  | 注册时补 `formatValue: (v) { final m = v as YourModel; return ...; }` |
| 显示 0-key 空卡片                               | 打开了 box 但从未写入                   | 遗留问题，`storage_analyze` 会过滤；或删除该 box                   |
| `HiveError: You must provide your type`       | typed box 走了非 typed 路径             | 注册时必须 `typeId: N, openTyped: () => Hive.openBox<T>(name)`     |
| 覆盖注册（feature 被 hot reload 后 registry 重复注册） | `register` 幂等（Map 覆盖），无副作用 | 无需处理                                                             |

## 5. 相关文件（源码）

- `lib/core/storage/box_descriptor.dart` —— BoxDescriptor 定义
- `lib/core/storage/storage_registry.dart` —— 全局注册表
- `lib/core/storage/storage_manager.dart` —— 纯查询代理（不含分支）
- `lib/core/body/models/body_record_repo.dart` —— body_records 注册示例
- `lib/lab/demos/calendar/data/calendar_hive.dart` —— 日历 3 个 box 注册示例
- `lib/lab/demos/storage_analyze_demo.dart` —— 面板 UI
