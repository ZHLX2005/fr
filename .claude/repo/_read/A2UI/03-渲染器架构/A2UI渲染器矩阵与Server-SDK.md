# A2UI 渲染器矩阵与 Server-SDK

> 范围:A2UI 官方渲染器实现差异(Lit / Angular / React / Markdown / Flutter)+ Python Server SDK(parser / schema / basic_catalog / ADK / A2A)+ 消息处理 pipeline + 校验器 + 渲染 binder 机制。

---

## 1. 渲染器对比矩阵

A2UI 的"同一份 JSON、多种 renderer"由两层抽象保证:**TS web_core 提供与框架无关的核心(state / processing / rendering)**,**各 renderer 只做与原生 widget 的映射**。

`AGENTS.md:45` 列出 6 个渲染器位置:

| Renderer | 目录 | 框架 | 状态 |
|----------|------|------|------|
| **Lit** | `renderers/lit/` | Lit (web components) | Stable |
| **Angular** | `renderers/angular/` | Angular | Stable |
| **React** | `renderers/react/` | React | Stable |
| **Markdown** | `renderers/markdown/markdown-it/` | markdown-it + DOMPurify | Stable(共享,用于富文本组件) |
| **Flutter** | `renderers/flutter/`(占位)+ [Flutter GenUI SDK](https://github.com/flutter/genui) | Flutter | Stable,外置实现 |
| **Web Core** | `renderers/web_core/` | 框架无关的 TS 核心 | 共享基座 |

### 1.1 Lit 渲染器

`renderers/lit/src/v0_9/index.ts:17-22` 导出 5 个对象:

```ts
export type {LitComponentApi} from './types.js';
export {A2uiController} from './a2ui-controller.js';
export {A2uiSurface} from './surface/a2ui-surface.js';
export {A2uiLitElement} from './a2ui-lit-element.js';
export {Context} from './context/context.js';
export {basicCatalog} from './catalogs/basic/index.js';
```

**核心组件:**

- `A2uiSurface`(`surface/a2ui-surface.ts:32-...`):Lit element,接收 `SurfaceModel` 作为 property,内部订阅 `componentsModel.onCreated` 等待 `id === 'root'` 出现才允许渲染。`willUpdate`(`a2ui-surface.ts:58-78`)是核心生命周期钩子。
- `A2uiController<Api>`(`a2ui-controller.ts:34-88`):`Lit ReactiveController`,持有 `GenericBinder` 订阅,新 props 到达时调用 `host.requestUpdate()`:

```ts
constructor(private host: A2uiLitElement<any>, api: Api) {
    this.binder = new GenericBinder(this.host.context, api.schema);
    this.props = this.binder.snapshot as ...;
    this.host.addController(this);
    if (this.host.isConnected) this.hostConnected();
}
hostConnected() {
    if (!this.subscription) {
        this.subscription = this.binder.subscribe(newProps => {
            this.props = newProps;
            this.host.requestUpdate();
        });
    }
}
```

- `renderA2uiNode.ts`:递归把 component tree 转成 `html` 模板字符串(用 lit-html 的 `TemplateResult`)。

### 1.2 React 渲染器

`renderers/react/src/v0_9/index.ts` 公开 `A2uiSurface`、`adapter`(把 native React component 适配成 ComponentApi)。

关键文件 `A2uiSurface.tsx:21-63` 用 `React.useSyncExternalStore` 订阅 `SurfaceModel` 的 `componentsModel`:

```tsx
const ResolvedChild = memo(({surface, id, basePath, compImpl, componentModel}) => {
    const ComponentToRender = compImpl.render;
    const context = useMemo(
        () => new ComponentContext(surface, id, basePath),
        [surface, id, basePath, componentModel],
    );
    const buildChild = useCallback((childId, specificPath) => {
        const path = specificPath || context.dataContext.path;
        return <DeferredChild key={`${childId}-${path}`} surface={surface} id={childId} basePath={path} />;
    }, [surface, context.dataContext.path]);
    return <ComponentToRender context={context} buildChild={buildChild} />;
});
```

`DeferredChild`(`A2uiSurface.tsx:65-...`)用 `useSyncExternalStore` 在子组件 `onCreated`/`onDeleted` 时递增 version 触发重渲染。React renderer 完全靠 hook 拿到 reactive 状态,不依赖 lit 的 ReactiveController。

### 1.3 Angular 渲染器

`renderers/angular/` 下同样分 `v0_8/` 与 `v0_9/`,公开 API 在 `public-api.ts`。Angular 用 RxJS 风格的 `BehaviorSubject` 暴露 props,模板层订阅 component tree。

### 1.4 Markdown 渲染器(`Text` 组件用)

`renderers/markdown/markdown-it/README.md:1-7`:

> Markdown renderer for A2UI using markdown-it and dompurify. This is used across all JS renderers, so the configuration is consistent. This package provides a pre-configured `renderMarkdown` function that is injected into the respective Markdown Renderer service of each renderer.

由 `markdown-it` 解析 + `dompurify` 消毒,所有 JS renderer 的 `Text` 组件都会注入这个函数。Markdown 仅渲染 **Text 组件的 `text` 字段**,不替代整张 surface 的渲染管线。

### 1.5 Flutter 渲染器

`renderers/flutter/README.md:1-9`:

> The [Flutter Gen UI SDK](https://github.com/flutter/genui) is the official Flutter renderer for A2UI.
> - `genui`: 核心框架
> - `genui_a2a`: 充当 A2UI 后端 agent 的 renderer,接入 A2UI 协议

本仓库内 Flutter 目录只占位,实现位于外部 Flutter 仓库。A2UI 与 Flutter 渲染端的边界通过 `genui_a2a` 包对接到 Flutter widget 树。

### 1.6 各 renderer 共享的核心

`renderers/web_core/src/v0_9/index.ts:24-40` 一次性导出 16 类共享原语:

```ts
export * from './catalog/function_invoker.js';
export * from './catalog/types.js';
export * from './common/events.js';
export * from './processing/message-processor.js';
export * from './rendering/component-context.js';
export * from './rendering/data-context.js';
export * from './rendering/generic-binder.js';
export * from './schema/index.js';
export * from './state/component-model.js';
export * from './state/data-model.js';
export * from './state/surface-components-model.js';
export * from './state/surface-group-model.js';
export * from './state/surface-model.js';
export * from './errors.js';
export * from './basic_catalog/index.js';

export {effect, Signal, signal, computed} from '@preact/signals-core';
```

注意最后一行:web_core 用 `@preact/signals-core` 提供 `Signal` / `computed` / `effect`,作为整个 reactive 系统的运行时底层。所有 renderer(Lit 用 controller、React 用 useSyncExternalStore)都从这个 signal pool 订阅。

### 1.7 渲染器对比表

| 维度 | Lit | React | Angular | Markdown | Flutter |
|------|-----|-------|---------|----------|---------|
| 框架抽象 | Lit ReactiveController | useSyncExternalStore + memo | RxJS BehaviorSubject | markdown-it + DOMPurify | Flutter Widget |
| 核心组件 | A2uiSurface / A2uiController | A2uiSurface / ResolvedChild | A2uiSurfaceDirective | renderMarkdown | genui_a2a |
| Signal 后端 | @preact/signals-core | @preact/signals-core | @preact/signals-core | n/a | Dart Stream |
| 渐进渲染 | placeholder ID | loading_*_id | loading_*_id | n/a(纯文本) | 占位 widget |
| 安全 | DOMPurify(markdown) | DOMPurify(markdown) | DOMPurify(markdown) | DOMPurify(markdown) | widget 边界 |
| 状态机入口 | `web_core.MessageProcessor` | 同上 | 同上 | n/a | genui |

---

## 2. Python Server SDK

源码位置:`agent_sdks/python/a2ui_core/` 与 `agent_sdks/python/a2ui_agent/`。`AGENTS.md:44` 把它归为 "Server integration SDKs for Python"。

### 2.1 a2ui_core(无 UI 依赖的协议核心)

`a2ui_core/src/a2ui/core/` 子目录(`__init__.py`、`schema/`、`catalog/`、`state/`、`processing/`、`rendering/`、`validating/`、`basic_catalog/`、`common/`)。

#### schema(自动生成的 Pydantic 模型)

`a2ui_core/src/a2ui/core/schema/server_to_client.py:100-105`:

```python
A2uiMessage = Union[
    CreateSurfaceMessage,
    UpdateComponentsMessage,
    UpdateDataModelMessage,
    DeleteSurfaceMessage,
]

class A2uiMessageListWrapper(StrictBaseModel):
    messages: List[A2uiMessage] = Field(..., description="A list of messages.")
```

每条 message 用 `Literal[SPEC_VERSION]` 限制 `version` 字段。Common types 在 `a2ui_core/src/a2ui/core/schema/common_types.py`(从 `common_types.json` 生成)。`a2ui_core/src/a2ui/core/schema/client_to_server.py` 对应 C2S。

#### catalog(目录对象的内存模型)

`a2ui_core/src/a2ui/core/catalog/catalog.py:30-142`:

```python
class Catalog(Generic[TComponent, TFunction]):
    def __init__(self, catalog_id, spec_version, components, functions, theme_schema={}):
        ...
        self.components: Dict[str, TComponent] = {c.name: c for c in components}
        self.functions: Dict[str, TFunction] = {fn.name: fn for fn in functions}
        ...

    @classmethod
    def from_json(cls, catalog_schema, spec_version, catalog_id=None) -> "Catalog":
        """Constructs a schema-only Catalog directly from raw JSON Schema."""
        catalog_id = catalog_id or catalog_schema.get("catalogId")
        components_map = catalog_schema.get("components", {})
        any_comp_refs = catalog_schema.get("$defs", {}).get("anyComponent", {}).get("oneOf", [])
        permitted_names = set()
        for item in any_comp_refs:
            ref = item.get("$ref", "")
            if isinstance(ref, str) and ref.startswith("#/components/"):
                permitted_names.add(ref.split("/")[-1])
        ...
```

`get_function()` 还能容忍大小写变体(`catalog.py:61-69`),这是为了兼容 catalog 里 `call` 字段大小写不一致的历史 JSON。

`catalog/functions.py:18-67` 定义 `FunctionApi`(纯 schema)与 `FunctionImplementation`(schema + execute 函数);`create_function_implementation(api, execute)` 是工厂。执行统一走 `FunctionImplementation.execute()`,会先做 Pydantic schema 校验(`functions.py:51-55`)。

#### state(状态机)

`a2ui_core/src/a2ui/core/state/` 5 个模型:

| 文件 | 职责 |
|------|------|
| `surface_group_model.py` | 全局容器,管理多个 `SurfaceModel`,触发全局事件 |
| `surface_model.py` | 单个 surface 状态(id / catalog / theme / send_data_model / data_model / components_model / on_action / on_error) |
| `surface_components_model.py` | 单 surface 内组件字典,触发 on_created / on_updated / on_deleted |
| `component_model.py` | 单组件(id / type / properties / on_updated) |
| `data_model.py` | RFC 6901 JSON Pointer reactive store,见上文 §3 |

`SurfaceModel.dispatch_action()`(`surface_model.py:46-68`)把组件的 `action.event` 或 `action.functionCall` 标准化为 C2S `action` envelope。

#### processing(message processor)

见下文 §3 单独章节。

#### rendering(generic binder / data context)

见下文 §4 单独章节。

#### validating(校验器)

见下文 §5 单独章节。

#### basic_catalog(basic catalog 的运行时实现)

`a2ui_core/src/a2ui/core/basic_catalog/__init__.py:15-87` 把 basic catalog 的所有 17 个组件 + 14 个函数 + 11 个 operator 函数 + Theme 集中装配:

```python
class BasicCatalog(Catalog[ModelComponentApi, FunctionImplementation]):
    def __init__(self, locale: Optional[str] = None):
        super().__init__(
            catalog_id=_basic_catalog_id(SPEC_VERSION),
            spec_version=SPEC_VERSION,
            components=BASIC_COMPONENTS,
            functions=create_basic_catalog_functions(locale),
            theme_schema=Theme.model_json_schema(),
        )
```

`components.py`(生成)定义每个组件的 Pydantic 模型,如 `TextComponent`(`basic_catalog/components.py:62-70`):

```python
class TextComponent(CatalogComponentCommon):
    component: Literal["Text"] = "Text"
    text: DynamicString = Field(...)
    variant: Optional[Literal["h1", "h2", "h3", "h4", "h5", "caption", "body"]] = Field(
        description="A hint for the base text style.", default="body"
    )
```

`function_apis.py` 定义 14 个基础函数 + `function_impls.py` 给出对应的 Python 实现。`operator_apis.py` 提供 `add/sub/mul/div/equals/...` 等算子(扩展包)。`expression_parser.py` 是 `${...}` 字符串插值解析器;`locale_config.py` 处理 CLDR 与货币符号。

### 2.2 a2ui_agent(LLM 输出 → A2UI envelope 的桥梁)

源码位置:`agent_sdks/python/a2ui_agent/src/a2ui/`。它依赖 `a2ui_core` 并增加 LLM 输出端工具。

#### parser(LLM 输出解析)

入口 `parser/parser.py:45-88`,识别 LLM 输出中的 `<a2ui-json>...</a2ui-json>` 标签(`A2UI_OPEN_TAG` / `A2UI_CLOSE_TAG`,定义在 `parser/constants.py`):

```python
def parse_response(content: str) -> List[ResponsePart]:
    matches = list(_A2UI_BLOCK_PATTERN.finditer(content))
    ...
    for match in matches:
        text_part = content[last_end:start].strip()
        json_string = match.group(1)
        json_string_cleaned = _sanitize_json_string(json_string)
        json_data = parse_and_fix(json_string_cleaned)
        response_parts.append(ResponsePart(text=text_part, a2ui_json=json_data))
    ...
```

`_A2UI_BLOCK_PATTERN`(`parser.py:22-24`):

```python
_A2UI_BLOCK_PATTERN = re.compile(
    f"{re.escape(A2UI_OPEN_TAG)}(.*?){re.escape(A2UI_CLOSE_TAG)}", re.DOTALL
)
```

`payload_fixer.parse_and_fix` 自动修复不完整 JSON(LLM 输出经常在最后一个 brace 被截断)。

##### 流式解析器(关键能力)

`parser/streaming.py:46-347` `A2uiStreamParser` 是 v0.9 的核心流式入口。它通过 `__new__`(`streaming.py:53-66`)按 catalog.version 选择 `A2uiStreamParserV08` / `A2uiStreamParserV09` 子类。

`process_chunk(chunk)`(`streaming.py:246-347`)逐字符扫描:

1. 先等 `<a2ui-json>` 开放标签
2. 找 `</a2ui-json>` 关闭标签前的安全边界(防止半截标签)
3. 调用 `_process_json_chunk`,在 JSON buffer 中追踪 `{}`、`[]`、字符串状态(`streaming.py:436-572`)
4. 每个**完整对象**就立即识别并 yield,**部分对象**由 `_sniff_partial_component` 与 `_sniff_partial_data_model` 试探出早期可渲染内容
5. 用 `analyze_topology`(`validating/topology_analyzer.py:20-89`)找当前可见的可达子集,从 `root` 出发 DFS 找出当前 stream 状态下可渲染的部分
6. 把"未到达的子组件 ID"用 `loading_<id>` placeholder 替换(`streaming.py:964-1067`),保证客户端可渐进渲染

`_sniff_partial_data_model` 还在数据模型层做"已变更 key 的增量 update",保证 `updateDataModel` 也能流式落地。

`A2uiStreamParser` 还维护 `seen_components`、`yielded_ids`、`yielded_contents`(用于 hash 比较)、`deleted_surfaces` 等增量去重状态,避免同一条 component 在多个 chunk 中重复 yield。

#### adk(Google ADK 集成)

入口 `adk/send_a2ui_to_client_toolset.py:131-326` `SendA2uiToClientToolset` 暴露给 ADK agent 的工具集,接受 `a2ui_enabled` / `a2ui_catalog` / `a2ui_examples` 三个 provider:

- `_SendA2uiJsonToClientTool.run_async()`(`send_a2ui_to_client_toolset.py:296-326`):LLM 调用 `send_a2ui_json_to_client(a2ui_json)` 工具时,执行 `parse_and_fix` + `a2ui_catalog.validator.validate` 两步校验,通过后写入 `validatedA2uiJsonKey` 返回。
- `process_llm_request`(`send_a2ui_to_client_toolset.py:277-294`):把 catalog 的 LLM instruction + examples 追加到 system instructions,确保 LLM 知道可用组件与样例。

`adk/a2a/part_converter.py`(`A2uiPartConverter`)把 GenAI 的 `Part` 转成 A2A `Part`(识别 FunctionResponse 中的 `send_a2ui_json_to_client` 工具结果,以及文本中的 `<a2ui-json>` 块)。`adk/a2a/event_converter.py` 把多个 event 合并输出。

#### a2a(A2A 扩展注册)

`a2a/extension.py:23-146` 提供 3 个能力:

- `A2UI_EXTENSION_BASE_URI = "https://a2ui.org/a2a-extension/a2ui"`(`extension.py:23`)
- `get_a2ui_agent_extension(version, accepts_inline_catalogs, supported_catalog_ids)`(`extension.py:28-56`):构造 `AgentExtension`,自动拼出 `https://a2ui.org/a2a-extension/a2ui/v0.9.1` URI。
- `try_activate_a2ui_extension(context, agent_card)`(`extension.py:119-146`):从 client request 与 agent card 中匹配共同支持的扩展 URI,用 `packaging.version.parse` 排序取最高版本。

`a2a/parts.py` 提供 `create_a2ui_part` / `parse_response_to_parts`,把 GenAI/A2A 消息与 A2UI envelope 互转。

#### schema / template / inference_strategy

- `schema/catalog.py` `A2uiCatalog`:把 catalog JSON + validator + LLM instructions 集成的运行时形态。
- `template/` 提供 few-shot 模板渲染。
- `inference_strategy.py`:指导 LLM 推断下一步该发什么 envelope。

---

## 3. 消息处理 Pipeline(MessageProcessor)

### 3.1 Python `MessageProcessor`

`agent_sdks/python/a2ui_core/src/a2ui/core/processing/message_processor.py:30-231`,核心是 `process_messages` + `_process_message` 派发。

入口接收 list 或 `{messages: [...]}`(`message_processor.py:48-60`):

```python
def process_messages(self, messages):
    message_list = (
        messages.get("messages", []) if isinstance(messages, dict) else messages
    )
    if self.strict_mode:
        self.validator.validate_protocol_envelope(message_list)
    for msg in message_list:
        self._process_message(msg)
```

每条消息按 4 种类型分发:

| 消息 | 方法 | 关键操作 |
|------|------|----------|
| `createSurface` | `_process_create_surface`(`118-152`) | 找到 catalog;创建 `SurfaceModel` 并 `model.add_surface(...)`;strict 模式下用 `CatalogSchemaValidator` 验证 theme |
| `updateComponents` | `_process_update_components`(`158-215`) | 找到 surface 与 catalog;strict 模式校验;遍历 components,处理 type 变更(重建)与属性覆盖 |
| `updateDataModel` | `_process_update_data_model`(`217-230`) | 找到 surface;`surface.data_model.set(path, value)` 触发 reactive 通知 |
| `deleteSurface` | `_process_delete_surface`(`153-156`) | `model.delete_surface(surface_id)` |

Capabilities 聚合(`message_processor.py:62-78`)和 client data model 聚合(`80-90`)在 processor 自身提供。

### 3.2 TS `MessageProcessor`(对照)

`renderers/web_core/src/v0_9/processing/message-processor.ts:48-354`。结构与 Python 端**一一对应**:

- `processMessages(messages)`(`222-227`)拆 list 后逐条 `processMessage`
- `processCreateSurfaceMessage`(`264-280`):按 `catalogId` 找 catalog;surface 已存在抛错;建 `SurfaceModel`
- `processUpdateComponentsMessage`(`288-322`):同 Python,type 变更重建
- `processUpdateDataModelMessage`(`324-336`):`surface.dataModel.set(path, value)`
- `processDeleteSurfaceMessage`(`282-286`):`this.model.deleteSurface(...)`

TS 端多出的能力(`message-processor.ts:87-201`):

- `getClientCapabilities({ includeInlineCatalogs })` 把 Zod catalog 转为 JSON Schema 包装的 inline catalog,自动处理 `REF:` 标记的 description(把 `description: "REF:common_types.json#/$defs/ComponentId|..."` 还原成 `{$ref: "..."}`)
- `getClientDataModel()` 收集所有 `sendDataModel=true` 的 surface 当前 data model
- `onSurfaceCreated` / `onSurfaceDeleted` 订阅

### 3.3 TS ↔ Python 对应关系

| 行为 | Python | TS web_core |
|------|--------|-------------|
| 数据模型 | `DataModel` (手写) | `data-model.ts` (手写 + Signals) |
| 组件模型 | `ComponentModel` | `component-model.ts` |
| Surface 集合 | `SurfaceGroupModel` | `surface-group-model.ts` |
| 单 surface | `SurfaceModel` | `surface-model.ts` |
| 事件总线 | `common/events.py` (Subscription/EventSource) | `common/events.ts` |
| 反应式 runtime | Python 直接调用 | `@preact/signals-core` |
| Catalog | `Catalog[ComponentApi, FunctionApi]` | `Catalog<T>` |
| Validator | Pydantic-based `A2uiValidator` + 手工 integrity / topology | Zod-based |
| Function runtime | `FunctionImplementation.execute()` | `FunctionInvoker` |

---

## 4. 校验器(Validator / IntegrityChecker / TopologyAnalyzer)

`agent_sdks/python/a2ui_core/src/a2ui/core/validating/` 3 个核心文件。

### 4.1 A2uiValidator(Pydantic 顶层校验)

`validating/validator.py:68-216`:

- `validate_protocol_envelope(messages)`(`71-87`):先校验每条消息有 `version`,再调用 `A2uiMessageListWrapper.model_validate({"messages": messages})` 做 Pydantic 校验,最后跑 `validate_recursion_and_paths`(防止 JSON 嵌套过深或路径非法)
- `_format_validation_errors`(`89-135`):过滤掉 oneOf 中**未被选中分支**的误报,使错误信息只显示真正匹配失败的分支
- `validate_components(schema_validator, components, config)`(`137-171`):对每个 component 单独 schema 校验(避免 fail-fast),再用 `IntegrityChecker` 检查引用 + 用 `TopologyAnalyzer` 检查孤岛/环
- `validate(...)`(`173-216`):高层 API,自动处理"增量 update 无 createSurface 时打开 allow_missing_root"

两个全局 preset(`validator.py:53-58`):

```python
STRICT_VALIDATION = ValidationConfig()
RELAXED_VALIDATION = ValidationConfig(
    allow_orphan_components=True,
    allow_dangling_references=True,
    allow_missing_root=True,
)
```

### 4.2 IntegrityChecker(引用完整性)

`validating/integrity_checker.py:75-156`:

```python
def validate_component_integrity(components, ref_fields_map, root_id=ROOT_ID,
                                 allow_dangling_references=False, allow_missing_root=False):
    ids = set()
    # 1. Collect IDs and check for duplicates
    for comp in components:
        comp_id = comp.get("id")
        if comp_id in ids:
            raise ValueError(f"Duplicate component ID: {comp_id}")
        ids.add(comp_id)

    if allow_dangling_references:
        return

    # 2. Check for root component
    if not allow_missing_root and root_id not in ids:
        raise ValueError(f"Missing root component: No component has id='{root_id}'")

    # 3. Check for dangling references using helper
    for comp in components:
        for ref_id, field_name in get_component_references(comp, ref_fields_map):
            if ref_id not in ids:
                raise ValueError(
                    f"Component '{comp_id}' references non-existent component '{ref_id}' in field '{field_name}'"
                )
```

`ref_fields_map` 由 `CatalogSchemaValidator.extract_ref_fields()` 从 catalog 的 `$ref` 收集得到,key 是 component type,value 是 `(single_refs, list_refs)`。

`validate_recursion_and_paths`(`integrity_checker.py:112-156`)递归检查:

- 全局深度上限 `MAX_GLOBAL_DEPTH = 50`
- 函数调用深度上限 `MAX_FUNC_CALL_DEPTH = 5`
- path 必须匹配正则 `^(?:(?:\/(?:[^~\/]|~[01])*)*|(?:[^~\/]|~[01])+(?:\/(?:[^~\/]|~[01])*)*)$` (RFC 6901 + 相对路径)

### 4.3 TopologyAnalyzer(拓扑分析)

`validating/topology_analyzer.py:20-89`:

```python
def analyze_topology(components, ref_fields_map, root_id=ROOT_ID,
                     allow_orphan_components=False, allow_missing_root=False):
    adj_list = {}
    all_ids = set()
    for comp in components:
        comp_id = comp.get("id")
        all_ids.add(comp_id)
        adj_list.setdefault(comp_id, [])
        for ref_id, field_name in get_component_references(comp, ref_fields_map):
            if ref_id == comp_id:
                raise ValueError(f"Self-reference detected: ...")
            adj_list[comp_id].append(ref_id)

    # DFS 检测 cycle + 深度
    visited, recursion_stack = set(), set()
    def dfs(node_id, depth):
        if depth > MAX_GLOBAL_DEPTH:
            raise ValueError(f"Global recursion limit exceeded")
        visited.add(node_id); recursion_stack.add(node_id)
        for neighbor in adj_list.get(node_id, []):
            if neighbor not in visited:
                dfs(neighbor, depth + 1)
            elif neighbor in recursion_stack:
                raise ValueError(f"Circular reference detected ...")
        recursion_stack.remove(node_id)

    if allow_missing_root:
        for node_id in sorted(list(all_ids)):
            if node_id not in visited:
                dfs(node_id, 0)
    else:
        if root_id in all_ids:
            dfs(root_id, 0)
        if not allow_orphan_components:
            orphans = all_ids - visited
            if orphans:
                raise ValueError(f"Component '{orphans[0]}' is not reachable from '{root_id}'")
    return visited
```

这是流式解析器能"提前 yield"的关键——`A2uiStreamParser`(`streaming.py:873-878`)在每个 chunk 末尾调用 `analyze_topology` 找当前**从 root 可达**的子集,把这些 component 包装成 partial message 立即下发,未到达的 ID 用 `loading_<id>` 替换。

---

## 5. 渲染 Binder 机制

### 5.1 三层 Context

`a2ui_core/src/a2ui/core/rendering/` 提供 binder 与 context:

| 文件 | 角色 |
|------|------|
| `component_context.py` | 单组件上下文:把 surface / component_id / base_path / data_context 打包 |
| `data_context.py` | 数据上下文:订阅 DynamicString/DynamicNumber/DynamicBoolean/DynamicStringList,执行 FunctionCall |
| `generic_binder.py` | 通用 binder:监听 component_model.on_updated + data_model 多个 path,输出 resolved props |

### 5.2 GenericBinder 关键代码

`generic_binder.py:21-66`:

```python
class GenericBinder:
    def __init__(self, context: ComponentContext):
        self.context = context
        self.data_listeners = []
        self.listeners = set()
        self.current_props = {}
        self.comp_unsub = None
        # 订阅 component model 更新
        sub = self.context.component_model.on_updated.subscribe(
            lambda _: self._rebuild_all_bindings()
        )
        self.comp_unsub = lambda: sub.unsubscribe()
        self._rebuild_all_bindings()

    def _rebuild_all_bindings(self):
        # 清理已有 data 订阅
        for listener in self.data_listeners:
            listener.unsubscribe()
        self.data_listeners = []

        raw_props = self.context.component_model.properties
        resolved_props = {}
        for k, v in raw_props.items():
            if k != "checks":
                resolved_props[k] = self._bind_property(k, v)
        self.current_props = resolved_props

        if "checks" in raw_props:
            self.current_props["checks"] = raw_props["checks"]
            self._bind_checks(raw_props["checks"])

        self._notify()
```

`_bind_property`(`generic_binder.py:68-111`)判断三种动态形态:

```python
is_dynamic = isinstance(value, dict) and "path" in value and isinstance(value["path"], str)
is_func    = isinstance(value, dict) and "call" in value and isinstance(value["call"], str)
is_interpolatable = isinstance(value, str) and "${" in value

if is_dynamic or is_func or is_interpolatable:
    def on_change(new_val):
        self.current_props[key] = new_val
        self._notify()
    bound = self.context.data_context.subscribe_dynamic_value(value, on_change)
    self.data_listeners.append(bound)
    return bound.value
```

任何 Dynamic* / FunctionCall / `${...}` 字符串都会被**订阅**到一个 data path,初始值通过 `Subscription(initial_value=...)` 立即返回,后续 path 变化触发 `on_change` → `current_props[key] = new_val` → `_notify()` 推给所有 listener。

`_bind_checks`(`generic_binder.py:113-151`)统一处理 `CheckRule`(校验规则),把所有规则的 `condition` 求值后合并 `isValid` 与 `validationErrors`:

```python
def update_validation_state():
    errors = [r["message"] for r in rule_results if not r["valid"]]
    self.current_props["isValid"] = len(errors) == 0
    self.current_props["validationErrors"] = errors
    self._notify()
```

最后 `subscribe(listener)`(`generic_binder.py:160-164`)注册 listener 并**立即用当前 props 调一次**,保证新订阅者拿到初始值。

### 5.3 跨 renderer 复用

TS 端 `renderers/web_core/src/v0_9/rendering/generic-binder.ts` 是同一机制的 Signals 版实现。Lit 的 `A2uiController` 与 React 的 `ComponentContext` 都通过它拿到 resolved props,只是把"如何把 props 喂给框架"换成对应的 hook(Lit 用 ReactiveController、React 用 useSyncExternalStore)。

### 5.4 调用链总览

```text
MessageProcessor (envelope 入口)
    │
    ▼
SurfaceGroupModel / SurfaceModel / SurfaceComponentsModel / ComponentModel / DataModel
    │
    ▼ (订阅)
ComponentContext + DataContext
    │
    ▼
GenericBinder._rebuild_all_bindings()
    ├─ Dynamic* / FunctionCall / `${...}` → DataContext.subscribe_dynamic_value
    └─ CheckRule                   → DataContext.subscribe_dynamic_value (condition)
    │
    ▼ (props 推给 framework)
Lit: A2uiController.host.requestUpdate()
React: useSyncExternalStore 重渲染
Angular: BehaviorSubject.next()
Flutter: genui widget 重建
```

---

## 6. Server SDK 端到端集成样例(以 Google ADK 为例)

`agent_sdks/python/a2ui_agent/src/a2ui/adk/send_a2ui_to_client_toolset.py:131-326` 提供与 Google ADK 集成的完整流程:

```python
LlmAgent(
    tools=[
        SendA2uiToClientToolset(
            a2ui_enabled=check_enabled,
            a2ui_catalog=get_catalog,    # Catalog[A2uiCatalog]
            a2ui_examples=fetch_examples,
        ),
    ],
)
```

1. `process_llm_request` 把 catalog + examples 注入 system prompt
2. LLM 调用 `send_a2ui_json_to_client(a2ui_json="<a2ui-json>{...}</a2ui-json>")`
3. `_SendA2uiJsonToClientTool.run_async` 调 `parse_and_fix` + `catalog.validator.validate` 校验 JSON
4. 通过后存入 `validatedA2uiJsonKey` 返回,框架后续交给 `A2uiPartConverter` 转 A2A `DataPart`
5. A2A 在传输层带 `mimeType=application/a2ui+json`,client 端 Renderer 按 envelope 渲染

---

## 7. 小结

1. **渲染器矩阵**:5 个官方 renderer(Lit / React / Angular / Markdown / Flutter),共享 `web_core` 的 state / processing / rendering。
2. **Python SDK**:a2ui_core 提供无 UI 的协议运行时(状态机 + 校验 + binder),a2ui_agent 提供 LLM 输出端的解析与 ADK/A2A 集成。
3. **MessageProcessor** 是协议入口的"中央控制器",Python 与 TS 双实现结构对齐。
4. **校验器** 3 件套:`A2uiValidator`(Pydantic envelope)、`IntegrityChecker`(引用与路径)、`TopologyAnalyzer`(可达与环)。
5. **Binder 机制** 把"组件属性 → DataModel path/FunctionCall/插值字符串"实时解析为 resolved props,framework 层只用负责把 resolved props 渲染成 widget。
6. **流式渲染** 通过 `A2uiStreamParser` + `analyze_topology` 实现"边收边渲染",未到达的 component 用 `loading_<id>` placeholder 替代。

---

## 引用清单

| 文件 | 行 | 用途 |
|------|-----|------|
| `AGENTS.md` | 17-48 | 仓库结构、版本、SDK 入口 |
| `renderers/lit/src/v0_9/index.ts` | 17-22 | Lit 渲染器导出 |
| `renderers/lit/src/v0_9/a2ui-controller.ts` | 34-88 | Lit ReactiveController |
| `renderers/lit/src/v0_9/surface/a2ui-surface.ts` | 32-78 | Lit A2uiSurface 生命周期 |
| `renderers/react/src/v0_9/A2uiSurface.tsx` | 21-99 | React ResolvedChild + DeferredChild |
| `renderers/web_core/src/v0_9/index.ts` | 24-46 | 共享核心导出 |
| `renderers/web_core/src/v0_9/processing/message-processor.ts` | 48-354 | TS 端 MessageProcessor + InlineCatalog |
| `renderers/markdown/markdown-it/README.md` | 1-22 | markdown-it + DOMPurify 共享说明 |
| `renderers/flutter/README.md` | 1-9 | Flutter 渲染器指向 genui / genui_a2a |
| `agent_sdks/python/a2ui_core/src/a2ui/core/schema/server_to_client.py` | 100-110 | A2uiMessage + A2uiMessageListWrapper |
| `agent_sdks/python/a2ui_core/src/a2ui/core/catalog/catalog.py` | 30-142 | Catalog + from_json |
| `agent_sdks/python/a2ui_core/src/a2ui/core/catalog/functions.py` | 18-66 | FunctionApi / FunctionImplementation |
| `agent_sdks/python/a2ui_core/src/a2ui/core/state/surface_model.py` | 25-97 | 单 surface 状态与 dispatch_action |
| `agent_sdks/python/a2ui_core/src/a2ui/core/state/data_model.py` | 24-176 | RFC 6901 reactive store |
| `agent_sdks/python/a2ui_core/src/a2ui/core/processing/message_processor.py` | 30-231 | Python MessageProcessor |
| `agent_sdks/python/a2ui_core/src/a2ui/core/rendering/generic_binder.py` | 21-175 | 通用 binder |
| `agent_sdks/python/a2ui_core/src/a2ui/core/validating/validator.py` | 68-216 | A2uiValidator |
| `agent_sdks/python/a2ui_core/src/a2ui/core/validating/integrity_checker.py` | 75-156 | 引用完整性 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/validating/topology_analyzer.py` | 20-89 | 拓扑分析 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/basic_catalog/__init__.py` | 15-87 | BasicCatalog 装配 |
| `agent_sdks/python/a2ui_core/src/a2ui/core/basic_catalog/components.py` | 62-70 | TextComponent Pydantic |
| `agent_sdks/python/a2ui_core/src/a2ui/core/basic_catalog/function_apis.py` | 23-50 | 基础函数 Pydantic 模型 |
| `agent_sdks/python/a2ui_agent/src/a2ui/parser/parser.py` | 22-88 | 非流式 parse_response |
| `agent_sdks/python/a2ui_agent/src/a2ui/parser/streaming.py` | 46-1067 | 流式 A2uiStreamParser |
| `agent_sdks/python/a2ui_agent/src/a2ui/adk/send_a2ui_to_client_toolset.py` | 131-326 | Google ADK toolset 集成 |
| `agent_sdks/python/a2ui_agent/src/a2ui/a2a/extension.py` | 23-146 | A2A 扩展 URI + 版本协商 |
