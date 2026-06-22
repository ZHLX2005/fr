# GenUI 框架内部生成与处理机制

> 本文聚焦:**flutter_genui 在拿到 A2UI 消息之后,在 Flutter 内部到底生成、解析、维护了什么**。
> 全部基于 `D:\code\a_dart\prj\fr\.claude\repo\flutter_genui\packages\genui\` 源码。

---

## 1. 总体生成流程

AI 服务 → 文本 / SSE 事件流 → `Transport` 层解析为 `A2uiMessage` 序列 → `SurfaceController.handleMessage` → 修改 `SurfaceRegistry` / `DataModelStore` → `Surface` widget 监听 `ValueListenable<SurfaceDefinition?>` 自动重建 → 渲染真实 Flutter Widget。

> **关键点:框架生成的"UI"是 Flutter 真实 Widget 树,不是代码;LLM 输出的是 JSON 描述,由 Catalog 翻译为 Widget。**

源码依据 `README.md:61-67`:
```
61  ### Core difference
62
63  This UI is not generated in the form of code; rather, it's generated at runtime
64  based on a widget catalog from the developers' project.
```

---

## 2. SurfaceController — 整个引擎的总指挥

文件:`packages/genui/lib/src/engine/surface_controller.dart`(共 333 行)

### 2.1 类定义

源码依据 `surface_controller.dart:30-50`:
```
30  interface class SurfaceController implements SurfaceHost, A2uiMessageSink {
31    /// Creates a [SurfaceController].
...
38    SurfaceController({
39      required this.catalogs,
40      this.pendingUpdateTimeout = const Duration(minutes: 1),
41    });
...
44    /// The catalogs available to surfaces in this engine.
45    final Iterable<Catalog> catalogs;
...
49    late final surface_reg.SurfaceRegistry _registry =
50        surface_reg.SurfaceRegistry();
51    late final DataModelStore _store = DataModelStore();
```

同时实现两个接口:
- `SurfaceHost`(让 `Conversation` 监听 surface 更新)— `interfaces/surface_host.dart:15-24`
- `A2uiMessageSink`(让 transport 推入 A2uiMessage)— `interfaces/a2ui_message_sink.dart:8-11`

### 2.2 状态机:`_handleMessageInternal` 4 个 case

`surface_controller.dart:152-246` 是核心分发逻辑:

```dart
void _handleMessageInternal(A2uiMessage message) {
  switch (message) {
    case CreateSurface(:final surfaceId, ...):
      // 1) 清掉 pending buffer
      // 2) 拿/建 DataModel
      // 3) 根据 sendDataModel 决定 attach/detach
      // 4) _registry.updateSurface(isNew: ...)
      // 5) 校验 catalog.schema
      // 6) 刷新 pending buffer

    case UpdateComponents(:final surfaceId, :final components):
      // 1) 若 surface 未创建 → _bufferMessage 暂存
      // 2) 否则把 components 合并到 _components map
      // 3) 校验新 definition

    case UpdateDataModel(:final surfaceId, :final path, :final value):
      // 1) 若 surface 未创建 → buffer
      // 2) 否则 _store.getDataModel(surfaceId).update(path, value)
      //   (注意:不触发 surface rebuild,组件自己监听 dataModel)

    case DeleteSurface(:final surfaceId):
      // 清 pending + 删 registry + 删 dataModel
  }
}
```

源码关键片段 `surface_controller.dart:203-218`:
```
203        case UpdateComponents(:final surfaceId, :final components):
204          if (!_registry.hasSurface(surfaceId)) {
205            _bufferMessage(surfaceId, message);
206            return;
207          }
208
209          final SurfaceDefinition current = _registry.getSurface(surfaceId)!;
210          final Map<String, Component> newComponents = Map.of(current.components);
211          for (final component in components) {
212            newComponents[component.id] = component;
213          }
214
215          _registry.updateSurface(
216            surfaceId,
217            current.copyWith(components: newComponents),
218          );
```

`SurfaceController` **不** 主动 emit "update surface" 给 `DataModel` 的修改(避免全量重建)。源码依据 `surface_controller.dart:236-238`:
```
236          model.update(path, value);
237
238          // Note: We don't trigger a surface update here to avoid full UI refreshes
239          // on data changes. Components should listen to the DataModel directly.
```

### 2.3 事件流:`surfaceUpdates` + `onSubmit`

源码依据 `surface_controller.dart:58-72`:
```
58    // Expose registry events as surface updates
59    @override
60    Stream<SurfaceUpdate> get surfaceUpdates => _registry.events.map(
61      (e) => switch (e) {
62        surface_reg.SurfaceAdded(:final surfaceId, :final definition) =>
63          SurfaceAdded(surfaceId, definition),
64        surface_reg.SurfaceUpdated(:final surfaceId, :final definition) =>
65          ComponentsUpdated(surfaceId, definition),
66        surface_reg.SurfaceRemoved(:final surfaceId) =>
67          SurfaceRemoved(surfaceId),
68      },
69    );
70
71    /// A stream of messages to be submitted to the AI service.
72    Stream<ChatMessage> get onSubmit => _onSubmit.stream;
```

事件类型在 `packages/genui/lib/src/model/ui_models.dart:404-437`:
- `SurfaceAdded`
- `ComponentsUpdated`
- `SurfaceRemoved`

`onSubmit` 流是 **用户交互 → AI 的反向通道**,被 `Conversation` 监听后转发给 transport。

### 2.4 pending buffer(消息排序保证)

如果 `UpdateComponents` 比 `CreateSurface` 先到(流式场景),需要缓存。源码依据 `surface_controller.dart:248-256`:
```
248    void _bufferMessage(String surfaceId, A2uiMessage message) {
249      _pendingUpdates.putIfAbsent(surfaceId, () => []).add(message);
250      if (!_pendingUpdateTimers.containsKey(surfaceId)) {
251        _pendingUpdateTimers[surfaceId] = Timer(pendingUpdateTimeout, () {
252          _pendingUpdates.remove(surfaceId);
253          _pendingUpdateTimers.remove(surfaceId);
254        });
255      }
256    }
```

默认 `pendingUpdateTimeout = Duration(minutes: 1)`(`surface_controller.dart:40`),超时丢弃。

---

## 3. SurfaceRegistry — surface 生命周期 + 响应式核心

文件:`packages/genui/lib/src/engine/surface_registry.dart`(共 129 行)

### 3.1 内部结构

源码依据 `surface_registry.dart:38-50`:
```
38  /// Manages the lifecycle and storage of [SurfaceDefinition]s.
39  class SurfaceRegistry {
40    final Map<String, ValueNotifier<SurfaceDefinition?>> _surfaces = {};
41    // Track creation/update order for cleanup policies
42    final List<String> _surfaceOrder = [];
43    final StreamController<RegistryEvent> _eventController =
44        StreamController.broadcast();
45
46    /// The stream of registry events.
47    Stream<RegistryEvent> get events => _eventController.stream;
```

每个 surfaceId 对应一个 `ValueNotifier<SurfaceDefinition?>` — 这就是响应式的关键。`Surface` widget 监听它,任意 `updateSurface` 都会触发重建。

### 3.2 watchSurface — 懒创建

源码依据 `surface_registry.dart:54-69`:
```
54    /// Returns a [ValueListenable] that tracks the definition of the surface
55    /// with the given [surfaceId].
56    ///
57    /// If the surface does not exist, a new notifier is created with a null
58    /// value.
59    ValueListenable<SurfaceDefinition?> watchSurface(String surfaceId) {
60      if (!_surfaces.containsKey(surfaceId)) {
61        genUiLogger.fine('Adding new surface $surfaceId');
62      } else {
63        genUiLogger.fine('Fetching surface notifier for $surfaceId');
64      }
65      return _surfaces.putIfAbsent(
66        surfaceId,
67        () => ValueNotifier<SurfaceDefinition?>(null),
68      );
69    }
```

### 3.3 updateSurface — 触发事件

源码依据 `surface_registry.dart:75-96`:
```
75    void updateSurface(
76      String surfaceId,
77      SurfaceDefinition definition, {
78      bool isNew = false,
79    }) {
80      final ValueNotifier<SurfaceDefinition?> notifier = _surfaces.putIfAbsent(
81        surfaceId,
82        () => ValueNotifier(null),
83      );
84      notifier.value = definition;
85
86      _surfaceOrder.remove(surfaceId);
87      _surfaceOrder.add(surfaceId);
88
89      if (isNew) {
90        genUiLogger.info('Created new surface $surfaceId');
91        _eventController.add(SurfaceAdded(surfaceId, definition));
92      } else {
93        // genUiLogger.info('Updated surface $surfaceId'); // Optional logging
94        _eventController.add(SurfaceUpdated(surfaceId, definition));
95      }
96    }
```

`_surfaceOrder` 用于 LRU 清理策略(`surface_registry.dart:42-52` 注释)。

### 3.4 三个事件

`surface_registry.dart:13-36` 定义了三个内部 `RegistryEvent`:
- `SurfaceAdded`
- `SurfaceRemoved`
- `SurfaceUpdated`

被 `SurfaceController.surfaceUpdates` 翻译为对外的 `SurfaceAdded` / `ComponentsUpdated` / `SurfaceRemoved`(`surface_controller.dart:60-67`)。

---

## 4. DataModelStore — 每 surface 一份响应式数据模型

文件:`packages/genui/lib/src/engine/data_model_store.dart`(共 44 行)

### 4.1 极简

源码依据 `data_model_store.dart:8-44`:
```
8   class DataModelStore {
9     final Map<String, DataModel> _dataModels = {};
10    final Set<String> _attachedSurfaces = {};
11
12    /// Retrieves the data model for the given [surfaceId], creating it if it
13    /// does not exist.
14    DataModel getDataModel(String surfaceId) {
15      return _dataModels.putIfAbsent(surfaceId, InMemoryDataModel.new);
16    }
17
18    /// Removes the data model for the given [surfaceId] and detaches the surface.
19    void removeDataModel(String surfaceId) {
20      final DataModel? model = _dataModels.remove(surfaceId);
21      model?.dispose();
22      _attachedSurfaces.remove(surfaceId);
23    }
24
25    /// Marks the surface with the given [surfaceId] as attached.
26    void attachSurface(String surfaceId) {
27      _attachedSurfaces.add(surfaceId);
28    }
29
30    /// Marks the surface with the given [surfaceId] as detached.
31    void detachSurface(String surfaceId) {
32      _attachedSurfaces.remove(surfaceId);
33    }
```

每个 surface 一个 `DataModel`,默认实现是 `InMemoryDataModel`。

### 4.2 `InMemoryDataModel` 行为

文件:`packages/genui/lib/src/model/data_model.dart:265-529`

- `_data: JsonMap` — 树形 JSON 数据
- `_subscriptions: Map<DataPath, _RefCountedValueNotifier<Object?>>` — 路径 → 监听器
- `update(path, value)`:沿 segments 走 map/list,值变更后通知该路径 + 所有父路径 + 所有子路径(`_notifySubscribers` — `data_model.dart:498-528`)
- `subscribe<T>(absolutePath)`:返回 `ValueNotifier<T?>`,带引用计数
- `bindExternalState`:把外部 `ValueListenable` 绑定到路径(可双向)

引用计数的 notifier(`data_model.dart:531-563`)保证最后一个 listener dispose 时才真正销毁。

### 4.3 DataContext — 路径解析视图

源码依据 `data_model.dart:22-99`:
```
22  class DataContext implements cf.ExecutionContext {
...
24    DataContext(
25      this._dataModel,
26      this.path, {
27      Iterable<cf.ClientFunction>? functions,
28    }) : _functions = {
29           if (functions != null)
30             for (final f in functions) f.name: f,
31         };
...
51    /// Subscribes to a path, resolving it against the current context.
52    @override
53    ValueNotifier<T?> subscribe<T>(DataPath path) {
54      final DataPath absolutePath = resolvePath(path);
55      return _dataModel.subscribe<T>(absolutePath);
56    }
```

`DataPath` 支持绝对/相对路径;`List` 子项时可以用 `nested(relativePath)` 创建子 context(`data_model.dart:98-99`)。

### 4.4 DataPath 解析

文件:`packages/genui/lib/src/model/data_path.dart`(共 87 行)

- 路径以 `/` 分隔
- 支持绝对/相对
- 列表下标可作为 segment(`int.tryParse`)
- `startsWith` / `dirname` / `join` 等基本操作

---

## 5. A2uiParserTransformer — 流式 markdown/JSON 解析

文件:`packages/genui/lib/src/transport/a2ui_parser_transformer.dart`(共 275 行)

### 5.1 作用

把 `Stream<String>`(LLM 增量输出)转成 `Stream<GenerationEvent>`,其中:
- `A2uiMessageEvent` — 解析成功的 A2UI 消息
- `TextEvent` — 人类可读文字

支持三种 LLM 输出格式:
1. **Markdown JSON 代码块** ```` ```json ... ``` ````
2. **裸平衡 JSON**(`{ ... }`)
3. **JSONL**(连续多个 JSON,空白分隔)

### 5.2 主循环

源码依据 `a2ui_parser_transformer.dart:54-90`:
```
54    void _onData(String chunk) {
55      _buffer += chunk;
56      _processBuffer();
57    }
58
59    void _onDone() {
60      // If there's anything left in the buffer that looks like text, emit it.
61      if (_buffer.isNotEmpty) {
62        _emitText(_buffer);
63        _buffer = '';
64      }
65      _controller.close();
66    }
67
68    void _processBuffer() {
69      while (_buffer.isNotEmpty) {
70        // 1. Check for Markdown JSON block
71        final _Match? markdownMatch = _findMarkdownJson(_buffer);
72        if (markdownMatch != null) {
73          try {
74            final Object? decoded = jsonDecode(markdownMatch.content);
75            if (decoded != null) {
76              _emitBefore(markdownMatch.start);
77              _emitMessage(decoded);
78              _buffer = _buffer.substring(markdownMatch.end);
79              continue;
80            }
81          } on FormatException {
...
89        }
90
91        // 2. Check for Balanced JSON
92        final _Match? jsonMatch = _findBalancedJson(_buffer);
```

### 5.3 平衡 JSON 匹配器

源码依据 `a2ui_parser_transformer.dart:230-266`:
```
230    _Match? _findBalancedJson(String input) {
231      if (!input.startsWith('{')) return null;
232
233      var balance = 0;
234      var inString = false;
235      var isEscaped = false;
236
237      for (var i = 0; i < input.length; i++) {
238        final String char = input[i];
239
240        if (isEscaped) {
241          isEscaped = false;
242          continue;
243        }
244        if (char == '\\') {
245          isEscaped = true;
246          continue;
247        }
248        if (char == '"') {
249          inString = !inString;
250          continue;
251        }
252
253        if (!inString) {
254          if (char == '{') {
255            balance++;
256          } else if (char == '}') {
257            balance--;
258            if (balance == 0) {
259              final String text = input.substring(0, i + 1);
260              return _Match(0, i + 1, text, text);
261            }
262          }
263        }
264      }
265      return null;
266    }
```

正确处理引号 + 转义 + 嵌套。

### 5.4 JSONL 处理

源码依据 `a2ui_parser_transformer.dart:48-50, 135-145`:
```
48    // When true, whitespace-only content is treated as a JSONL separator and
49    // discarded. When false, it is emitted as a TextEvent.
50    bool _wasLastEventA2ui = false;
...
135          if (firstPotentialStart == -1) {
136            // No potential JSON start.
137            if (_buffer.isNotEmpty) {
138              if (_wasLastEventA2ui && _buffer.trim().isEmpty) {
139                // Whitespace-only after a JSON message: treat as JSONL separator.
140                // Hold in buffer until more data arrives or stream ends.
141                break;
142              }
```

发出 A2UI 消息后,纯空白不当作 TextEvent,而是 JSONL 分隔符;继续等更多数据。

### 5.5 输出类型 `GenerationEvent`

`A2uiTransportAdapter` export 了 `A2uiMessageEvent` / `TextEvent` / `GenerationEvent`(`a2ui_transport_adapter.dart:14-15`):

```dart
export '../model/generation_events.dart'
    show A2uiMessageEvent, GenerationEvent, TextEvent;
```

---

## 6. A2uiTransportAdapter — 推模式高层 API

文件:`packages/genui/lib/src/transport/a2ui_transport_adapter.dart`(共 97 行)

### 6.1 实现 Transport 接口

源码依据 `a2ui_transport_adapter.dart:27-40`:
```
27  class A2uiTransportAdapter implements Transport {
28    /// Creates a [A2uiTransportAdapter].
29    ///
30    /// The [onSend] callback is required if [sendRequest] will be called.
31    A2uiTransportAdapter({this.onSend}) {
32      _pipeline = _inputStream.stream
33          .transform(const A2uiParserTransformer())
34          .asBroadcastStream();
35    }
36
37    /// The callback to invoke when [sendRequest] is called.
38    final ManualSendCallback? onSend;
39
40    final StreamController<String> _inputStream = StreamController();
41    final StreamController<A2uiMessage> _messageStream =
42        StreamController.broadcast();
43    late final Stream<GenerationEvent> _pipeline;
```

### 6.2 推模式 API

源码依据 `a2ui_transport_adapter.dart:46-73`:
```
46    /// Feeds a chunk of text from the LLM to the controller.
47    ///
48    /// The controller buffers and parses this internally using the transformer.
49    void addChunk(String text) {
50      _pipelineSubscription ??= _pipeline.listen((event) {
51        if (event is A2uiMessageEvent) {
52          _messageStream.add(event.message);
53        }
54      });
55      _inputStream.add(text);
56    }
57
58    /// Feeds a raw A2UI message (e.g. from a tool output or separate channel).
59    void addMessage(A2uiMessage message) {
60      _messageStream.add(message);
61    }
62
63    /// A stream of sanitizer text for the chat UI.
64    @override
65    Stream<String> get incomingText => _pipeline
66        .where((e) => e is TextEvent)
67        .cast<TextEvent>()
68        .map((e) => e.text.trim())
69        .where((text) => text.isNotEmpty);
70
71    /// A stream of A2UI messages parsed from the input.
72    @override
73    Stream<A2uiMessage> get incomingMessages => _messageStream.stream;
```

应用层只需要 **不断 `addChunk(text)`**,适配器自动:
- 把 `TextEvent` 转发给 `incomingText`(给聊天 UI)
- 把 `A2uiMessageEvent` 转发给 `incomingMessages`(给 SurfaceController)

---

## 7. Catalog — 18 个内置 widget

文件:`packages/genui/lib/src/catalog/basic_catalog.dart`(共 200 行)

### 7.1 18 个 widget

源码依据 `basic_catalog.dart:122-148`:
```
122    static Catalog asCatalog({List<String> systemPromptFragments = const []}) {
123      return Catalog(
124        [
125          audioPlayer,
126          button,
127          card,
128          checkBox,
129          column,
130          dateTimeInput,
131          divider,
132          icon,
133          image,
134          list,
135          modal,
136          choicePicker,
137          row,
138          slider,
139          tabs,
140          text,
141          textField,
142          video,
143        ],
144        functions: BasicFunctions.all,
145        catalogId: basicCatalogId,
146        systemPromptFragments: [basicCatalogRules, ...systemPromptFragments],
147      );
148    }
```

| 类别 | widget |
|---|---|
| 布局 | `column`, `row`, `card`, `list`, `tabs`, `modal`, `divider` |
| 显示 | `text`, `icon`, `image`, `audioPlayer`, `video` |
| 输入 | `button`, `checkBox`, `textField`, `dateTimeInput`, `slider`, `choicePicker` |

`asNoAssetCatalog()` 可去掉 `audioPlayer` / `image` / `video`(`basic_catalog.dart:111-115`)。

### 7.2 单个 widget 的样子(Text)

源码依据 `packages/genui/lib/src/catalog/basic_catalog_widgets/text.dart:33-100`:
```
33  final text = CatalogItem(
34    name: 'Text',
35    dataSchema: S.object(
36      description: 'A block of styled text.',
37      properties: {
38        'text': A2uiSchemas.stringReference(
39          description: '...',
40        ),
41        'variant': S.string(
42          description: 'A hint for the base text style.',
43          enumValues: ['h1', 'h2', 'h3', 'h4', 'h5', 'caption', 'body'],
44        ),
45      },
46      required: ['text'],
47    ),
...
61    widgetBuilder: (itemContext) {
62      final textData = _TextData.fromMap(itemContext.data as JsonMap);
63
64      return BoundString(
65        dataContext: itemContext.dataContext,
66        value: textData.text,
67        builder: (context, value) { ... }
```

每个 `CatalogItem` 有三要素:
1. `name` — LLM 用来选择的标识
2. `dataSchema` — JSON Schema,描述其 properties,会随 catalog 喂给 LLM
3. `widgetBuilder(itemContext)` — 收到 `itemContext.data` 后真正返回 Flutter widget

### 7.3 Button — 用户事件回传示例

源码依据 `packages/genui/lib/src/catalog/basic_catalog_widgets/button.dart:198-243`:
```
198  Future<void> _handlePress(
199    CatalogItemContext itemContext,
200    _ButtonData buttonData,
201  ) async {
202    final JsonMap actionData = buttonData.action;
203    if (actionData.containsKey('event')) {
204      final eventMap = actionData['event'] as JsonMap;
205      final actionName = eventMap['name'] as String;
206      final contextDefinition = eventMap['context'] as JsonMap?;
207
208      final JsonMap resolvedContext = await resolveContext(
209        itemContext.dataContext,
210        contextDefinition,
211      );
212      itemContext.dispatchEvent(
213        UserActionEvent(
214          name: actionName,
215          sourceComponentId: itemContext.id,
216          context: resolvedContext,
217        ),
218      );
219      } else if (actionData.containsKey('functionCall')) {
220        final funcMap = actionData['functionCall'] as JsonMap;
221        final callName = funcMap['call'] as String;
222        ...
225          Navigator.of(itemContext.buildContext).pop();
226        ...
```

**两种交互方式**:
1. `action.event` — 抛回给 AI 的语义事件,带 `name` + `context`
2. `action.functionCall` — 调用 catalog 里注册的 `ClientFunction`,或在 widget 端直接做副作用(如 `closeModal`)

---

## 8. DataBinding 怎么工作

### 8.1 绑定类型

`packages/genui/lib/src/widgets/widget_utilities.dart:47-72` 提供了 `BoundValue<T>` 抽象类。

例如 `BoundString`:
- 接收 `value: Object?`(可能是字面量 / `{path: "..."}` / `{call: "..."}`)
- 自动 subscribe `DataContext` 对应路径
- value 变化时调 `builder` 重建

### 8.2 动态值解析

源码依据 `data_model.dart:115-127`:
```
115    Stream<Object?> _evaluateStream(Object? value) {
116      if (value is Map) {
117        if (value.containsKey('path')) {
118          return subscribeStream(DataPath(value['path'] as String));
119        }
120        if (value.containsKey('call')) {
121          return _evaluateFunctionCall(value as JsonMap);
122        }
123      }
124      if (value is Stream) return value.cast<Object?>();
125      return Stream.value(value);
126    }
```

**3 种值形态**:
- `String` / `num` / `bool` — 字面量,直接用
- `{path: "..."}` — 订阅 data model,变化时自动 rebuild
- `{call: "funcName", args: {...}}` — 调用 `ClientFunction`

### 8.3 端到端数据流

```
LLM 输出 updateDataModel {path: "/counter", value: 5}
        ↓
A2uiParserTransformer → A2uiMessageEvent(UpdateDataModel)
        ↓
SurfaceController.handleMessage
        ↓
model.update(DataPath("/counter"), 5)
        ↓
InMemoryDataModel._notifySubscribers
  ↓ 写回 _subscriptions["/counter"] 及其所有父路径
  ↓ forceNotify 父路径(因容器原地改)
        ↓
BoundString / BoundValue.builder 被调用
        ↓
Text widget 重新渲染
```

---

## 9. Surface widget — 真正的渲染入口

文件:`packages/genui/lib/src/widgets/surface.dart`(共 226 行)

### 9.1 监听 definition 重建

源码依据 `surface.dart:47-94`:
```
47  class _SurfaceState extends State<Surface> {
48    @override
49    Widget build(BuildContext context) {
...
53        return ValueListenableBuilder<SurfaceDefinition?>(
54          valueListenable: widget.surfaceContext.definition,
55          builder: (context, definition, child) {
56            genUiLogger.fine('Building surface ${widget.surfaceContext.surfaceId}');
57            if (definition == null) {
...
64            // Implicit root is "root".
65            const rootId = 'root';
66            if (definition.components.isEmpty ||
67                !definition.components.containsKey(rootId)) {
...
74            final Catalog? catalog = _findCatalogForDefinition(definition);
75            if (catalog == null) { ... return FallbackWidget(error: error); }
76
77            return _buildWidget(
78              definition,
79              catalog,
80              rootId,
81              DataContext(
82                widget.surfaceContext.dataModel,
83                DataPath.root,
84                functions: catalog.functions,
85              ),
86            );
87          },
88        );
89      }
```

要点:
- **必须有 `id: "root"` 组件**,否则空显示(`surface.dart:65-72`)
- 用 `surfaceContext.definition` (即 `SurfaceRegistry.watchSurface` 返回的 `ValueListenable`)订阅重建
- 根 `DataContext` 从 `DataPath.root` 开始,带上 `catalog.functions`

### 9.2 递归构建

源码依据 `surface.dart:101-150`:
```
101    Widget _buildWidget(
102      SurfaceDefinition definition,
103      Catalog catalog,
104      String widgetId,
105      DataContext dataContext,
106    ) {
107      try {
108        Component? data = definition.components[widgetId];
...
116        final JsonMap widgetData = data.properties;
117        genUiLogger.finest('Building widget $widgetId');
118        return catalog.buildWidget(
119          CatalogItemContext(
120            id: widgetId,
121            data: widgetData,
122            type: data.type,
123            buildChild: (String childId, [DataContext? childDataContext]) =>
124                _buildWidget(definition, catalog, childId, ...),
125            dispatchEvent: _dispatchEvent,
126            buildContext: context,
127            dataContext: dataContext,
...
```

`buildChild` 实现 widget 树递归。

### 9.3 事件回传

源码依据 `surface.dart:152-171`:
```
152    void _dispatchEvent(UiEvent event) {
153      if (widget.actionDelegate.handleEvent(
154        context,
155        event,
156        widget.surfaceContext,
157        _buildWidget,
158      )) {
159        return;
160      }
161
162      // The event comes in without a surfaceId, which we add here.
163      final Map<String, Object?> eventMap = {
164        ...event.toMap(),
165        surfaceIdKey: widget.surfaceContext.surfaceId,
166      };
167      final UiEvent newEvent = event is UserActionEvent
168          ? UserActionEvent.fromMap(eventMap)
169          : UiEvent.fromMap(eventMap);
170      widget.surfaceContext.handleUiEvent(newEvent);
171    }
```

**用户事件回传链路**(`_dispatchEvent`):
1. `actionDelegate` 优先拦截(可弹 modal、跳转等)
2. 给事件补上 `surfaceId`
3. 调 `surfaceContext.handleUiEvent(event)`
4. → `SurfaceController._ControllerContext.handleUiEvent`(`surface_controller.dart:325-327`)
5. → `SurfaceController.handleUiEvent`(`surface_controller.dart:262-274`)
6. 包成 `ChatMessage` + `UiInteractionPart` 加入 `onSubmit` 流
7. `Conversation` 监听 `onSubmit` → `transport.sendRequest`(`conversation.dart:156`)

---

## 10. 整体事件回环

```
                    ┌─────────────────────────────────┐
                    │           AI / Agent            │
                    │ (LLM 或 A2A Server)             │
                    └─────────────────────────────────┘
                          ▲                  │
                  JSON   │                  │  A2UI 流
                  events │                  │  (text/SSE)
                          │                  ▼
       ┌──────────────────────────────────────────────────┐
       │ Transport                                         │
       │  ├─ A2uiTransportAdapter.addChunk(text)           │
       │  └─ A2uiAgentConnector (via genui_a2a)            │
       └──────────────────────────────────────────────────┘
                          │  Stream<A2uiMessage>
                          ▼
       ┌──────────────────────────────────────────────────┐
       │ SurfaceController.handleMessage                   │
       │  ├─ CreateSurface  → SurfaceRegistry.updateSurface│
       │  ├─ UpdateComponents → 同上                       │
       │  ├─ UpdateDataModel → DataModel.update            │
       │  └─ DeleteSurface  → registry.removeSurface       │
       └──────────────────────────────────────────────────┘
                          │  Stream<SurfaceUpdate>
                          ▼
       ┌──────────────────────────────────────────────────┐
       │ Conversation  (event facade)                      │
       │  └─ state List<String> surfaces / latestText      │
       └──────────────────────────────────────────────────┘
                          │
                          ▼
       ┌──────────────────────────────────────────────────┐
       │ Surface widget 监听 ValueListenable<Definition?>  │
       │  └─ Catalog.buildWidget(type, data, itemContext)  │
       │     ├─ BoundValue 订阅 DataContext path           │
       │     └─ onTap → dispatchEvent → UserActionEvent    │
       └──────────────────────────────────────────────────┘
                          │
                          ▼  onSubmit ChatMessage
                   回到 Transport.sendRequest → AI
```

---

## 11. 总结

flutter_genui 在内部生成的内容:

1. **运行时 Flutter Widget 树** — 不是代码,由 `Catalog.buildWidget` 在 `Surface._buildWidget` 递归中即时构建
2. **多 surface 状态** — `SurfaceRegistry` 持有 `Map<surfaceId, ValueNotifier<SurfaceDefinition?>>`,带广播事件流
3. **每 surface 的响应式数据模型** — `InMemoryDataModel` + `DataPath` + `DataContext` + 引用计数 `ValueNotifier`
4. **A2UI 消息分类** — 4 种 sealed class + JSON Schema 校验
5. **用户事件反向通道** — `UserActionEvent` → `UiInteractionPart` → `onSubmit` ChatMessage

整个框架本质是:**"JSON 描述 + 目录翻译 + ValueNotifier 响应式"** 的三层组合,把 LLM 输出的 UI 意图变成 Flutter 真实可交互的 widget 树。
