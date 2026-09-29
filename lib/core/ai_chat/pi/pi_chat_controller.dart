import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../api/pi/pi.dart';
import '../../storage/hive/hive_store.dart';
import 'pi_chat_message.dart';
import 'pi_chat_message_repository.dart';
import 'pi_chat_settings.dart';

/// pi 聊天控制器：一条会话的完整生命周期（ChangeNotifier）。
///
/// 职责：
/// - 从 [PiChatMessageRepository] 回读历史（Hive）
/// - 发消息（乐观 UI → prompt → SSE 流式 → 终稿落库）
/// - 中止 / 新建会话 / 切换模型（经 [PiAgentEndpoint]）
///
/// 配置来自 [PiChatSettings]（SharedPreferences）；未配置时 [canChat] 为
/// false，UI 引导去设置页。
class PiChatController extends ChangeNotifier {
  PiChatController({
    required PiChatSettings settings,
    PiAgentEndpoint? agent,
    PiSessionsEndpoint? sessions,
    PiChatMessageRepository? repository,
  })  : _settings = settings,
        _agent = agent ?? PiAgentEndpoint(config: () => settings.toApiConfig()),
        _sessions = sessions ??
            PiSessionsEndpoint(config: () => settings.toApiConfig()),
        _repo = repository ?? piChatMessageRepository;

  final PiChatSettings _settings;
  final PiAgentEndpoint _agent;
  final PiSessionsEndpoint _sessions;
  final PiChatMessageRepository _repo;

  String? _sessionId;
  final List<PiChatMessage> _messages = [];
  StreamSubscription<PiSseEvent>? _sub;
  bool _sending = false;
  String? _lastError;
  bool _disposed = false;

  /// pi 服务端 sessionId（null = 尚未建会话）。
  String? get sessionId => _sessionId;

  /// 手动清除错误横幅（UI 的关闭按钮）。
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// 当前会话消息（不可变视图）。
  List<PiChatMessage> get messages => List.unmodifiable(_messages);

  bool get sending => _sending;

  String? get lastError => _lastError;

  /// 配置是否齐全（不齐时 UI 引导设置）。
  bool get canChat => _settings.isConfigured;

  /// 流式进行中的助手消息（UI 用于打字指示）。
  PiChatMessage? get streamingMessage {
    for (final m in _messages.reversed) {
      if (m.role == 'assistant' && !m.done) return m;
    }
    return null;
  }

  /// 进入一个已有会话（从会话列表点进来 / 重启恢复）。
  Future<void> openSession(String sessionId) async {
    await _repo.init();
    // 切走前把当前会话未完成的气泡标停（否则 Hive 里永久残留「生成中」，
    // 复评 P1：发送中可点「新建会话」泄漏）。
    await _stopUnfinishedBubbles();
    _sub?.cancel();
    _sub = null;
    _sessionId = sessionId;
    _messages
      ..clear()
      ..addAll(_repo.messagesOf(sessionId));
    _sending = false;
    _lastError = null;
    notifyListeners();
    // 异步取会话名（AppBar 显示「pi · 名字」而非 sessionId 乱码）。
    // 失败静默 —— 标题退化为默认即可，不为它报错。
    unawaited(_loadSessionName(sessionId));
  }

  Future<void> _loadSessionName(String sessionId) async {
    try {
      final detail = await _sessions.detail(sessionId);
      final name = detail['info'] is Map
          ? (detail['info']['name']?.toString() ?? '')
          : (detail['name']?.toString() ?? '');
      if (name.isNotEmpty && _sessionId == sessionId && !_disposed) {
        _sessionName = name;
        notifyListeners();
      }
    } catch (_) {
      // 标题拿不到就算了
    }
  }

  String? _sessionName;

  /// 会话显示名（服务端 name；空则 UI 退化为默认标题）。
  String? get sessionName => _sessionName;

  /// 仅测试用：跳过网络建会话，直接注入 sessionId（状态机单测用）。
  void overrideSessionIdForTest(String sessionId) {
    _sessionId = sessionId;
  }

