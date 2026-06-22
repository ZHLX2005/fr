# A2UI 消息协议与传输

> 范围:A2UI v0.9.1 envelope + 数据模型 + action 系统 + 传输契约 + catalog 替换机制。证据来源:JSON Schema、`specification/v0_9_1/docs/a2ui_protocol.md`、Python SDK 内部实现。

---

## 1. 四种 Envelope 消息

A2UI v0.9.1 在 `specification/v0_9_1/json/server_to_client.json` 顶层定义为 `oneOf` 4 种类型:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "A2UI Message Schema",
  "type": "object",
  "oneOf": [
    {"$ref": "#/$defs/CreateSurfaceMessage"},
    {"$ref": "#/$defs/UpdateComponentsMessage"},
    {"$ref": "#/$defs/UpdateDataModelMessage"},
    {"$ref": "#/$defs/DeleteSurfaceMessage"}
  ],
  ...
}
```

`specification/v0_9_1/docs/a2ui_protocol.md:175-178` 对应文字定义:

> Every message streamed by the server must be a JSON object containing exactly one of the following keys: `createSurface`, `updateComponents`, `updateDataModel`, or `deleteSurface`.

每条消息都必须带 `version` 字段,enum 为 `["v0.9", "v0.9.1"]`(server_to_client.json:17-19),向下兼容。

Python 侧 dispatch 见 `agent_sdks/python/a2ui_core/src/a2ui/core/processing/message_processor.py:92-117`:

```python
def _process_message(self, message: Dict[str, Any]) -> None:
    update_types = [
        k for k in (MSG_TYPE_CREATE_SURFACE, MSG_TYPE_UPDATE_COMPONENTS,
                    MSG_TYPE_UPDATE_DATA_MODEL, MSG_TYPE_DELETE_SURFACE)
        if k in message
    ]
    if len(update_types) > 1:
        raise ValueError(...)
    if MSG_TYPE_CREATE_SURFACE in message:
        self._process_create_surface(message[MSG_TYPE_CREATE_SURFACE])
    elif MSG_TYPE_DELETE_SURFACE in message:
        ...
    elif MSG_TYPE_UPDATE_COMPONENTS in message:
        ...
    elif MSG_TYPE_UPDATE_DATA_MODEL in message:
        ...
```

下面逐条剖析。

### 1.1 `createSurface`

`server_to_client.json:14-46` 与 `specification/v0_9_1/docs/a2ui_protocol.md:178-202`:

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `surfaceId` | ✅ | string | UI 区域的唯一标识 |
| `catalogId` | ✅ | string | catalog 的命名空间 URI(推荐用自有域名前缀,如 `https://mycompany.com/1.0/somecatalog`) |
| `theme` | ❌ | object | 主题参数,必须对应当前 catalog 的 theme schema |
| `sendDataModel` | ❌ | boolean | 若为 true,客户端在每次 C2S 消息的 metadata 携带完整 data model;默认 false |
| `version` | ✅ | enum `["v0.9","v0.9.1"]` | 协议版本 |

强制约束(`a2ui_protocol.md:179`):

> While typically achieved by the agent sending a `createSurface` message, an agent may skip this if it knows the surface has already been created (e.g., by another agent). Once a surface is created, its `surfaceId` and `catalogId` are fixed... It is an error to send `createSurface` for a `surfaceId` that already exists without first deleting it.

MessageProcessor 中(`message_processor.py:118-152`):

```python
def _process_create_surface(self, payload):
    surface_id = payload.get("surfaceId")
    catalog_id = payload.get("catalogId")
    ...
    catalog = next((c for c in self.catalogs if c.catalog_id == catalog_id), None)
    if not catalog:
        raise ValueError(f"Catalog not found: {catalog_id}")
    if self.model.get_surface(surface_id):
        raise ValueError(f"Surface {surface_id} already exists.")
    ...
```

### 1.2 `updateComponents`

`server_to_client.json:48-78` 与 `a2ui_protocol.md:204-239`:

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `surfaceId` | ✅ | string | 目标 surface |
| `components` | ✅ | array(minItems 1) | 组件对象的扁平列表,item 必须对应当前 catalog 的 `anyComponent` |
| `version` | ✅ | enum | 协议版本 |

