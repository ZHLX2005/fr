/// pi 后端（nx-as 网关）API。
///
/// 手机端经 nx-as 的 `/m/v1/*` 通道调用 pi-web，鉴权用 device token。
/// 目录：
/// - `agent/`    — 新建会话、命令通道、SSE 事件流
/// - `sessions/` — 会话列表、详情、状态、改名、删除
/// - `models/`   — 模型清单（**必须带 cwd**）
///
/// 使用方式：
/// ```dart
/// final cfg = PiConfig(baseUrl: 'http://47.110.80.47:18080', token: 'nxas_d1...');
/// final agent = PiAgentEndpoint(config: () => cfg);
/// final created = await agent.newSession(cwd: '/data');
/// agent.events(created.sessionId).listen((e) { /* 流式渲染 */ });
/// ```
library;

export 'pi_config.dart';
export 'pi_exception.dart';
export 'agent/pi_agent_endpoint.dart';
export 'agent/pi_sse_event.dart';
export 'sessions/pi_sessions_endpoint.dart';
export 'models/pi_models_endpoint.dart';
