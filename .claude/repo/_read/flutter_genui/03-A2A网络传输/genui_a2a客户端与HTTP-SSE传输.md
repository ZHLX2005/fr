# genui_a2a 客户端与 HTTP/SSE 传输

> 本文聚焦 `packages/genui_a2a/` 子包:**A2A 协议是什么、Flutter 端怎么实现、HTTP/SSE 怎么流式收 A2UI 消息、它与 A2UI envelope 的关系**。
> 全部基于 `D:\code\a_dart\prj\fr\.claude\repo\flutter_genui\packages\genui_a2a\` 源码。

---

## 1. A2A 协议是什么

**A2A(Agent-to-Agent)** 是一个 **JSON-RPC 2.0 over HTTP/SSE** 的多 Agent 通信协议,核心特征:

- **Agent Card 发现**:服务端在 `/.well-known/agent-card.json` 提供自描述清单(能力、技能、安全、流式支持)
- **任务(Task)模型**:有状态、可取消、可订阅、可断线重连
- **流式更新**:服务端通过 SSE 持续推送 `Event`
- **Message + Part**:消息由 `TextPart` / `FilePart` / `DataPart` 组成
- **扩展(Extension)**:通过 `X-A2A-Extensions` HTTP 头和 `extensions` 字段声明协议扩展,GenUI 用此机制声明 A2UI

源码依据 `packages/genui_a2a/lib/src/a2a/core/agent_card.dart:17-23`:
```
17  /// A self-describing manifest for an A2A agent.
18  ///
19  /// The [AgentCard] provides essential metadata about an agent, including its
20  /// identity, capabilities, skills, supported communication methods, and
21  /// security requirements. It serves as a primary discovery mechanism for
22  /// clients to understand how to interact with the agent, typically served from
23  /// `/.well-known/agent-card.json`.
```

源码依据 `packages/genui_a2a/lib/src/a2a/client/a2a_client.dart:90`:
```
90    static String get agentCardPath => '/.well-known/agent-card.json';
```

---

## 2. 库结构

文件:`packages/genui_a2a/lib/src/a2a/a2a.dart`(共 28 行)

```
9   export 'client/a2a_client.dart';
10  export 'client/a2a_exception.dart';
11  export 'client/http_transport.dart';
12  export 'client/sse_transport.dart';
13  export 'client/transport.dart';
14  export 'core/agent_capabilities.dart';
15  export 'core/agent_card.dart';
16  export 'core/agent_extension.dart';
17  export 'core/agent_interface.dart';
18  export 'core/agent_provider.dart';
19  export 'core/agent_skill.dart';
20  export 'core/events.dart';
21  export 'core/list_tasks_params.dart';
22  export 'core/list_tasks_result.dart';
23  export 'core/message.dart';
24  export 'core/part.dart';
25  export 'core/push_notification.dart';
26  export 'core/security_scheme.dart';
27  export 'core/task.dart';
```

A2A 子包内部目录:
```
genui_a2a/
  src/
    a2ui_agent_connector.dart     ← 面向 GenUI 的高层封装
    a2a/
      a2a.dart                    ← barrel
      client/
        a2a_client.dart           ← JSON-RPC 2.0 客户端
        a2a_exception.dart        ← 错误码 → 异常
        a2a_handler.dart
        http_transport.dart       ← HTTP 传输
        sse_transport.dart        ← SSE 传输(继承 HttpTransport)
        sse_parser.dart           ← SSE 帧解析
        transport.dart            ← Transport 抽象
      core/
        agent_card.dart
        agent_capabilities.dart
        agent_skill.dart
        agent_provider.dart
        agent_interface.dart
        agent_extension.dart
        security_scheme.dart
        message.dart
        part.dart
        task.dart
        events.dart
        push_notification.dart
        list_tasks_params.dart
        list_tasks_result.dart