每条组件定义(`a2ui_protocol.md:298-306`):

- `id`(`ComponentId`,必填):唯一 ID
- `component`(string,必填):组件类型名(如 `"Text"`、`"Button"`)
- **其余属性平铺在组件对象内**(flat style);v0.8 是嵌套 style(`component: { Text: { ... } }`),v0.9 已统一为 flat

`message_processor.py:158-215` 在 strict 模式下先用 `A2uiValidator.validate_components` 校验,然后遍历 list:

```python
for comp in components:
    comp_id = comp.get("id")
    comp_type = comp.get("component")
    properties = {k: v for k, v in comp.items() if k not in ("id", "component")}
    existing = surface.components_model.get(comp_id)
    if existing:
        if comp_type and comp_type != existing.type:
            # 类型变更 → 重建
            surface.components_model.remove_component(comp_id)
            surface.components_model.add_component(ComponentModel(comp_id, comp_type, properties))
        else:
            existing.properties = properties
    else:
        ...
```

注意:消息可以引用尚未到达的子组件 ID,客户端需要**渐进渲染**(`a2ui_protocol.md:206`):

> Note that components may reference children or data bindings that do not yet exist; clients should handle this gracefully by rendering placeholders (progressive rendering).

### 1.3 `updateDataModel`

`server_to_client.json:79-108` 与 `a2ui_protocol.md:241-262`:

| 字段 | 必填 | 类型 | 说明 |
|------|------|------|------|
| `surfaceId` | ✅ | string | 目标 surface |
| `path` | ❌ | string(JSON Pointer) | 数据模型内的位置,缺省或 `/` 表示整张表 |
| `value` | ❌ | any | 新值;若省略则把 `path` 处的键移除(数组则该 index 设为 undefined,保留长度) |
| `version` | ✅ | enum | 协议版本 |

更新语义是 upsert(`a2ui_protocol.md:524-528`):

> - If the path exists, the value is updated.
> - If the path does not exist, the value is created.
> - If the value is omitted (or set to `undefined`), the key is removed. For arrays, the value at the index is set to `undefined`, preserving length.

底层 DataModel 是 RFC 6901 风格的 reactive JSON store,见 `agent_sdks/python/a2ui_core/src/a2ui/core/state/data_model.py:91-133`:

```python
def set(self, path: str, value: Any) -> None:
    """Sets a value atomically at a JSON Pointer path with auto-vivification."""
    tokens = self._parse_pointer(path)
    if not tokens:
        self._data = copy.deepcopy(value)
        self._trigger_listeners("/", value)
        return

    # Auto-vivification: traverse and construct intermediate dicts/lists
    current = self._data
    for i, token in enumerate(tokens[:-1]):
        ...
    # Set final leaf value
    last_token = tokens[-1]
    ...
    self._trigger_cascade(tokens)
```

`_trigger_cascade` 同时向上(bubble-up)通知父节点、向下(cascade-down)通知所有后代监听者(`data_model.py:159-171`)。

### 1.4 `deleteSurface`

`server_to_client.json:109-130` 与 `a2ui_protocol.md:265-281`:

| 字段 | 必填 | 类型 |
|------|------|------|
| `surfaceId` | ✅ | string |
| `version` | ✅ | enum |

仅一个字段。`message_processor.py:153-156`:

```python
def _process_delete_surface(self, payload):
    surface_id = payload.get("surfaceId")
    if surface_id:
        self.model.delete_surface(surface_id)
```

SurfaceModel 释放资源时同时 dispose data_model 与 components_model(`surface_model.py:76-97`)。

---

## 2. Common Types:`Dynamic*` / `ChildList` / `ComponentId` / `FunctionCall`

`specification/v0_9_1/json/common_types.json` 定义协议级可复用类型。`a2ui_protocol.md:130-138` 总览:

> - `DynamicString` / `DynamicNumber` / `DynamicBoolean` / `DynamicStringList`: 数据绑定的核心,接受字面值、`path`(JSON Pointer)或 `FunctionCall`。
> - `ChildList`: 容器引用子组件,支持 `array`(静态)与 `object`(数据驱动模板)。
> - `ComponentId`: 同 surface 内对组件 ID 的引用。

### 2.1 `Dynamic*` 系列

