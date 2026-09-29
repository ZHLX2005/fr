/// SSE 事件流里的一条帧（pi-web 的 `/agent/:id/events`）。
///
/// 帧结构（真机实测）：
/// ```
/// {"type":"connected","sessionId":"...","isStreaming":false}
/// {"type":"message_start","message":{"role":"user","content":[...]}}
/// {"type":"message_start","message":{"role":"assistant",...}}
/// {"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"2"}}
/// {"type":"message_update","assistantMessageEvent":{"type":"text_end","content":"2"}}
/// {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"2"}]}}
/// {"type":"agent_end"}
/// ```
///
/// ⚠️ `message_start`/`message_end` **会同时回显用户消息**，必须靠 [role] 区分方向；
/// 助手增量只在 `message_update.assistantMessageEvent` 里。
class PiSseEvent {
  /// 事件类型：connected / message_start / message_update / message_end /
  /// agent_start / agent_end / agent_settled / prompt_done / prompt_error 等。
  final String type;

  /// 该帧的消息角色（user / assistant），仅 message_start/message_end 有。
  final String? role;

  /// 助手文本增量（仅 message_update 的 text_delta 有）。
  final String? textDelta;

  /// 完整文本（message_end 或 text_end 时可用）。
  final String? text;

  /// 原始解析后的 JSON，便于上层取用未建模字段。
  final Map<String, dynamic> raw;

  const PiSseEvent({
    required this.type,
    this.role,
    this.textDelta,
    this.text,
    this.raw = const {},
  });

  /// 是否为助手侧的流式增量。
  bool get isAssistantDelta => type == 'message_update' && textDelta != null;

  /// 是否为「本轮结束」信号。
  bool get isTurnEnd =>
      type == 'agent_end' || type == 'agent_settled' || type == 'prompt_done';

  /// 本轮出错。
  bool get isError => type == 'prompt_error' || type == 'error';

  /// 从解码后的 JSON 构造（兼容 `{data:{...}}` / `{event:{...}}` 包裹形态）。
  static PiSseEvent? fromJson(Object? decoded) {
    Map<String, dynamic> map;
    if (decoded is Map<String, dynamic>) {
      map = decoded;
    } else {
      return null;
    }
    if (!map.containsKey('type')) {
      for (final key in const ['event', 'data']) {
        final inner = map[key];
        if (inner is Map<String, dynamic> && inner.containsKey('type')) {
          map = inner;
          break;
        }
      }
    }
    final type = map['type'];
    if (type is! String) return null;

    String? role;
    String? text;
    final msg = map['message'];
    if (msg is Map<String, dynamic>) {
      final r = msg['role'];
      if (r is String) role = r;
      text = _textOf(msg['content']);
    }

    String? delta;
    final ame = map['assistantMessageEvent'];
    if (ame is Map<String, dynamic>) {
      final d = ame['delta'];
      if (d is String) delta = d;
      final endContent = ame['content'];
      if (text == null && endContent is String) text = endContent;
    }
    // 兜底：少数形态把增量直接放在顶层
    if (delta == null) {
      final d = map['delta'];
      if (d is String) delta = d;
    }

    return PiSseEvent(
      type: type,
      role: role,
      textDelta: delta,
      text: text,
      raw: map,
    );
  }

  /// content 既可能是字符串，也可能是 `[{type:'text',text:'...'}]`。
  static String? _textOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          final t = block['text'];
          if (t is String) buf.write(t);
        }
      }
      return buf.isEmpty ? null : buf.toString();
    }
    return null;
  }

  @override
  String toString() {
    final parts = <String>['type=$type'];
    if (role != null) parts.add('role=$role');
    if (textDelta != null) parts.add('delta=${jsonPreview(textDelta!)}');
    if (text != null) parts.add('text=${jsonPreview(text!)}');
    return 'PiSseEvent(${parts.join(', ')})';
  }

  static String jsonPreview(String s, [int max = 40]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
