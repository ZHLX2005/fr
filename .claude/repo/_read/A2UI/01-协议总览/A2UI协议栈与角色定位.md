# A2UI 协议栈与角色定位

> 范围:A2UI v0.9.1(当前生产版本)+ v0.9(稳定)对照。所有结论均来自仓库内源码。

---

## 1. A2UI 是什么

A2UI(Agent-to-User Interface)是一个**面向 LLM 与 agent 的、跨平台的、面向流的 UI 协议**,目标是让 agent 能像"说话"一样生成 UI。其核心定位是"**像数据一样安全,像代码一样表达**"(`safe like data, but expressive like code`)。

仓库根 `README.md:32-33` 给出一句话总结:

> Agents send a declarative JSON format describing the _intent_ of the UI. The client application then renders this using its own native component library (Flutter, Angular, Lit, etc.).

设计哲学在 `README.md:42-66` 中分为 4 点:

- **Security first**(安全第一):agent 输出的是**声明式 JSON 数据**,不是可执行代码;客户端维护一份"目录(catalog)",只能请求渲染目录里**预先批准**的组件。
- **LLM-friendly and incrementally updatable**(LLM 友好、增量可更新):UI 用扁平的 component-by-id 列表描述,LLM 可**渐进式**生成。
- **Framework-agnostic and portable**(框架无关):同一份 A2UI JSON 可被 Flutter / Angular / Lit / React / SwiftUI 等不同客户端渲染。
- **Flexibility**(灵活):可通过"Smart Wrapper"注册自定义组件,把已有 UI(例如安全 iframe)接入 A2UI 的数据绑定与事件系统。

`AGENTS.md:18-26` 进一步明确三大能力:**Streaming UI(渐进渲染)**、**Two-Way Data Binding(双向数据绑定)**、**Local Function Evaluation(本地函数求值)**。

---

## 2. 协议栈分层

A2UI 仓库内证据显示协议栈自上而下分为三层:**规范层 → 传输层 → 渲染层**。

### 2.1 规范层(Spec Layer)

位于 `specification/` 目录,按版本组织为 `v0_8/`、`v0_9/`、`v0_9_1/`、`v1_0/`。`AGENTS.md:43` 明确:

> `specification/`: Versioned subdirectories containing JSON schemas, component/function catalogs, and human-readable guides.

每个版本下固定有:

- `docs/a2ui_protocol.md` — 协议主规范(人类可读)
- `docs/evolution_guide.md` — 版本演进说明
- `docs/a2ui_extension_specification.md` — A2A 扩展机制
- `json/server_to_client.json`、`client_to_server.json`、`common_types.json`、`server_capabilities.json`、`client_capabilities.json` — JSON Schema
- `catalogs/basic/catalog.json` — 默认组件目录

### 2.2 传输层(Transport Layer)

`specification/v0_9_1/docs/a2ui_protocol.md:80-122` 显式声明 **transport-agnostic**(传输无关),只规定 4 条契约:

> 1. **Reliable delivery** — 消息必须按生成顺序到达(状态性更新)。
> 2. **Message framing** — 传输必须明确划分每个 JSON envelope(JSONL 换行、WebSocket 帧、SSE event)。
> 3. **Metadata support** — 必须支持 metadata(用于 client capabilities、server capabilities、sendDataModel)。
> 4. **Bidirectional capability**(可选)— S2C 单向,但需要返回 action 消息时必须支持双向。

`docs/concepts/transports.md:18-25` 给出官方稳定/计划的传输映射:

| 传输 | 状态 |
|------|------|
| **A2A Protocol** | ✅ Stable |
| **AG-UI** | ✅ Stable |
| **REST API** | 📋 Planned |
| **WebSockets** | 💡 Proposed |
| **SSE** | 💡 Proposed |

在 A2A 绑定下,每个 A2UI envelope 映射为 A2A `DataPart`,MIME 固定为 `application/a2ui+json`。`specification/v0_9_1/docs/a2ui_extension_specification.md:71-76`:

```text
To identify a DataPart as containing A2UI data, it must have the following metadata:
- mimeType: application/a2ui+json
```

### 2.3 渲染层(Renderer Layer)

仓库内 `renderers/` 子目录列出多个官方实现(`AGENTS.md:45`):