  /// 新建一个 pi 会话（ensure_session，不耗额度）并切换过去。
  Future<void> newSession({String? model}) async {
    final cfg = _settings;
    if (!cfg.isConfigured) {
      _lastError = '未配置：请先在设置里填写服务地址与 device token';
      notifyListeners();
      return;
    }
    String? provider;
    String? modelId;
    if (model != null && model.contains('/')) {
      final i = model.indexOf('/');
      provider = model.substring(0, i);
      modelId = model.substring(i + 1);
    }
    try {
      final created = await _agent.newSession(
        cwd: cfg.cwd,
        provider: provider,
        modelId: modelId,
      );
      await openSession(created.sessionId);
    } on PiApiException catch (e) {
      _lastError = '新建会话失败: ${e.message}';
      notifyListeners();
    }
  }

  /// 发送一条用户消息（乐观落库 → prompt → 流式收 assistant）。
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    if (!_settings.isConfigured) {
      _lastError = '未配置：请先在设置里填写服务地址与 device token';
      notifyListeners();
      return;
    }
    _lastError = null;
    _sending = true;
    notifyListeners();

    // 落库 key 提到 try 外：catch 里收口失败气泡要用（异常可能发生在任意一步）
    String? userKey;
    String? assistantKey;
    try {
      // 1) 无会话则先建（首条消息场景）。
      // 设置里的「默认模型」（provider/modelId）在这里**真正生效**——
      // 此前它只被写进消息字段，从未传给服务端（评分 #20：死配置）。
      if (_sessionId == null) {
        String? provider;
        String? modelId;
        final dm = _settings.defaultModel;
        if (dm.contains('/')) {
          final i = dm.indexOf('/');
          provider = dm.substring(0, i);
          modelId = dm.substring(i + 1);
        }
        _sessionId = (await _agent.newSession(
          cwd: _settings.cwd,
          provider: provider,
          modelId: modelId,
        ))
            .sessionId;
      }
      final sid = _sessionId!;

      // 2) 乐观落库用户消息
      userKey = await _repo.append(PiChatMessage(
        sessionId: sid,
        role: 'user',
        text: trimmed,
        pending: true,
      ));
      _messages.add(_repo.getByKey(userKey)!);
      notifyListeners();

      // 3) 建立事件流（服务端会回显用户消息；助手增量在 message_update）
      final assistant = PiChatMessage(
        sessionId: sid,
        role: 'assistant',
        text: '',
        done: false,
        model: _settings.defaultModel.isEmpty ? null : _settings.defaultModel,
      );
      assistantKey = await _repo.append(assistant);
      final assistantMsg = _repo.getByKey(assistantKey)!;
      _messages.add(assistantMsg);
      notifyListeners();

      final buf = StringBuffer();
      var userEchoed = false;
      // 到这里 userKey/assistantKey 必然已赋值（落库成功才会走到）；
      // 局部拷贝成非空给 SSE 回调用。
      final String uKey = userKey;
      final String aKey = assistantKey;
      // 流式节流：每个 delta 都写 Hive+notify 会造成每秒几十次磁盘 IO 与
      // 整页 rebuild（复评 #4：真机掉帧点）。delta 先进 buffer，
      // 50ms 定时批量落盘+通知一次。
      var pendingFlush = false;
      void scheduleFlush() {
        if (pendingFlush) return;
        pendingFlush = true;
        Future<void>.delayed(const Duration(milliseconds: 50), () async {
          pendingFlush = false;
          await _repo.updateText(aKey, buf.toString());
          assistantMsg.text = buf.toString();
          if (!_disposed) notifyListeners();
        });
      }
      await _sub?.cancel();
      _sub = _agent.events(sid).listen(
        (e) {
          if (e.role == 'user') userEchoed = true;
          if (e.isAssistantDelta) {
            buf.write(e.textDelta);
            scheduleFlush();
          }
          if (e.type == 'message_end' && e.role == 'assistant' && e.text != null) {
            // 终稿覆盖（防丢增量）
            _repo.updateText(aKey, e.text!, done: true);
            assistantMsg
              ..text = e.text!
              ..done = true;
            notifyListeners();
          }
          if (e.isTurnEnd) {
            // ★ 成功轮次在这里收口（复评 P0-1）：pi-web 的 SSE 是长连+心跳
            //（30s 注释帧），agent_end 后流**不断开** → onDone 永不触发。
            // 若只靠 onDone，生产环境每轮成功回复后发送按钮永久转圈、
            // user 气泡永久「发送中」。空回复（纯工具调用轮）也置 done。
            _repo.updateText(aKey, buf.toString(), done: true);
            assistantMsg
              ..text = buf.toString()
              ..done = true;
            if (userEchoed) {
              _repo.updateText(uKey, trimmed, done: true);
            }
            _sending = false;
            notifyListeners();
          }
          if (e.isError) {
            // 错误 = 这一轮结束（prompt_error 后服务端不再产出），完整收口：
            // assistant 标错误可重发、user 清 pending、sending 复位。
            // （此前只标 assistant —— user 永挂「发送中」，复评 P1 缝隙）
            final msg = e.raw['errorMessage']?.toString() ?? '对话出错';
            _repo.markError(aKey, msg);
            assistantMsg
              ..error = msg
              ..done = true;
            _repo.updateText(uKey, trimmed, done: true);
            _sending = false;
            notifyListeners();
          }
        },
        onError: (Object err) async {
          final detail = err is PiApiException ? err.message : '$err';
          _repo.markError(aKey, detail);
          assistantMsg
            ..error = detail
            ..done = true;
          // user 气泡同样要收口：断流时清 pending，否则 meta 行永远「发送中」，
          // 且与旁边的「失败+重发」并存成矛盾态（复评 #3）。
          try {
            await _repo.updateText(uKey, trimmed, done: true);
          } catch (_) {}
          _lastError = detail;
          _sending = false;
          notifyListeners();
        },
        onDone: () async {
          await _repo.updateText(aKey, buf.toString(), done: true);
          assistantMsg
            ..text = buf.toString()
            ..done = true;
          // 无条件清 pending：能走到流结束，说明 prompt 已被受理；
          // 回显帧只是锦上添花（有些错误路径没有回显），不该卡「发送中」。
          await _repo.updateText(uKey, trimmed, done: true);
          _sending = false;
          notifyListeners();
        },
      );

      // 4) 发送 prompt（受理即返回；正文走上面的流）
      await _agent.prompt(sid, trimmed);
      notifyListeners();
    } on PiApiException catch (e) {
      _lastError = e.isUnauthorized
          ? 'token 无效或已吊销，请到设置检查'
          : e.isThrottled
              ? '请求过于频繁，请稍后再试'
              : '发送失败: ${e.message}';
      await _finalizeFailedTurn(userKey: userKey, assistantKey: assistantKey,
          userText: trimmed, errorMessage: _lastError!);
      _sending = false;
      notifyListeners();
    } catch (e) {
      _lastError = '发送失败: $e';
      await _finalizeFailedTurn(userKey: userKey, assistantKey: assistantKey,
          userText: trimmed, errorMessage: _lastError!);
      _sending = false;
      notifyListeners();
    }
  }

  /// 把当前会话未完成的 assistant 气泡标记为「已停止」并落库。
  /// dispose / abort / openSession 三处共用。
  Future<void> _stopUnfinishedBubbles({bool clearUserPending = false}) async {
    for (final m in _messages) {
      if (m.role == 'assistant' && !m.done) {
        m
          ..done = true
          ..text = m.text.isEmpty ? '（已停止）' : m.text;
        await _repo.updateText(m.sessionId, m.text, done: true);
      }
      if (clearUserPending && m.role == 'user' && m.pending) {
        m.pending = false;
        await _repo.updateText(m.sessionId, m.text, done: true);
      }
    }
  }

  /// 失败轮次的收口（单一出口）：用户气泡标记「未送达」，assistant 气泡
  /// 标记失败并给「重发」入口。否则两条气泡会永久停在「发送中/生成中」，
  /// 界面在对用户撒谎（评分 #13/#14）。
  ///
  /// 注意 userKey/assistantKey 可能为 null —— 异常可能发生在落库之前。
  Future<void> _finalizeFailedTurn({
    String? userKey,
    String? assistantKey,
    required String userText,
    required String errorMessage,
  }) async {
    try {
      if (assistantKey != null) {
        await _repo.markError(assistantKey, errorMessage);
        final m = _repo.getByKey(assistantKey);
        if (m != null) {
          m
            ..error = errorMessage
            ..done = true;
        }
      }
      if (userKey != null) {
        // 送达失败：清 pending（UI 显示「失败」状态行）
        await _repo.updateText(userKey, userText, done: true);
      }
    } catch (_) {
      // 收口失败不能掩盖原始错误
    }
  }

  /// 中止当前运行。
  Future<void> abort() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await _agent.abort(sid);
      // 本地同步收口：不等服务端 agent_end（若该流不结束，
      // 中止按钮永不消失、发送按钮永久禁用 —— 复评 #8）。
      await _sub?.cancel();
      _sub = null;
      await _stopUnfinishedBubbles(clearUserPending: true);
      _sending = false;
      notifyListeners();
    } on PiApiException catch (e) {
      // 中止请求失败也必须复位 sending —— 否则发送按钮永久禁用（复评 P1）。
      _lastError = '中止失败: ${e.message}';
      await _sub?.cancel();
      _sub = null;
      await _stopUnfinishedBubbles(clearUserPending: true);
      _sending = false;
      notifyListeners();
    }
  }

  /// 清空本地记录（不影响服务端会话）。
  Future<void> clearLocal() async {
    final sid = _sessionId;
    if (sid != null) await _repo.clearSession(sid);
    _messages.clear();
    notifyListeners();
  }

  /// 删除服务端会话 + 本地记录。
  Future<void> deleteSession() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await _sessions.delete(sid);
    } on PiApiException catch (e) {
      _lastError = '删除会话失败: ${e.message}';
      notifyListeners();
      return;
    }
    await _repo.clearSession(sid);
    _messages.clear();
    _sessionId = null;
    notifyListeners();
  }

  /// 重发最后一条用户消息（失败气泡的「重发」按钮）。
  ///
  /// 实现：把最后一条 user 消息的文本重新走一遍 [send]，并把失败的那条
  /// assistant 气泡从本地移除（避免界面上留下一条无用的错误气泡）。
  Future<void> retryLast() async {
    if (_sending) return;
    // 找**最后一条失败的 assistant**，再取它**前面最近一条** user——
    // 否则历史中间的失败气泡点重发会发错内容（复评 #10）。
    PiChatMessage? failedAssistant;
    final fIdx = _messages.lastIndexWhere(
        (m) => m.role == 'assistant' && m.error != null);
    if (fIdx >= 0) failedAssistant = _messages[fIdx];
    String? lastUserText;
    if (failedAssistant != null) {
      for (var i = fIdx - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.role == 'user' && m.text.isNotEmpty) {
          lastUserText = m.text;
          break;
        }
      }
    } else {
      // 没有失败气泡（横幅重试场景）：退化为最后一条 user
      for (final m in _messages.reversed) {
        if (m.role == 'user' && m.text.isNotEmpty) {
          lastUserText = m.text;
          break;
        }
      }
    }
    if (lastUserText == null) return;
    if (failedAssistant != null) {
      final idx = _messages.indexOf(failedAssistant);
      if (idx >= 0) _messages.removeAt(idx);
      await _repo.removeLastErrorOf(failedAssistant.sessionId);
      notifyListeners();
    }
    await send(lastUserText);
  }

  /// 确保基础设施已初始化（main.dart 启动期也可调）。
  Future<void> ensureInit() async {
    await HiveStore.instance.init();
    await _repo.init();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    // 页面销毁时若有未完成的 assistant 气泡，标记为「已停止」——
    // 否则重启后（从 Hive 回读）它永远显示「生成中」+ 闪烁光标。
    for (final m in _messages) {
      if (m.role == 'assistant' && !m.done) {
        m.done = true;
        if (m.text.isEmpty) {
          m.text = '（已停止）';
        }
        // 直接落库（dispose 里不能等异步）
        _repo.updateText(m.sessionId, m.text, done: true).catchError((_) {});
      }
    }
    super.dispose();
  }
}