`common_types.json:97-198`:

```json
"DynamicString": {
  "oneOf": [
    {"type": "string"},
    {"$ref": "#/$defs/DataBinding"},
    {"allOf": [
      {"$ref": "#/$defs/FunctionCall"},
      {"properties": {"returnType": {"const": "string"}}}
    ]}
  ]
}
```

`DynamicNumber` / `DynamicBoolean` / `DynamicStringList` 同样结构,只是 `returnType` 的 const 与 array item 类型不同。Python 侧对应 Pydantic 模型在 `agent_sdks/python/a2ui_core/src/a2ui/core/schema/common_types.py`(代码生成)。

### 2.2 `ChildList`

`common_types.json:37-62`:

```json
"ChildList": {
  "oneOf": [
    { "type": "array", "items": {"$ref": "#/$defs/ComponentId"} },
    {
      "type": "object",
      "properties": {
        "componentId": {"$ref": "#/$defs/ComponentId"},
        "path": {"type": "string", "description": "The path to the list of component property objects in the data model."}
      },
      "required": ["componentId", "path"]
    }
  ]
}
```

- **array 形态**:静态子节点列表,例如 `["title", "button"]`。
- **object 形态(模板)**:声明一个 `componentId` 模板组件,然后对 data model 中 `path` 指向的数组**逐项实例化**,进入 Child Scope。这与 `a2ui_protocol.md:407-415` 的相对路径机制一起实现 list 渲染:

```text
employees: [
  { name: "Alice", role: "Engineer" },
  { name: "Bob",   role: "Designer" }
]

component "Text" { text: { path: "name" } }   // 相对路径
component "Text" { text: { path: "/company" } } // 绝对路径,始终从 root scope 取
```

### 2.3 `ComponentId`

`common_types.json:7-10`:

```json
"ComponentId": {
  "type": "string",
  "description": "The unique identifier for a component, used for both definitions and references within the same surface."
}
```

注意 validator 用此类型识别**结构性链接**而非静态文本(`a2ui_protocol.md:162-171`):

> Single child references: Any property that holds the ID of another component MUST use the `ComponentId` type defined in `common_types.json`.
> Use: `"$ref": "common_types.json#/$defs/ComponentId"`; Do NOT use: `"type": "string"`.

如果某字段写成 `string` 而不是 `ComponentId`,validator 会把它视为静态文本(URL/label)而**不会**检查目标组件是否存在。

### 2.4 `FunctionCall`

`common_types.json:200-232`:

```json
"FunctionCall": {
  "type": "object",
  "properties": {
    "call": {"type": "string"},
    "args": {
      "type": "object",
      "additionalProperties": {
        "anyOf": [
          {"$ref": "#/$defs/DynamicValue"},
          {"type": "object", "description": "A literal object argument"}
        ]
      }
    },
    "returnType": {"enum": ["string", "number", "boolean", "array", "object", "any", "void"], "default": "boolean"}
  },
  "required": ["call"],
  "oneOf": [{"$ref": "catalog.json#/$defs/anyFunction"}]
}
```

`returnType` 默认 `boolean`;`oneOf: anyFunction` 强制"函数名必须在 catalog 中存在"。`a2ui_protocol.md:593-595`:

> The client supports a set of named Functions (e.g., `required`, `regex`, `email`, `add`, `concat`) which are defined in the JSON schema (e.g. `catalogs/basic/catalog.json`) alongside the component definitions. The server references these functions by name in `FunctionCall` objects. This avoids sending executable code.

### 2.5 `Action`

`common_types.json:261-302`:

```json
"Action": {
  "oneOf": [
    {
      "type": "object",
      "properties": {
        "event": {
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "context": {
              "type": "object",
              "additionalProperties": {"$ref": "#/$defs/DynamicValue"}
            }
          },
          "required": ["name"]
        }
      },
      "required": ["event"]
    },
    {
      "type": "object",
      "properties": {"functionCall": {"$ref": "#/$defs/FunctionCall"}},
      "required": ["functionCall"]
    }
  ]
}
```

一个交互组件(如 `Button`)的 `action` 要么是 **server event**(触发 C2S `action` 消息),要么是 **client-side functionCall**(本地执行 catalog 中声明的函数,如 `openUrl`)。`a2ui_protocol.md:347-385` 提供两种形态的 JSON 示例。