```

---

## 3. A2uiAgentConnector — 面向 GenUI 的封装

文件:`packages/genui_a2a/lib/src/a2ui_agent_connector.dart`(共 363 行)

### 3.1 构造时自动注入 A2UI 扩展

源码依据 `a2ui_agent_connector.dart:18-53`:
```
18  final Uri a2uiExtensionUri = Uri.parse(
19    'https://a2ui.org/a2a-extension/a2ui/v0.9',
20  );
21
22  final Logger _log = genui.genUiLogger;
23
24  /// Connects to an A2UI Agent endpoint and streams the A2UI protocol lines.
25  ///
26  /// This class handles the communication with an A2UI agent, including fetching
27  /// the agent card, sending messages, and receiving the A2UI protocol stream.
28  class A2uiAgentConnector {
29    /// Creates a [A2uiAgentConnector] that connects to the given [url].
...
39    A2uiAgentConnector({Uri? url, A2AClient? client, String? contextId})
40      : _contextId = contextId,
41        assert((client == null) != (url == null)) {
42      this.client =
43          client ??
44          A2AClient(
45            url: url.toString(),
46            log: _log,
47            transport: SseTransport(
48              url: url.toString(),
49              log: _log,
50              authHeaders: {'X-A2A-Extensions': a2uiExtensionUri.toString()},
51            ),
52          );
53    }
```

默认使用 `SseTransport`,并设置 `X-A2A-Extensions` HTTP 头,声明客户端支持 A2UI v0.9 扩展。

### 3.2 三个广播流

源码依据 `a2ui_agent_connector.dart:55-77`:
```
55    final _controller = StreamController<genui.A2uiMessage>.broadcast();
56    final _textController = StreamController<String>.broadcast();
57    final _errorController = StreamController<Object>.broadcast();
58    @visibleForTesting
59    late A2AClient client;
60
61    /// The current task ID from the A2A server.
62    @visibleForTesting
63    String? taskId;
64
65    String? _contextId;
66
67    /// The current context ID from the A2A server.
68    String? get contextId => _contextId;
69
70    /// The stream of A2UI messages.
71    Stream<genui.A2uiMessage> get stream => _controller.stream;
72
73    /// The stream of text responses.
74    Stream<String> get textStream => _textController.stream;
75
76    /// A stream of errors from the A2A connection.
77    Stream<Object> get errorStream => _errorController.stream;
```

- `stream` — `Stream<A2uiMessage>`,**GenUI 端直接订阅**
- `textStream` — `Stream<String>`,纯文本(来自 `TextPart`)
- `errorStream` — 错误

### 3.3 connectAndSend — 发送 + 接收全程

源码依据 `a2ui_agent_connector.dart:94-276`:

#### 3.3.1 ChatMessage → Message + Part 映射

```
106        final message = Message(
107          messageId: const Uuid().v4(),
108          role: Role.user,
109          parts: chatMessage.parts.map<Part>((part) {
110            if (part is genui.TextPart) {
111              return Part.text(text: part.text);
112            } else if (part.isUiInteractionPart) {
...
115              try {
116                final Object? json = jsonDecode(uiPart.interaction);
117                if (json is Map<String, Object?>) {
118                  return Part.data(data: json);
119                }
120                return Part.text(text: uiPart.interaction);
...
130            } else if (part is genui.DataPart) {
131              return Part.file(file: FileType.bytes(...));
132            } else if (part is genui.LinkPart) {
133              return Part.file(file: FileType.uri(...));
134            }
135            return const Part.text(text: '');
136          }).toList(),
137        );
```

**关键映射**:
- `TextPart` → `Part.text`
- `UiInteractionPart`(用户 UI 事件)→ `Part.data`(**A2UI 协议的核心反向通道**)
- `UiPart` → `Part.data`(`SurfaceDefinition` JSON)
- `DataPart` → `Part.file`(base64 字节)
- `LinkPart` → `Part.file`(`FileType.uri`)

#### 3.3.2 metadata 注入客户端能力

源码依据 `a2ui_agent_connector.dart:153-162`:
```
153        final metadata = <String, Object?>{};
154        if (clientCapabilities != null) {
155          metadata['a2uiClientCapabilities'] = clientCapabilities.toJson();
156        }
157        if (clientDataModel != null) {
158          metadata['a2uiClientDataModel'] = clientDataModel;
159        }
160        if (metadata.isNotEmpty) {
161          messageToSend = messageToSend.copyWith(metadata: metadata);
162        }
```

**`a2uiClientCapabilities`** 让 server 知道客户端支持哪些 catalog 组件;**`a2uiClientDataModel`** 把 client 端当前数据状态传给 server。

#### 3.3.3 messageStream + 事件处理

源码依据 `a2ui_agent_connector.dart:177-223`:
```
177        final Stream<Event> events = client.messageStream(messageToSend);
178
179        String? responseText;
180        try {
181          Message? finalResponse;
182          await for (final event in events) {
...
188            if (event is TaskStatusUpdate) {
189              taskId = event.taskId;
190              _contextId = event.contextId;
191              final Message? message = event.status.message;
...
207              if (message != null) {
208                finalResponse = message;
...
212                for (final Part part in message.parts) {
213                  if (part is DataPart) {
214                    _processA2uiMessages(part.data);
215                  } else if (part is TextPart) {
216                    final String trimmedText = part.text.trim();
217                    if (trimmedText.isNotEmpty && !_textController.isClosed) {
218                      _textController.add(trimmedText);
219                    }
220                  }
221                }
222              }
223            }
```

**A2UI envelope 从 A2A `DataPart.data` 中提取**(`_processA2uiMessages`,见 3.3.4)。

#### 3.3.4 A2A → A2UI 解析

源码依据 `a2ui_agent_connector.dart:325-346`:
```
325    void _processA2uiMessages(Map<String, Object?> data) {
326      var prettyJson = '(Error sanitizing log data)';
327      try {
328        prettyJson = const JsonEncoder.withIndent(
329          '  ',
330        ).convert(sanitizeLogData(data));
331        _log.finest('Processing a2ui messages from data part:\n$prettyJson');
332      } catch (e) {
333        _log.warning('Error logging a2ui messages: $e');
334      }
335      if (data.containsKey('updateComponents') ||
336          data.containsKey('updateDataModel') ||
337          data.containsKey('createSurface') ||
338          data.containsKey('deleteSurface')) {
339        if (!_controller.isClosed) {
340          _log.finest('Adding message to stream: $prettyJson');
341          _controller.add(genui.A2uiMessage.fromJson(data));
342        }
343      } else {
344        _log.warning('A2A data part did not contain any known A2UI messages.');
345      }
346    }
```

**判定标准**:`data` 包含 `createSurface` / `updateComponents` / `updateDataModel` / `deleteSurface` 任一字段 → 当作 A2UI envelope → 转成 `A2uiMessage` 推到 `stream`。

### 3.4 sendEvent — 客户端事件回传

源码依据 `a2ui_agent_connector.dart:282-323`:
```
282    Future<void> sendEvent(Map<String, Object?> event) async {
283      if (taskId == null) {
284        _log.severe('Cannot send event, no active task ID.');
285        return;
286      }
287
288      final Map<String, Object?> clientEvent = {
289        'version': 'v0.9',
290        'action': {
291          'name': event['action'],
292          'sourceComponentId': event['sourceComponentId'],
293          'timestamp': DateTime.now().toIso8601String(),
294          'context': event['context'],
295          if (event.containsKey('surfaceId')) 'surfaceId': event['surfaceId'],
296        },
297      };
298
299      _log.finest('Sending client event: $clientEvent');
300
301      final dataPart = Part.data(data: clientEvent);
302      final message = Message(
303        role: Role.user,
304        parts: [dataPart],
305        contextId: contextId,
306        referenceTaskIds: [taskId!],
307        messageId: const Uuid().v4(),
308        extensions: [a2uiExtensionUri.toString()],
309        );
310
311      try {
312        final Task response = await client.messageSend(message);
```

**用户点击按钮** → `Surface` 派发 `UserActionEvent` → `SurfaceController.handleUiEvent` → `onSubmit` → 由调用方包成 `ChatMessage + UiInteractionPart` → 传回 `connectAndSend` → 包成 `Part.data` → 通过 `message/send` 单发调用发送。

---

## 4. A2AClient — JSON-RPC 2.0 客户端

文件:`packages/genui_a2a/lib/src/a2a/client/a2a_client.dart`(共 457 行)

### 4.1 构造与默认传输

源码依据 `a2a_client.dart:60-67`:
```
60    final Transport _transport;
61    final Logger? _log;
62
63    int _requestId = 0;
64
65    A2AClient({required this.url, Transport? transport, Logger? log})
66      : _transport = transport ?? SseTransport(url: url, log: log),
67        _log = log;
```

**默认 Transport 是 `SseTransport`**(A2A 的主流用法)。

### 4.2 工厂:从 Agent Card 自动选 Transport

源码依据 `a2a_client.dart:69-88`:
```
69    /// Creates an [A2AClient] by fetching an [AgentCard] and selecting the best
70    /// transport.
71    ///
72    /// Fetches the agent card from [agentCardUrl], determines the best transport
73    /// based on the card's capabilities (preferring streaming if available),
74    /// and returns a new [A2AClient] instance.
75    static Future<A2AClient> fromAgentCardUrl(
76      String agentCardUrl, {
77      Logger? log,
78    }) async {
79      final tempTransport = HttpTransport(url: agentCardUrl, log: log);
80      final Map<String, Object?> response = await tempTransport.get('');
81      final agentCard = AgentCard.fromJson(response);
82
83      final HttpTransport transport = (agentCard.capabilities.streaming ?? false)
84          ? SseTransport(url: agentCard.url, log: log)
85          : HttpTransport(url: agentCard.url, log: log);
86
87      return A2AClient(url: agentCard.url, transport: transport, log: log);
88    }
```

`streaming: true` → 选 `SseTransport`;否则 `HttpTransport`。

### 4.3 RPC 方法集

`a2a_client.dart` 实现了完整的 A2A RPC 方法,每个都是 JSON-RPC 2.0 调用:

| 方法 | 行号 | 用途 |
|---|---|---|
| `getAgentCard` | 100-105 | `GET /.well-known/agent-card.json` |
| `getAuthenticatedExtendedCard` | 115-123 | 带 Bearer token 的扩展 card |
| `messageSend` | 138-163 | `message/send`,同步获取初始 Task |
| `messageStream` | 176-235 | `message/stream`,SSE 长连接 |
| `getTask` | 244-257 | `tasks/get` 轮询 |
| `listTasks` | 266-279 | `tasks/list` |
| `cancelTask` | 289-302 | `tasks/cancel` |
| `resubscribeToTask` | 313-335 | `tasks/resubscribe`,断线重连 |
| `setPushNotificationConfig` | 351-370 | `tasks/pushNotificationConfig/set` |
| `getPushNotificationConfig` | 379-399 | `tasks/pushNotificationConfig/get` |
| `listPushNotificationConfigs` | 407-431 | `tasks/pushNotificationConfig/list` |
| `deletePushNotificationConfig` | 439-456 | `tasks/pushNotificationConfig/delete` |

### 4.4 messageStream 的请求结构

源码依据 `a2a_client.dart:176-199`:
```
176    Stream<Event> messageStream(Message message) {
177      _log?.info('Sending message for stream: ${message.messageId}');
178      final Map<String, Object?> params = {
179        'configuration': null,
180        'metadata': null,
181        'message': message.toJson(),
182      };
183      if (message.extensions != null) {
184        params['extensions'] = message.extensions;
185      }
186      final Map<String, Object> messageMap = {
187        'jsonrpc': '2.0',
188        'method': 'message/stream',
189        'params': params,
190        'id': _requestId++,
191      };
192      final Map<String, String> headers = {};
193      if (message.extensions != null) {
194        headers['X-A2A-Extensions'] = message.extensions!.join(',');
195      }
196      final Stream<Map<String, Object?>> stream = _transport.sendStream(
197        messageMap,
198        headers: headers,
199      );
```

**JSON-RPC 2.0 envelope**: `{jsonrpc: "2.0", method, params, id}`,扩展通过 header `X-A2A-Extensions` 传递。

### 4.5 流转换:`task` 事件 → `StatusUpdate`

源码依据 `a2a_client.dart:200-234`:
```
200      return stream.transform(
201        StreamTransformer.fromHandlers(
202          handleData: (data, sink) {
...
211            if (data.containsKey('error')) {
212              sink.addError(
213                _exceptionFrom(data['error'] as Map<String, Object?>),
214              );
215            } else {
216              if (data['kind'] != null) {
217                if (data['kind'] == 'task') {
218                  final task = Task.fromJson(data);
219                  sink.add(
220                    Event.statusUpdate(
221                      taskId: task.id,
222                      contextId: task.contextId,
223                      status: task.status,
224                      final_: false,
225                    ),
226                  );
227                } else {
228                  sink.add(Event.fromJson(data);
229                }
230              }
231            }
232          },
233        ),
234      );
```

`task` 类型事件被提升为 `Event.statusUpdate` 让上层统一处理。

### 4.6 错误码映射

源码依据 `a2a_client.dart:27-45`:
```
27  A2AException _exceptionFrom(Map<String, Object?> error) {
28    final code = error['code'] as int;
29    final message = error['message'] as String;
30    final data = error['data'] as Map<String, Object?>?;
31
32    return switch (code) {
33      -32001 => A2AException.taskNotFound(message: message, data: data),
34      -32002 => A2AException.taskNotCancelable(message: message, data: data),
35      -32006 => A2AException.pushNotificationNotSupported(...),
36      -32007 => A2AException.pushNotificationConfigNotFound(...),
37      _ => A2AException.jsonRpc(code: code, message: message, data: data),
38    };
39  }
```

A2A 错误码 -32001~ -32007 是预定义;其他走通用 jsonRpc。

---

## 5. HTTP 传输

文件:`packages/genui_a2a/lib/src/a2a/client/http_transport.dart`(共 113 行)

### 5.1 实现 Transport 抽象

源码依据 `http_transport.dart:14-38`:
```
14  /// This transport is suitable for single-shot GET requests and POST requests
15  /// for non-streaming JSON-RPC calls. It does not support [sendStream].
16  class HttpTransport implements Transport {
17    final String url;
18
19    @override
20    final Map<String, String> authHeaders;
21
22    final http.Client client;
23    final Logger? log;
24
25    HttpTransport({
26      required this.url,
27      this.authHeaders = const {},
28      http.Client? client,
29      this.log,
30    }) : client = client ?? http.Client();
31
38  }
```

### 5.2 GET (用于 Agent Card)

源码依据 `http_transport.dart:40-61`:
```
40    @override
41    Future<Map<String, Object?>> get(
42      String path, {
43      Map<String, String> headers = const {},
44    }) async {
45      final Uri uri = Uri.parse('$url$path');
46      final Map<String, String> allHeaders = {...authHeaders, ...headers};
47      log?.fine('Sending GET request to $uri with headers: $allHeaders');
48      try {
49        final http.Response response = await client.get(uri, headers: allHeaders);
50        log?.fine('Received response from GET $uri: ${response.body}');
51        if (response.statusCode >= 400) {
52          throw A2AException.http(
53            statusCode: response.statusCode,
54            reason: response.reasonPhrase,
55          );
56        }
57        return jsonDecode(response.body) as Map<String, Object?>;
58      } on http.ClientException catch (e) {
59        throw A2AException.network(message: e.toString());
60      }
61    }
```

### 5.3 POST(用于非流式 RPC)

源码依据 `http_transport.dart:63-95`:
```
63    @override
64    Future<Map<String, Object?>> send(
65      Map<String, Object?> request, {
66      String path = '',
67      Map<String, String> headers = const {},
68    }) async {
69      final Uri uri = Uri.parse('$url$path');
70      log?.fine('Sending POST request to $uri with body: $request');
71      final Map<String, String> allHeaders = {
72        'Content-Type': 'application/json',
73        ...authHeaders,
74        ...headers,
75      };
76      try {
77        final http.Response response = await client.post(
78          uri,
79          headers: allHeaders,
80          body: jsonEncode(request),
81        );
82        log?.fine('Received response from POST $uri: ${response.body}');
83        if (response.statusCode >= 400) {
84          throw A2AException.http(
85            statusCode: response.statusCode,
86            reason: response.reasonPhrase,
87          );
88        }
89        return jsonDecode(response.body) as Map<String, Object?>;
90      } on http.ClientException catch (e) {
91        throw A2AException.network(message: e.toString());
92      } on FormatException catch (e) {
93        throw A2AException.parsing(message: e.toString());
94      }
95    }
```

### 5.4 显式不支持流式

源码依据 `http_transport.dart:97-107`:
```
97    @override
98    Stream<Map<String, Object?>> sendStream(
99      Map<String, Object?> request, {
100      Map<String, String> headers = const {},
101    }) {
102      throw const A2AException.unsupportedOperation(
103        message:
104            'Streaming is not supported by HttpTransport. Use SseTransport '
105            'instead.',
106      );
107    }
```

---

## 6. SSE 传输

文件:`packages/genui_a2a/lib/src/a2a/client/sse_transport.dart`(共 91 行)

### 6.1 继承 HttpTransport

源码依据 `sse_transport.dart:24-37`:
```
24  class SseTransport extends HttpTransport {
25    /// Creates an [SseTransport] instance.
26    ///
27    /// Inherits parameters from [HttpTransport]:
28    /// - [url]: The base URL of the A2A server.
29    /// - [authHeaders]: Optional additional authorization headers.
30    /// - [client]: Optional [http.Client] for custom configurations or testing.
31    /// - [log]: Optional [Logger] instance.
32    SseTransport({
33      required super.url,
34      super.authHeaders,
35      super.client,
36      super.log,
37    });
```

`get` / `send` / `close` 都继承自父类;只重写 `sendStream`。

### 6.2 sendStream — POST + 读 SSE 流

源码依据 `sse_transport.dart:39-90`:
```
39    @override
40    Stream<Map<String, Object?>> sendStream(
41      Map<String, Object?> request, {
42      Map<String, String> headers = const {},
43    }) async* {
44      final Uri uri = Uri.parse(url);
45      final String body = jsonEncode(request);
46      try {
47        log?.fine(
48          () =>
49              'Sending SSE request to $uri with body: '
50              '${jsonEncode(sanitizeLogData(request))}',
51        );
52      } catch (e) {
53        log?.warning('Error logging SSE request: $e');
54      }
55      final Map<String, String> allHeaders = {
56        'Content-Type': 'application/json',
57        'Accept': 'text/event-stream',
58        ...authHeaders,
59        ...headers,
60      };
61      final httpRequest = http.Request('POST', uri)
62        ..headers.addAll(allHeaders)
63        ..body = body;
64
65      try {
66        final http.StreamedResponse response = await client.send(httpRequest);
67        if (response.statusCode >= 400) {
68          final String responseBody = await response.stream.bytesToString();
69          log?.severe(
70            'Received error response: ${response.statusCode} $responseBody',
71            );
72          throw A2AException.http(
73            statusCode: response.statusCode,
74            reason: '${response.reasonPhrase} $responseBody',
75          );
76        }
77        final Stream<String> lines = response.stream
78            .transform(utf8.decoder)
79            .transform(const LineSplitter());
80        yield* SseParser(log: log).parse(lines);
81      } on http.ClientException catch (e) {
82        throw A2AException.network(message: e.toString());
83      } catch (e) {
84        if (e is A2AException) {
85          rethrow;
86        }
87        // Catch any other unexpected errors during stream processing.
88        throw A2AException.network(message: 'SSE stream error: $e');
89      }
90    }
```

要点:
- **方法仍是 POST**(不是 GET),`Accept: text/event-stream` 告诉服务端走 SSE
- 拿到 `http.StreamedResponse`,用 `utf8.decoder` + `LineSplitter` 拆行
- 把行流喂给 `SseParser`,parser 产生 `Map<String, Object?>` 流

---

## 7. SseParser — SSE 帧解析

文件:`packages/genui_a2a/lib/src/a2a/client/sse_parser.dart`(共 101 行)

### 7.1 状态机

源码依据 `sse_parser.dart:26-67`:
```
26    Stream<Map<String, Object?>> parse(Stream<String> lines) async* {
27      var data = <String>[];
28
29      try {
30        await for (final line in lines) {
31          final String lineData = line.length < 300
32              ? line
33              : line.substring(0, 300);
34          log?.finer('Received SSE line: ${line.length} $lineData...');
35          if (line.startsWith('data:')) {
36            data.add(line.substring(5).trim());
37          } else if (line.startsWith(':')) {
38            // Ignore comments (used for keepalives)
39            log?.finest('Ignoring SSE comment: $line');
40          } else if (line.isEmpty) {
41            // Event boundary
42            if (data.isNotEmpty) {
43              final Map<String, Object?>? result = _parseData(data);
44              data = []; // Clear for next event
45              if (result != null) {
46                yield result;
47              }
48            }
49          } else {
50            log?.warning('Ignoring unexpected SSE line: $line');
51          }
52        }
53
54        if (data.isNotEmpty) {
55          log?.finer(
56            'End of stream reached with ${data.length} lines of data pending.',
57            );
58          final Map<String, Object?>? result = _parseData(data);
59          if (result != null) {
60            yield result;
61          }
62        }
63        // ignore: avoid_catching_errors
64      } on StateError {
65        throw const A2AException.parsing(message: 'Stream closed unexpectedly.');
66      }
67    }
```

帧识别规则:
- `data: ...` → 累积到 `data` 列表(支持多行)
- `: ...` → 注释,丢弃(常用于 keepalive)
- 空行 → 帧边界,合并 `data` 并解析
- 其它 → 警告忽略

### 7.2 JSON-RPC envelope 解析

源码依据 `sse_parser.dart:69-100`:
```
69    Map<String, Object?>? _parseData(List<String> data) {
70      final String dataString = data.join('\n');
71      if (dataString.isNotEmpty) {
72        try {
73          final jsonData = jsonDecode(dataString) as Map<String, Object?>;
...
79          if (jsonData.containsKey('result')) {
80            final Object? result = jsonData['result'];
81            if (result != null) {
82              return result as Map<String, Object?>;
83            } else {
84              log?.warning('Received a null result in the SSE stream.');
85            }
86          } else if (jsonData.containsKey('error')) {
87            final error = jsonData['error'] as Map<String, Object?>;
88            throw A2AException.jsonRpc(
89              code: error['code'] as int,
90              message: error['message'] as String,
91              data: error['data'] as Map<String, Object?>?,
92            );
93            }
94          } catch (e) {
95            if (e is A2AException) rethrow;
96            throw A2AException.parsing(message: e.toString());
97          }
98          }
99      return null;
100     }
```

- JSON-RPC `result` 字段 → 取出来当事件(payload 即 result 内容,不带 JSON-RPC 包装)
- JSON-RPC `error` 字段 → 转 `A2AException.jsonRpc`
- 解析失败 → `A2AException.parsing`

---

## 8. A2A 核心模型

### 8.1 AgentCard(发现清单)

文件:`packages/genui_a2a/lib/src/a2a/core/agent_card.dart`

关键字段(`agent_card.dart:25-127`):
- `protocolVersion`(A2A 协议版本,如 `"0.1.0"`)
- `name` / `description` / `version` / `iconUrl` / `documentationUrl`
- `url` — 主端点
- `preferredTransport` — 主传输协议(`jsonrpc` / `grpc` / `http+json`)
- `additionalInterfaces` — 备用接口
- `capabilities`(`AgentCapabilities`)— `streaming` / `pushNotifications` / `stateTransitionHistory` / `extensions`
- `defaultInputModes` / `defaultOutputModes`(MIME 类型)
- `skills`(`List<AgentSkill>`)— 技能列表
- `securitySchemes` / `security` — OpenAPI 3.0 安全方案
- `supportsAuthenticatedExtendedCard`

发现路径:`/.well-known/agent-card.json`(`a2a_client.dart:90`)。

### 8.2 Task(任务)

文件:`packages/genui_a2a/lib/src/a2a/core/task.dart`

关键字段(`task.dart:20-63`):
- `id` — 任务 ID(server 生成)
- `contextId` — 上下文 ID(多轮对话)
- `status` — `TaskStatus`(`state` + 可选 `message`)
- `history` — 历史 Message
- `artifacts` — 产物
- `metadata` — 扩展元数据
- `lastUpdated` — Unix 毫秒
- `kind` — 类型判别符,固定 `"task"`

`TaskState` 枚举(常见):`submitted` / `working` / `input-required` / `completed` / `failed` / `canceled` / `rejected` / `auth-required` / `unknown`。

### 8.3 Message(消息)

文件:`packages/genui_a2a/lib/src/a2a/core/message.dart`

关键字段(`message.dart:27-75`):
- `role` — `Role.user` / `Role.agent`
- `parts` — `List<Part>`
- `metadata` / `extensions` / `referenceTaskIds`
- `messageId`(UUID)
- `taskId` / `contextId`
- `kind` — 判别符,固定 `"message"`

`Role` 枚举(`message.dart:13-19`):`user` / `agent`。

### 8.4 Part(内容片段)

文件:`packages/genui_a2a/lib/src/a2a/core/part.dart`

三种 part(`part.dart:19-66`):
- `TextPart` — 纯文本
- `FilePart` — 文件(`FileType.bytes` / `FileType.uri`)
- `DataPart` — 结构化 JSON

源码依据 `part.dart:43-62`:
```
43    /// Represents a plain text content part.
44    const factory Part.text({
45      String? kind,
46      required String text,
47      Map<String, Object?>? metadata,
48    }) = TextPart;
49
50    /// Represents a file content part.
51    const factory Part.file({
52      String? kind,
53      required FileType file,
54      Map<String, Object?>? metadata,
55    }) = FilePart;
56
57    /// Represents a structured JSON data content part.
58    const factory Part.data({
59      String? kind,
60      required Map<String, Object?> data,
61      Map<String, Object?>? metadata,
62    }) = DataPart;
```

`A2UI envelope` 主要通过 `DataPart.data` 传递(`a2ui_agent_connector.dart:213-214, 249-250` 都对 `part is DataPart` 走 `_processA2uiMessages(part.data)`)。

### 8.5 Event(流式事件)

文件:`packages/genui_a2a/lib/src/a2a/core/events.dart`

`Event` 是 sealed class,有 3 个子类(`events.dart:18-75`):
- `StatusUpdate` — `kind: "status-update"`,状态变更
- `TaskStatusUpdate` — `kind: "task-status-update"`,流式上下文的 status 更新
- `ArtifactUpdate` — `kind: "artifact-update"`,产物更新(分块、append)

共同字段:`taskId` / `contextId`。

---

## 9. 与 A2UI envelope 的关系

### 9.1 协议分层

```
┌────────────────────────────────────────────────────┐
│  A2UI v0.9 (UI 描述层)                              │
│  envelope = {                                      │
│    "version": "v0.9",                              │
│    "createSurface" | "updateComponents" |          │
│    "updateDataModel" | "deleteSurface": {…}        │
│  }                                                  │
└────────────────────────────────────────────────────┘
                       ▲  DataPart.data 包封
                       │
┌────────────────────────────────────────────────────┐
│  A2A (Agent 通信层,JSON-RPC 2.0 over HTTP/SSE)      │
│  Message {                                          │
│    role, parts: [TextPart | FilePart | DataPart],   │
│    metadata: { a2uiClientCapabilities, … },         │
│    extensions: ["https://a2ui.org/…/v0.9"]         │
│  }                                                  │
│  HTTP header: X-A2A-Extensions: …                   │
└────────────────────────────────────────────────────┘
                       ▲  message/stream (SSE)
                       │
┌────────────────────────────────────────────────────┐
│  Transport 层 (HTTP / SSE)                          │
│  jsonrpc: "2.0", method: "message/stream",          │
│  params: { message: Message, … }, id: N            │
└────────────────────────────────────────────────────┘
```

### 9.2 端到端数据流(verdure example)

源码依据 `examples/verdure/README.md`(存在),具体通信模式:

1. **Client → Server**:`A2uiAgentConnector.connectAndSend(text)`
   - 把 `ChatMessage.user(text)` 包装为 `Message(role: user, parts: [Part.text])`
   - 加上 `extensions: [a2uiExtensionUri]`
   - 加上 `metadata: { a2uiClientCapabilities, a2uiClientDataModel }`(可选)
   - 通过 `A2AClient.messageStream` 发 `message/stream` JSON-RPC

2. **Server → Client**:SSE `data:` 行
   - JSON-RPC 2.0 envelope: `{result: {kind: "task-status-update", taskId, contextId, status: {state, message: {role: agent, parts: [...]}}}}`
   - `SseParser` 抽出 `result` → 流入 `messageStream.transform`
   - 提升为 `StatusUpdate` / `TaskStatusUpdate` 事件
   - `A2uiAgentConnector` 取出 `event.status.message.parts`
     - `DataPart` → 走 `_processA2uiMessages` → `A2uiMessage.fromJson` → `stream` 推
     - `TextPart` → `textStream` 推

3. **Client → Server(用户事件)**:点击按钮后
   - `Surface` 派发 `UserActionEvent`
   - → `SurfaceController.handleUiEvent` → `onSubmit` ChatMessage + `UiInteractionPart`
   - → `A2uiAgentConnector.sendEvent` 或 `connectAndSend`
   - → 包成 `Message(role: user, parts: [Part.data({version: "v0.9", action: {...}})]`
   - → `A2AClient.messageSend` → `message/send` JSON-RPC

### 9.3 metadata 中传递 A2UI 特有信息

源码依据 `a2ui_agent_connector.dart:154-162`:
```
154        if (clientCapabilities != null) {
155          metadata['a2uiClientCapabilities'] = clientCapabilities.toJson();
156        }
157        if (clientDataModel != null) {
158          metadata['a2uiClientDataModel'] = clientDataModel;
159        }
```

这俩键是 **A2A 通用 metadata**,不被 A2A 协议理解,但 A2UI server 知道怎么读。`a2uiClientCapabilities` 告诉 server 客户端支持哪些 catalog 组件,server 据此选择输出;`a2uiClientDataModel` 携带客户端当前数据状态,实现状态回环。

---

## 10. 错误处理 — A2AException

文件:`packages/genui_a2a/lib/src/a2a/client/a2a_exception.dart`(未读全文,但由调用点可见形态)

从 `_exceptionFrom`(`a2a_client.dart:27-45`)看有 6 种:
- `taskNotFound`(码 -32001)
- `taskNotCancelable`(码 -32002)
- `pushNotificationNotSupported`(码 -32006)
- `pushNotificationConfigNotFound`(码 -32007)
- `jsonRpc`(通用)
- `http`(`HttpTransport.sendStream` / `get` 抛,带 statusCode)
- `network`(`http.ClientException` 转)
- `parsing`(JSON 失败)
- `unsupportedOperation`(`HttpTransport.sendStream` 抛)

---

## 11. 总结

`genui_a2a` 是 Flutter 端 **A2A 协议客户端 + A2UI envelope 转换器**:

- **协议**:JSON-RPC 2.0 over HTTP,Agent 发现走 `/.well-known/agent-card.json`,流式响应走 SSE
- **入口**:`A2uiAgentConnector`(`a2ui_agent_connector.dart`)— 构造时自动注入 A2UI extension,提供 `stream: Stream<A2uiMessage>` 给 GenUI 端订阅
- **传输**:`HttpTransport`(GET/POST,不支持流)+ `SseTransport`(继承 Http,重写 `sendStream` 用 `http.Request` POST + `Accept: text/event-stream`)
- **解析**:`SseParser` — 帧边界(空行)+ `data:` 前缀 + JSON-RPC `result`/`error` 解析
- **数据流**:A2A `Message` 的 `DataPart.data` → `_processA2uiMessages` → `A2uiMessage.fromJson` → GenUI `SurfaceController` 消费
- **反向通道**:`UiInteractionPart` → `Part.data` → JSON-RPC `message/send`
- **扩展机制**:`X-A2A-Extensions` HTTP 头 + `Message.extensions` 字段声明 A2UI v0.9 扩展;`metadata.a2uiClientCapabilities` / `a2uiClientDataModel` 携带 UI 能力与数据模型

flutter_genui 整个 A2A 子包本质是 **"在 A2A 之上挂一个 A2UI envelope 透传层"** — A2A 负责通信与任务,A2UI 负责 UI 描述语义。