- `web_core/` — TS 共享核心(state / processing / rendering / reactivity)
- `lit/` — Lit 渲染器
- `angular/` — Angular 渲染器
- `react/` — React 渲染器
- `markdown/` — markdown-it 渲染器(配合 DOMPurify 用于安全 HTML)
- `flutter/` — 占位 README,指向官方 [Flutter GenUI SDK](https://github.com/flutter/genui) 与 `genui_a2a` 包(`renderers/flutter/README.md:5-9`)

---

## 3. Server / Client / Renderer 角色定位

`docs/concepts/glossary.md:7-30` 把角色分为 **Agent**(协议服务器侧)与 **Renderer**(协议客户端侧):

```text
Renderer -> Agent: Catalog & instructions
loop Agentic flow
    Agent -> Renderer: Data + UI Updates. Function calls.
    Renderer -> Agent: User input
```

### 3.1 Server / Agent 角色(协议 S2C 侧)

- 由 LLM(本文是 Gemini / 任意可生成 JSON 的模型)+ Agent 框架(Google ADK / LangGraph / CrewAI / Mastra 等)实现。
- 职责:生成 4 种 envelope(`createSurface` / `updateComponents` / `updateDataModel` / `deleteSurface`)并通过传输层下发。
- Python server SDK 实现在 `agent_sdks/python/a2ui_agent/` 与 `agent_sdks/python/a2ui_core/`。
- 广告能力(广告 catalog 支持集)通过 `a2uiServerCapabilities` 完成,绑定到 A2A AgentCard 的 `AgentCapabilities.extensions[].params`(`specification/v0_9_1/docs/a2ui_extension_specification.md:34-50`):

```json
{
  "uri": "https://a2ui.org/a2a-extension/a2ui/v0.9.1",
  "description": "Ability to render A2UI v0.9.1",
  "required": false,
  "params": {
    "supportedCatalogIds": [
      "https://a2ui.org/specification/v0_9_1/catalogs/basic/catalog.json"
    ],
    "acceptsInlineCatalogs": true
  }
}
```

### 3.2 Client / Renderer 角色(协议 C2S 侧 + 渲染)

- 在客户端进程内,负责:解析 envelope、维护组件状态机、订阅数据模型变化、产出原生 widget、产生 `action` / `error` 消息发回 agent。
- 通过 A2A `Message.metadata.a2uiClientCapabilities` 上报 `supportedCatalogIds`(`specification/v0_9_1/json/client_capabilities.json:8-24`):

```json
{
  "v0.9": {
    "supportedCatalogIds": ["https://a2ui.org/.../catalog.json"],
    "inlineCatalogs": [...]
  }
}
```

- 当 `createSurface.sendDataModel=true` 时,客户端在每次 C2S 消息的 metadata 中带 `a2uiClientDataModel.surfaces[surfaceId]`,这是给"创建该 surface 的那个 server"看的,不会泄露给别的 agent(`specification/v0_9_1/docs/a2ui_protocol.md:578-585`):

> The data model is sent exclusively to the server that created the surface.

### 3.3 协议内部角色(Server 内部 + Renderer 内部)

注意 `docs/concepts/glossary.md:74-98` 把 **Agent architecture** 与 **Renderer stack** 都拆开,允许同进程或跨进程,且支持 orchestrator + sub-agent 模式。这与 `README.md:75-79` 中描述的"Remote Sub-Agents"用例一致。

---

## 4. v0.8 / v0.9 / v0.9.1 / v1.0 演进

来源:`AGENTS.md:30-37`、`specification/v0_9_1/docs/a2ui_protocol.md:31-42`、`specification/v0_9_1/docs/evolution_guide.md`、`docs/concepts/overview.md:30-62`。

| 版本 | 状态 | 关键差异 | 消息类型 |
|------|------|----------|----------|
| **v0.8** | Legacy | 依赖模型**结构化输出**(structured output),schema 受限 | `surfaceUpdate` / `dataModelUpdate` / `beginRendering` / `deleteSurface` |
| **v0.9** | Stable | 切换为 **prompt-first**:schema 直接嵌入 prompt,LLM 按 schema + examples 自由生成 JSON;模塊化拆为 `common_types.json` + `catalog.json` + `server_to_client.json` | `createSurface` / `updateComponents` / `updateDataModel` / `deleteSurface` |
| **v0.9.1** | 最新生产版本 | 仅 patch 变化:MIME 标准化为 `application/a2ui+json`(从旧的 `application/json+a2ui` 改名)、`surfaceId` 不再要求"render 期内全局唯一",只要求"现存 surface 之间唯一" | 同 v0.9,`version` 字段同时接受 `"v0.9"` 和 `"v0.9.1"` |
| **v1.0** | Candidate(原 v0.10) | 新增 `actionResponse`,启用同步 RPC 能力 | 上述 4 种 + `actionResponse` |

`specification/v0_9_1/docs/evolution_guide.md:27-29` 给出迁移说明:

> Since v0.9.1 is fully compatible with v0.9 payloads (the version fields in schemas accept both `"v0.9"` and `"v0.9.1"`), clients and servers can upgrade seamlessly. Action for Implementers: Update any hardcoded MIME type references from `application/json+a2ui` to `application/a2ui+json`.

`specification/v0_9_1/docs/a2ui_protocol.md:31-42` 描述 v0.8 → v0.9 的关键差异(prompt-first 思路):

> While v0.8 was optimized for LLMs that support structured output, v0.9 is designed to be embedded directly within a model's prompt. The LLM is then asked to produce JSON that matches the provided examples and schema descriptions. The main disadvantage of this approach is that it requires more complex post-generation validation.

---

## 5. 与 MCP / A2A / AG-UI 的关系

`README.md:97-101` 明确 A2UI 是**生态胶水层**:

> Transports: Compatible with **A2A Protocol** and **AG-UI**.
> LLMs: Can be generated by any model capable of generating JSON output.
> Host Frameworks: Requires a host application built in a supported framework (currently: Web or Flutter).

### 5.1 与 MCP 的关系

`specification/v0_9_1/docs/a2ui_protocol.md:118-120` 把 MCP 列为支持的传输之一:

> MCP (Model Context Protocol): Delivered as tool outputs or resource subscriptions.

仓库还提供 `docs/guides/a2ui_over_mcp.md` 与 `docs/guides/a2ui-in-mcp-apps.md` 专门讲解 A2UI 跑在 MCP 上:在 MCP 模式下,UI envelope 作为 **tool output** 一次性返回;或在 MCP Apps(`a2ui-in-mcp-apps.md`)扩展协议下作为 **resource subscription** 流式返回。MCP 不直接处理 UI,**A2UI 复用 MCP 的传输**。

### 5.2 与 A2A 的关系

A2UI 是 A2A 之上的**扩展协议**(extension),URI 唯一标识:

```text
https://a2ui.org/a2a-extension/a2ui/v0.9.1
```

`specification/v0_9_1/docs/a2ui_extension_specification.md:8-12`:

> This is the only URI accepted for this extension.

绑定方式(`specification/v0_9_1/docs/a2ui_extension_specification.md:62-66`):

- JSON-RPC / HTTP:`X-A2A-Extensions` HTTP header
- gRPC:`X-A2A-Extensions` metadata value

激活该扩展意味着 server 可以发送 A2UI 消息,client 也预期发送 A2UI 事件。A2UI 复用 A2A 的 `DataPart`,data 字段是**消息列表**(MIME `application/a2ui+json`)。

Python 端实现见 `agent_sdks/python/a2ui_agent/src/a2ui/a2a/extension.py:23-57` 的 `get_a2ui_agent_extension()` 与 `try_activate_a2ui_extension()`,后者负责版本协商,选取两端**共同支持且版本最高**的扩展 URI(`extension.py:100-146`)。

### 5.3 与 AG-UI 的关系

`specification/v0_9_1/docs/a2ui_protocol.md:111-113`:

> AG-UI (Agent to User Interface) is also an excellent transport option for A2UI Agent–User Interaction protocol. AG-UI provides convenient integrations into many agent frameworks and frontends.

`docs/concepts/transports.md:43-47` 进一步描述 AG-UI 是 CopilotKit 的协议,把 A2UI envelope **翻译为 AG-UI events** 并处理传输与状态同步。`README.md:148` 推荐通过 `npx copilotkit@latest init` 快速接入。

### 5.4 三者层次关系

```text
[ LLM Agent (任意可生成 JSON) ]
        │
        │ 生成 envelope
        ▼
[ A2UI Core 协议 ]  ← 规范层(schema + 4 种 envelope + 数据绑定 + catalog)
        │
        │ 经由以下任一传输
        ├── MCP (tool output / resource subscription)
        ├── A2A (DataPart, mimeType=application/a2ui+json)
        ├── AG-UI (转译为 events)
        ├── SSE / WebSocket / REST
        ▼
[ Renderer / Client 端 ]
        ├── Lit / Angular / React / Flutter / Markdown
        ▼
[ 原生 widget 树 ]
```

---

## 6. 小结:A2UI 的本质定位

1. **协议**而非框架:`specification/` 是 source of truth,所有 SDK / 渲染器只是该协议的实现。
2. **声明式 JSON 流**:Server 生成组件描述 + 数据模型更新,Client 把描述映射到原生组件。
3. **catalog 是安全边界**:Agent 不能"自由调用"任意 widget,只能选择 catalog 中预先批准的 component 与 function。
4. **传输无关**:A2A 是当前主推的稳定传输,AG-UI 与 MCP 是生态接入路径,其他 JSON-capable 通道都可承载。
5. **v0.9.1 是生产默认**,v1.0 候选,所有新接入应默认指向 v0.9.1(`AGENTS.md:37`)。

---

## 引用清单

| 文件 | 行 | 用途 |
|------|-----|------|
| `README.md` | 1-160 | 总览、哲学、架构图、传输、状态 |
| `AGENTS.md` | 17-48 | 版本权威、仓库结构 |
| `specification/v0_9_1/docs/a2ui_protocol.md` | 11-122 | 协议主规范、传输契约 |
| `specification/v0_9_1/docs/evolution_guide.md` | 1-29 | v0.9 → v0.9.1 演进 |
| `specification/v0_9_1/docs/a2ui_extension_specification.md` | 1-152 | A2A 扩展 URI、激活、数据编码 |
| `specification/v0_9_1/json/server_to_client.json` | 1-132 | S2C envelope schema |
| `specification/v0_9_1/json/client_capabilities.json` | 1-89 | Client 能力上报 schema |
| `docs/concepts/glossary.md` | 7-98 | 角色、agent 架构选项 |
| `docs/concepts/transports.md` | 1-47 | 传输现状 |
| `docs/concepts/overview.md` | 29-62 | 各版本消息类型对比 |
| `renderers/flutter/README.md` | 1-9 | Flutter 渲染器指向 |