---

## 3. 数据模型与 JSON Pointer 绑定

`a2ui_protocol.md:387-468` 用整个 section 描述**结构与状态分离**:

> A2UI relies on a strictly defined relationship between the UI structure (Components) and the state (Data Model), defining the mechanics of path resolution, variable scope during iteration.

### 3.1 路径规则

- **绝对路径**(以 `/` 开头):从根 scope 取值,与组件在树中的位置无关。
- **相对路径**(不带 `/`):仅在 ChildList 模板实例化后的 Child Scope 内有效,按 `componentId` 模板对数组中每个 item 创建一份 scope(`a2ui_protocol.md:406-414`):

```text
Text { text: { path: "name" } }       // 相对 → /employees/0/name
Text { text: { path: "/company" } }   // 绝对 → /company
```

### 3.2 类型转换规则

`a2ui_protocol.md:462-468`:

> - Numbers/Booleans: Standard string representation.
> - null/undefined: An empty string "".
> - Objects/Arrays: Stringified as JSON to ensure consistency across different client implementations.

### 3.3 双绑与本地-服务端同步

输入组件(`TextField`、`CheckBox`、`Slider`、`ChoicePicker`、`DateTimeInput`)**写**到本地 data model 是即时的,但**不**触发网络请求(`a2ui_protocol.md:485-492`):

> User inputs (keystrokes, toggles) do not automatically trigger network requests to the server. The updated state is sent to the server only when a specific User Action is triggered (e.g., a Button click).

提交按钮需要在 `action.event.context` 里**显式引用**路径,以便服务端拿到当前值(`a2ui_protocol.md:496-510`):

```json
"action": {
  "event": {
    "name": "submit_form",
    "context": { "email": { "path": "/formData/email" } }
  }
}
```

### 3.4 客户端实现层

Python DataModel 是 RFC 6901 风格的 reactive JSON Pointer store(`data_model.py:24-176`)。核心能力:

- `_parse_pointer` 支持 `~0` / `~1` 转义;同时支持**相对路径**(不以 `/` 开头)作为 Child Scope 下的解析入口(`data_model.py:31-41`)。
- `set()` 自动插入中间 dict/list(`auto-vivification`,`data_model.py:99-118`)。
- `subscribe(path, on_change)` 注册监听,初始值通过 `Subscription(initial_value=...)` 立即返回(`data_model.py:138-149`)。
- `_trigger_cascade` 实现"父路径冒泡 + 子路径级联"通知(`data_model.py:159-171`),保证同一节点被多个组件绑定时全部响应。

---

## 4. Action 系统(event / functionCall)

Action 是 A2UI 唯一的**用户交互→协议消息**入口。两种形态已见上文 §2.5。

### 4.1 Server action → `action` 消息

来源:`specification/v0_9_1/json/client_to_server.json:8-39` 与 `a2ui_protocol.md:815-825`。

```json
{
  "version": "v0.9.1",
  "action": {
    "name": "submit_form",
    "surfaceId": "contact_form_1",
    "sourceComponentId": "submit_button",
    "timestamp": "2026-01-15T12:00:00Z",
    "context": { "email": "user@example.com" }
  }
}
```

- `name`:从组件 `action.event.name` 取
- `surfaceId`:发起事件的 surface
- `sourceComponentId`:触发事件的组件 ID
- `timestamp`:ISO 8601
- `context`:所有 data binding 已解析后的扁平字典

Python SurfaceModel.dispatch_action(`surface_model.py:46-68`):

```python
def dispatch_action(self, payload, source_component_id):
    event_payload = payload
    if isinstance(payload, dict):
        if "event" in payload:
            event_payload = payload["event"]
        elif "functionCall" in payload:
            event_payload = payload["functionCall"]

    action_event = {
        "name": event_payload.get("name", event_payload.get("call", "")),
        "surfaceId": self.id,
        "sourceComponentId": source_component_id,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "context": event_payload.get("context", event_payload.get("args", {})),
    }
    self.on_action.emit(action_event)
```

### 4.2 Client-side functionCall

调用 catalog 中声明的客户端函数。Basic catalog 提供 14 个(`specification/v0_9_1/catalogs/basic/catalog.json:805-1245`),关键的有:

