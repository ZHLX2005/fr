# Hive 存储 + 集中可视面板设计

> **主题**：在 Flutter 项目中使用 Hive 做结构化存储，并通过 StorageManager 集中观察所有 Hive Box 的内容。
> **适用场景**：需要多个自包含的 typed box、并希望在 Lab → 存储分析 页面统一观察数据时。

## 架构总览

```
项目
├── Hive Boxes（每个 feature 一个或几个）
│   ├── timetable_config     (非 typed, key-value)
│   ├── timetable_items      (非 typed, key-value)
│   ├── body_records         (typed, BodyRecord)
│   ├── calendarEvents       (typed, Event)         ← 日历 demo
│   ├── calendarPeople       (typed, Person)        ← 日历 demo
│   └── calendarViewState    (非 typed, key-value)  ← 日历 demo
└── StorageManager（集中观察面板）
    ├── getAllStorageInfo()   → 每个 box 一个 StorageInfo（含 size/keyCount）
    ├── getKeyDetails(name)   → 展开某 box 的键值详情
    ├── _formatValue()        → typed 对象格式化显示
    └── _readTypedBox()       → typed box 泛型访问
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

### 1.2 集中初始化

所有 box 统一在一个地方注册和打开，避免重复、漏注册：

```dart
// calendar_hive.dart
class CalendarHive {
  static const eventsBoxName = 'calendarEvents';
  static const peopleBoxName = 'calendarPeople';
  static const viewStateBoxName = 'calendarViewState';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    // Hive Flutter 兜底（如果还没初始化）
    try { await Hive.initFlutter(); } catch (_) {}

    // 注册 adapter（幂等）
    if (!Hive.isAdapterRegistered(90)) {
      Hive.registerAdapter(EventAdapter());
    }
    if (!Hive.isAdapterRegistered(91)) {
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
    _initialized = true;
  }

  // 泛型 getter
  static Box<Event> get events => Hive.box<Event>(eventsBoxName);
  static Box<Person> get people => Hive.box<Person>(peopleBoxName);
  static Box get viewState => Hive.box(viewStateBoxName);
}
```

### 1.3 Provider 读写（不手动全量 save）

Hive Box 每次 `put/delete` 自动持久化，不需要全量序列化。Provider 的 add/update/remove 直接调 Box 方法：

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

## 2. StorageManager 集中面板

`storage_analyze_demo.dart` 是项目内已有的统一存储观察工具，在 Lab → 存储分析。

### 2.1 注册新 Box

在 `StorageManager` 中加 box 名：

```dart
// storage_manager.dart
final boxNames = [
  'existingBoxes...',
  'calendarEvents',    // 新增
  'calendarPeople',    // 新增
  'calendarViewState', // 新增
];
```

### 2.2 typed Box 支持

`boxName != null` 且是 typed 时，必须用泛型 `Hive.box<T>()` 访问。`StorageManager` 的 `_typedBoxNames` 集合和 `_readTypedBox` 方法处理：

```dart
static const _typedBoxNames = {
  'body_records',
  'calendarEvents',
  'calendarPeople',
};

List<KeyDetail> _readTypedBox(String name) {
  // 每个 typed box 一个分支：
  if (name == 'calendarEvents') {
    final box = Hive.box<Event>(name);  // 必须泛型
    for (final key in box.keys) {
      final value = box.get(key);
      // ...
    }
  }
}
```

### 2.3 格式化显示

`_formatValue()` 对 typed value 按字段展示：

```dart
if (runtime == 'Event') {
  final dyn = value as dynamic;
  return '标题: ${dyn.title}\n日期: ${dyn.month}月${dyn.day}日\n...';
}
```

如果显示 "Instance of xxx" → `_formatValue()` 没处理新 type → 加分支。

### 2.4 每个 box 独立卡片

`getAllStorageInfo()` 返回每个 box 一个 `StorageInfo`（含 keyCount、size）。`_getHiveInfo()` 遍历所有 box 名，**用泛型打开**，分别统计：

```dart
// ✅ 每个 box 独立
result.addAll(await _getHiveInfo());

// _getHiveInfo 内部：
for (final name in boxNames) {
  Box box;
  if (name == 'calendarEvents') {
    box = Hive.box<Event>(name);
  } else {
    box = Hive.box(name);
  }
  result.add(StorageInfo(name: name, keyCount: box.length, ...));
}
```

## 3. 添加流程（新增一个新 feature 的 Hive 存储）

### Step 1：定义模型

```dart
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  // copyWith / toJson / fromJson 可选
}
```

### Step 2：手写 TypeAdapter

typeId 避开已有：0(BodyRecord)、90(Event)、91(Person)。选 92+。

```dart
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 92;
  // write/read 实现...
}
```

### Step 3：集中初始化

在对应 Feature 的 `FeatureHive.init()` 里注册 + 打开：

```dart
if (!Hive.isAdapterRegistered(92)) {
  Hive.registerAdapter(NoteAdapter());
}
if (!Hive.isBoxOpen('notes')) {
  await Hive.openBox<Note>('notes');
}
```

### Step 4：写入

```dart
final box = Hive.box<Note>('notes');
await box.put(note.id, note);  // 或 box.add(note) 自动生成 int key
```

### Step 5：注册到 StorageManager

`storage_manager.dart` 三处加 box 名：

1. `boxNames` 列表（`getKeyDetails` 循环）
2. `_typedBoxNames` 集合（如果 typed）
3. `_readTypedBox` 分支（如果 typed）
4. `_getHiveInfo` boxNames 列表
5. `_formatValue` 格式化判断分支

### Step 6：验证

在 Lab → 存储分析 → 刷新，确认：
- 卡片显示正确 keyCount
- 展开能看到每个字段
- 清空/删除正常（`Hive.box.delete` / `box.clear()`）
