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

  /// pi 服务端 sessionId（null = 尚未建会话）。
  String? get sessionId => _sessionId;

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
    _sub?.cancel();
    _sessionId = sessionId;
    _messages
      ..clear()
      ..addAll(_repo.messagesOf(sessionId));
    _lastError = null;
    notifyListeners();
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

    try {
      // 1) 无会话则先建（首条消息场景）
      _sessionId ??= (await _agent.newSession(cwd: _settings.cwd)).sessionId;
      final sid = _sessionId!;

      // 2) 乐观落库用户消息
      final userKey = await _repo.append(PiChatMessage(
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
      final assistantKey = await _repo.append(assistant);
      final assistantMsg = _repo.getByKey(assistantKey)!;
      _messages.add(assistantMsg);
      notifyListeners();

      final buf = StringBuffer();
      var userEchoed = false;
      await _sub?.cancel();
      _sub = _agent.events(sid).listen(
        (e) {
          if (e.role == 'user') userEchoed = true;
          if (e.isAssistantDelta) {
            buf.write(e.textDelta);
            _repo.updateText(assistantKey, buf.toString());
            notifyListeners();
          }
          if (e.type == 'message_end' && e.role == 'assistant' && e.text != null) {
            // 终稿覆盖（防丢增量）
            _repo.updateText(assistantKey, e.text!, done: true);
            assistantMsg
              ..text = e.text!
              ..done = true;
            notifyListeners();
          }
          if (e.isTurnEnd && buf.isNotEmpty) {
            _repo.updateText(assistantKey, buf.toString(), done: true);
            assistantMsg
              ..text = buf.toString()
              ..done = true;
            notifyListeners();
          }
          if (e.isError) {
            final msg = e.raw['errorMessage']?.toString() ?? '对话出错';
            _repo.markError(assistantKey, msg);
            assistantMsg
              ..error = msg
              ..done = true;
            notifyListeners();
          }
        },
        onError: (Object err) {
          final detail = err is PiApiException ? err.message : '$err';
          _repo.markError(assistantKey, detail);
          assistantMsg
            ..error = detail
            ..done = true;
          _lastError = detail;
          _sending = false;
          notifyListeners();
        },
        onDone: () async {
          await _repo.updateText(assistantKey, buf.toString(), done: true);
          assistantMsg
            ..text = buf.toString()
            ..done = true;
          // 用户回执：服务端回显了用户消息，清除 pending
          if (userEchoed) await _repo.updateText(userKey, trimmed);
          _sending = false;
          notifyListeners();
        },
      );

      // 4) 发送 prompt（受理即返回；正文走上面的流）
      await _agent.prompt(sid, trimmed);
      notifyListeners();
    } on PiApiException catch (e) {
      _lastError = e.isUnauthorized
          ? 'token 无效或已吊销'
          : e.isThrottled
              ? '请求过于频繁，请稍后再试'
              : '发送失败: ${e.message}';
      _sending = false;
      notifyListeners();
    } catch (e) {
      _lastError = '发送失败: $e';
      _sending = false;
      notifyListeners();
    }
  }

  /// 中止当前运行。
  Future<void> abort() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await _agent.abort(sid);
    } on PiApiException catch (e) {
      _lastError = '中止失败: ${e.message}';
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
    // 找最后一条 user 文本
    String? lastUserText;
    PiChatMessage? failedAssistant;
    for (final m in _messages.reversed) {
      if (lastUserText == null && m.role == 'user' && m.text.isNotEmpty) {
        lastUserText = m.text;
      }
      if (lastUserText != null && m.role == 'assistant' && m.error != null) {
        failedAssistant = m;
        break;
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
    _sub?.cancel();
    super.dispose();
  }
}