| 函数 | 返回类型 | 用途 |
|------|----------|------|
| `required` | boolean | 非空校验 |
| `regex` | boolean | 正则校验 |
| `length` | boolean | 长度校验 |
| `numeric` | boolean | 数值范围校验 |
| `email` | boolean | 邮箱校验 |
| `formatString` | string | `${expr}` 字符串插值 |
| `formatNumber` | string | 数字格式化 |
| `formatCurrency` | string | 货币格式化 |
| `formatDate` | string | 按 TR35 模式格式化日期 |
| `pluralize` | string | CLDR 复数形式 |
| `openUrl` | void | 在浏览器中打开 URL |
| `and` / `or` / `not` | boolean | 逻辑运算 |

Python 实现统一通过 `FunctionImplementation.execute()`(`agent_sdks/python/a2ui_core/src/a2ui/core/catalog/functions.py:32-66`)走"先 schema 校验、再执行函数体"的路径。

### 4.3 `error` 消息

`client_to_server.json:40-87` 定义两类错误:

```json
{
  "version": "v0.9.1",
  "error": {
    "code": "VALIDATION_FAILED",
    "surfaceId": "user_profile_card",
    "path": "/components/0/text",
    "message": "Expected stringOrPath, got integer"
  }
}
```

`VALIDATION_FAILED` 是保留常量,便于 LLM 在自纠循环中识别(`a2ui_protocol.md:789-807`)。

---

## 5. 传输契约(Reliability / Framing / Metadata / Bidirectional)

### 5.1 四条契约

来源:`specification/v0_9_1/docs/a2ui_protocol.md:80-93`:

```text
1. Reliable delivery
2. Message framing
3. Metadata support
4. Bidirectional capability (optional)
```

逐条要点:

| 契约 | 要求 |
|------|------|
| **Reliable delivery** | 消息必须**按生成顺序**到达。A2UI 是状态性的(`createSurface` 必须在 `updateComponents` 之前),乱序会破坏 surface 状态。 |
| **Message framing** | 传输必须能区分每个 JSON envelope,常见方式:JSONL 换行、WebSocket 帧、SSE event。 |
| **Metadata support** | 必须支持把额外数据塞在消息旁,用于:① `sendDataModel` 同步 data model;② `client_capabilities` / `server_capabilities` 能力交换。 |
| **Bidirectional capability**(可选)| S2C 流是单向,但 UI 交互需要回传 `action`,所以传输必须支持 C2S 通道(或不阻塞它)。 |

### 5.2 A2A 绑定下的实现

A2A DataPart 编码(`specification/v0_9_1/docs/a2ui_extension_specification.md:71-85`):

- `kind: "data"`
- `metadata.mimeType: "application/a2ui+json"`(v0.9.1 标准化,见 evolution_guide.md:9-15)
- `data` 是**消息列表**,不是单一消息

Processing Rules:

> Receivers MUST process messages in the list sequentially. If a single message in the list fails to validate or apply (e.g., due to a schema violation or invalid reference), the receiver SHOULD report/log the error for that specific message and MUST continue processing the remaining messages in the list.

Atomicity is guaranteed only at the individual message level; 但渲染器**应**等到本批消息全部处理完后再 repaint,避免中间状态闪烁。

### 5.3 Capabilities & Metadata

在 A2A 绑定下,两类 metadata 流入消息:

| 流向 | 字段 | schema |
|------|------|--------|
| C2S | `a2uiClientCapabilities` | `client_capabilities.json` |
| C2S | `a2uiClientDataModel` | `client_data_model.json`(仅当 `sendDataModel=true`) |
| S2C | `a2uiServerCapabilities` | `server_capabilities.json`,通过 AgentCard `extensions[].params` |

`MessageProcessor` 在 Python 侧把多 catalog 聚合成一份 capabilities 报告(`message_processor.py:62-78`):

```python
def get_client_capabilities(self, include_inline_catalogs=False):
    capabilities = {
        "v0.9": {
            "supportedCatalogIds": [c.catalog_id for c in self.catalogs if hasattr(c, "catalog_id")]
        }
    }
    if include_inline_catalogs:
        capabilities["v0.9"]["inlineCatalogs"] = [
            c.catalog_schema for c in self.catalogs if hasattr(c, "catalog_schema")
        ]
    return capabilities
```

对应的 `get_client_data_model()`(`message_processor.py:80-90`)只把 `send_data_model=True` 的 surface 计入 metadata。

---

## 6. Catalog 替换机制

### 6.1 Catalog 在协议中的角色

`specification/v0_9_1/docs/a2ui_protocol.md:146-160` 描述 catalog 与 envelope 的解耦:

> The [`server_to_client.json`] envelope schema is designed to be catalog-agnostic. It references components and themes using a placeholder filename: `catalog.json` (specifically `$ref: "catalog.json#/$defs/anyComponent"` and `$ref: "catalog.json#/$defs/theme"`).
> To validate A2UI messages:
>   1. Basic Catalog: Map `catalog.json` to `catalogs/basic/catalog.json`.
>   2. Client Catalog: Map `catalog.json` to your own catalog file (e.g., `my_company_catalog.json`).

这就是 catalog **可插拔**的核心机制:**所有 envelope 引用的是占位符文件名 `catalog.json`,验证时把它替换成实际 catalog**。

### 6.2 Catalog 内容构成

Basic catalog(`specification/v0_9_1/catalogs/basic/catalog.json`,1383 行)顶层结构:

```json
{
  "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json",
  "components": { "Text": {...}, "Image": {...}, "Row": {...}, ... },
  "functions": { "required": {...}, "regex": {...}, ... },
  "theme":     { "primaryColor": {...}, "iconUrl": {...}, "agentDisplayName": {...} }
}
```

#### 组件清单(`a2ui_protocol.md:662-682`)

| 类型 | 组件 |
|------|------|
| 显示 | Text, Image, Icon, Video, AudioPlayer |
| 布局 | Row, Column, List, Card, Tabs, Divider |
| 反馈 | Modal |
| 交互 | Button, CheckBox, TextField, DateTimeInput, ChoicePicker, Slider |

#### 函数清单(共 14 个,见 §4.2 表格)

#### Theme 字段(`a2ui_protocol.md:707-712`)

```json
{
  "primaryColor":     "#00BFFF",
  "iconUrl":          "https://...",
  "agentDisplayName": "Weather Bot"
}
```

后两个用于**身份归属**,在多 agent / orchestrator 场景由 orchestrator 校验后覆写,防止恶意 agent 伪装(`a2ui_protocol.md:715-717`)。

### 6.3 Catalog 校验约束(用于自定义 catalog)

`a2ui_protocol.md:160-172` 列了 2 条硬约束:

> 1. **Single child references**: 必须用 `ComponentId`,不能写 `"type": "string"`。
> 2. **List references**: 必须用 `ChildList`。

`agent_sdks/python/a2ui_core/src/a2ui/core/validating/catalog_schema_validator.py`(`CatalogSchemaValidator`)负责枚举 catalog 中所有 `single_refs` 与 `list_refs` 字段,然后 IntegrityChecker 用这些字段名去解析组件的 `ComponentId` 引用。

### 6.4 自定义 Catalog 流程

`docs/guides/defining-your-own-catalog.md`(guide 章节)中描述:

1. 拷贝 `catalogs/basic/catalog.json` 作为模板
2. 删去/增加 `components` 内的组件定义
3. 删去/增加 `functions` 内的函数定义
4. 把 `theme` 改为自己设计系统的 token 集合
5. 在 prompt 中把 catalog 内容**替换 basic catalog** 作为 LLM 的 schema 来源
6. Server 端在 `createSurface.catalogId` 指向新 catalog URI(`https://yourcompany.com/...`),客户端从 `client_capabilities.supportedCatalogIds` 中匹配,匹配成功即可渲染

服务端 catalog 实现见 `agent_sdks/python/a2ui_core/src/a2ui/core/catalog/catalog.py:74-142`(`Catalog.from_json()`),它从 JSON Schema 直接构造 catalog 对象,并通过 `$defs.anyComponent` 与 `$defs.anyFunction` 反查允许的组件/函数名集合。

### 6.5 Inline Catalog(运行期内联)

`specification/v0_9_1/json/client_capabilities.json:54-86` 定义 inline catalog 形态,允许 client 在 metadata 中**携带** catalog 定义(用于临时或私有 catalog)。Server 端在 `acceptsInlineCatalogs=true` 时才能接受(`client_capabilities.json:18-21`):

> An array of inline catalog definitions, which can contain both components and functions. This should only be provided if the agent declares 'acceptsInlineCatalogs: true' in its capabilities.

TS 端 `MessageProcessor.generateInlineCatalog()`(`renderers/web_core/src/v0_9/processing/message-processor.ts:87-145`)把 Zod schema 通过 `zod-to-json-schema` 反序列化成 JSON Schema,再用 REF 标记的 description(`REF:<ref>|<text>`)替换回 `$ref`,从而构造标准的 inline catalog。

---

## 7. 数据流端到端示例

来源:`specification/v0_9_1/docs/a2ui_protocol.md:283-292`(完整 Contact Form JSONL)。

```jsonl
{"version":"v0.9.1","createSurface":{"surfaceId":"contact_form_1","catalogId":"https://a2ui.org/.../basic/catalog.json"}}
{"version":"v0.9.1","updateComponents":{"surfaceId":"contact_form_1","components":[{"id":"root","component":"Card","child":"form_container"}, ...]}}
{"version":"v0.9.1","updateDataModel":{"surfaceId":"contact_form_1","path":"/contact","value":{"firstName":"John",...}}}
{"version":"v0.9.1","deleteSurface":{"surfaceId":"contact_form_1"}}
```

`a2ui_protocol.md:48-78` 的 mermaid 时序图总结:

```text
Server->>Client: createSurface
Server->>Client: updateComponents (扁平列表)
Server->>Client: updateDataModel
Client->>Server: action (用户点击 Button 后由 transport.metadata 回传)
Server->>Client: updateComponents / updateDataModel (动态更新)
Server->>Client: deleteSurface
```

---

## 8. 小结

1. **协议只有 4 种 S2C envelope** + **2 种 C2S 消息**(action / error),全部基于 JSON Pointer 数据模型。
2. **common_types.json** 是协议的核心"语法糖",把数据绑定、组件引用、函数调用全部抽象成可复用的 JSON Schema 类型。
3. **数据模型是 reactive 的**,DataModel 实现支持自动插入中间节点、级联订阅与双向绑定。
4. **Action 系统**只有两种形态:发回 server(event)或本地调用 catalog 函数(functionCall)。
5. **传输契约 4 条**:reliable / framed / metadata-bearing / bidirectional-capable。A2A 是当前主推稳定实现,MIME 标准化为 `application/a2ui+json`。
6. **Catalog 替换**通过占位符 `$ref "catalog.json"` 实现,business 可以替换 basic catalog 限定 agent 可用的组件/函数/主题,实现安全边界。

---

## 引用清单

| 文件 | 行 | 用途 |
|------|-----|------|
| `specification/v0_9_1/json/server_to_client.json` | 1-132 | S2C envelope schema |
| `specification/v0_9_1/json/client_to_server.json` | 1-98 | C2S schema(action / error) |
| `specification/v0_9_1/json/common_types.json` | 1-305 | Dynamic* / ChildList / ComponentId / FunctionCall / Action |
| `specification/v0_9_1/json/client_capabilities.json` | 1-89 | C2S capabilities |
| `specification/v0_9_1/json/server_capabilities.json` | 1-26 | S2C capabilities(嵌入 AgentCard) |
| `specification/v0_9_1/catalogs/basic/catalog.json` | 1-1383 | Basic catalog 全集 |
| `specification/v0_9_1/docs/a2ui_protocol.md` | 175-810 | 协议规范主体 |
| `specification/v0_9_1/docs/a2ui_extension_specification.md` | 71-85 | A2A DataPart 编码 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/processing/message_processor.py` | 92-230 | envelope dispatch 与 Surface 状态变更 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/state/data_model.py` | 24-176 | Reactive JSON Pointer store |
| `agent_sdks/python/a2ui_core/src/a2ui/core/state/surface_model.py` | 46-68 | action 事件构造 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/catalog/catalog.py` | 74-142 | Catalog.from_json |
| `agent_sdks/python/a2ui_core/src/a2ui/core/catalog/functions.py` | 18-66 | FunctionApi / FunctionImplementation |
