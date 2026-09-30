import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

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
    http.Client? httpClient,
  })  : _settings = settings,
        _agent = agent ?? PiAgentEndpoint(config: () => settings.toApiConfig()),
        _sessions = sessions ??
            PiSessionsEndpoint(
              config: () => settings.toApiConfig(),
              client: httpClient, // 测试注入用（默认自建）
            ),
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

  /// ★ 本轮 assistant 气泡的 key（第 15 次复评 P1-1：`send()` 先置
  /// `_sending = true`，再 `await append` —— 这个窗口内 abort 若用
  /// 「最后一条 assistant」定位，会命中**上一轮**已完成的回复并把它标成
  /// 「已停止」（内存+磁盘双污染）。锚点在 append 前就确定，窗口内为 null
  /// 时直接跳过标注）。
  String? _turnAssistantKey;

  /// 订阅是否被**主动取消**（切会话/中止/dispose）。取消会关掉底层 HTTP 流，
  /// 客户端会收到 `Connection closed while receiving data` —— 那是正常副作用，
  /// 不是对话失败，必须静默（用户实测：退出再进入会弹这个异常）。
  bool _subCancelled = false;

  /// pi 服务端 sessionId（null = 尚未建会话）。
  String? get sessionId => _sessionId;

  /// 重命名会话（服务端 rename + 本地标题同步）。
  Future<bool> renameSession(String name) async {
    final sid = _sessionId;
    if (sid == null) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _sessions.rename(sid, trimmed);
      _sessionName = trimmed;
      _notify();
      return true;
    } on PiApiException catch (e) {
      _lastError = '重命名失败: ${e.message}';
      _notify();
      return false;
    }
  }

  // ── 图片输入（复评 P2-8：prompt 的 images 参数此前零 UI）──

  /// 待发送的图片（base64 data，不含前缀；image_picker 的 xfile 转）。
  final List<({String name, String base64})> pendingImages = [];

  /// 是否有待发图片。
  bool get hasPendingImages => pendingImages.isNotEmpty;

  /// 添加图片（调用方负责选择；这里只收 base64）。
  void addImage(String name, String base64) {
    pendingImages.add((name: name, base64: base64));
    _notify();
  }

  /// 移除一张待发图片。
  void removeImage(int index) {
    if (index < 0 || index >= pendingImages.length) return;
    pendingImages.removeAt(index);
    _notify();
  }

  void clearImages() {
    if (pendingImages.isEmpty) return;
    pendingImages.clear();
    _notify();
  }

  /// 主动断流（切会话/中止/dispose 都走这里）：置标记后再 cancel，
  /// 让 onError 能区分「我们主动关的」与「真断流」。
  Future<void> _cancelSub() async {
    final sub = _sub;
    if (sub == null) return;
    _subCancelled = true;
    _sub = null;
    try {
      await sub.cancel();
    } catch (_) {}
  }

  /// 安全通知：dispose 后不再 notify（第 7 次复评探针 D —— prompt POST 在途
  /// 时退出页面会抛 `A PiChatController was used after being disposed`）。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ── 思考档位（复评 P2-8：端点齐备却零接线）──

  String _thinkingLevel = 'off';

  /// 当前思考档位（off/minimal/low/medium/high/xhigh/max）。
  String get thinkingLevel => _thinkingLevel;

  /// 切换思考档位。
  Future<void> setThinkingLevel(String level) async {
    final sid = _sessionId;
    if (sid == null) {
      _thinkingLevel = level;
      _notify();
      return;
    }
    try {
      await _agent.setThinkingLevel(sid, level);
      _thinkingLevel = level;
      _lastError = null;
    } on PiApiException catch (e) {
      _lastError = '切换思考档位失败: ${e.message}';
    }
    _notify();
  }

  /// 上下文占用（percent / tokens / contextWindow；拿不到返回 null）。
  Map<String, dynamic>? get contextUsage => _contextUsage;
  Map<String, dynamic>? _contextUsage;

  /// 拉一次上下文占用（AppBar 副标题显示）。
  /// ★ 真实数据在 `get_state` 的 contextUsage；/sessions/:id/context 返回的
  /// 是消息列表（此前读错端点 → 用量条恒显 0%，第 9 次复评 P1-B）。
  Future<void> refreshContextUsage() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      final st = await _agent.state(sid);
      final cu = st['contextUsage'];
      if (cu is Map<String, dynamic> && !_disposed) {
        _contextUsage = cu;
        _notify();
      }
    } catch (_) {
      // 用量拿不到就算了
    }
  }

  /// 手动清除错误横幅（UI 的关闭按钮）。
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    _notify();
  }

  List<PiChatMessage>? _messagesView;

  /// 当前会话消息（不可变视图，带缓存）。
  ///
  /// 此前每次访问全量 `List.unmodifiable` 拷贝，而 itemBuilder 逐项调用
  /// → 长会话 + 50ms 流式通知节奏下每帧 O(可见行数×n)（复评 P2-1）。
  /// 现在只在消息列表实际变化时重建视图。
  List<PiChatMessage> get messages {
    return _messagesView ??= List.unmodifiable(_messages);
  }

  /// 消息变化时使缓存失效（所有改动点都走这里或直接改后调 _bump）。
  void _bumpMessages() {
    _messagesView = null;
  }

  /// 多段终稿拼接（空行分隔）。独立函数：字符串字面量里的换行转义
  /// 在 heredoc/转义链路上太容易碎。
  static String _joinParts(List<String> parts) =>
      parts.join(String.fromCharCode(10) + String.fromCharCode(10));

  bool get sending => _sending;

  /// ★ 能否中止（AppBar 与 composer **共用这一个谓词**）。
  ///
  /// 第 14 次复评探针 A：两处手写同一谓词必然分叉 —— 建会话窗口
  /// （sending=true 且 sessionId 未定，最长 180s）AppBar 的 stop 图标
  /// 可点但 abort() 静默无效 = 死按钮。单一事实源。
  bool get canAbort => _sending && _sessionId != null;

  /// 是否处于「建会话窗口」（sending 但 sessionId 未定）：UI 显示转圈，
  /// 不显示停止键。
  bool get creatingSession => _sending && _sessionId == null;

  String? get lastError => _lastError;

  /// 配置是否齐全（不齐时 UI 引导设置）。
  bool get canChat => _settings.isConfigured;

  /// 进入一个已有会话（从会话列表点进来 / 重启恢复）。
  Future<void> openSession(String sessionId) async {
    await _repo.init();
    // 切走前把当前会话未完成的气泡标停（否则 Hive 里永久残留「生成中」，
    // 复评 P1：发送中可点「新建会话」泄漏）。user pending 一并清。
    await _stopUnfinishedBubbles(clearUserPending: true);
    await _cancelSub();
    _sessionId = sessionId;
    _messages
      ..clear()
      ..addAll(_repo.messagesOf(sessionId));
    _bumpMessages();
    _sending = false;
    _lastError = null;
    // 跨会话状态重置（复评 P3：A 会话名粘到 B 会话）
    _sessionName = null;
    _currentModelId = null;
    unawaited(_rememberSession(sessionId));
    _notify();
    // 异步取会话名（AppBar 显示「pi · 名字」而非 sessionId 乱码）。
    // 失败静默 —— 标题退化为默认即可，不为它报错。
    unawaited(_loadSessionName(sessionId));
    // 异步拉服务端历史合并（复评三大问题之一：换机/清缓存后本地 Hive
    // 为空，服务端 JSONL 才是完整真相）。不阻塞首屏。
    unawaited(_mergeServerHistory(sessionId));
    // ★ 订阅事件流（复评 #6 连续扣分：此前进入一个服务端正在生成的会话
    // 只能看到冻结快照，且上面的收口还会把活跃气泡误标「已停止」）。
    // 若服务端 isStreaming，把 done=false 的气泡恢复成「生成中」并挂流跟随。
    unawaited(_followIfStreaming(sessionId));
  }

  /// 进入会话时检查服务端是否正在生成；是则恢复未完成气泡并挂流跟随。
  Future<void> _followIfStreaming(String sessionId) async {
    try {
      final st = await _agent.state(sessionId);
      final streaming = st['isStreaming'] == true;
      if (!streaming || _sessionId != sessionId || _disposed) return;

      // ★ 本轮 =「最后一条 user 之后」的 assistant（第 12 次复评探针 F3：
      // 取「最后一条 assistant」在本轮还没有 assistant 时会命中上一轮，
      // 把本轮增量追加到上一轮回答上 —— 答案挂错问题，且助手气泡只剩一条）。
      var lastUserIdx = -1;
      for (var i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].role == 'user') {
          lastUserIdx = i;
          break;
        }
      }
      // 本轮已有的 assistant（在 lastUser 之后）
      PiChatMessage? target;
      for (var i = lastUserIdx + 1; i < _messages.length; i++) {
        if (_messages[i].role == 'assistant') {
          target = _messages[i];
          break;
        }
      }
      String? aKey = target?.key as String?;

      // 本轮还没有 assistant 气泡 → 新起一条（另一台设备发起、或合并只补了
      // 尾部 user 的场景）。
      // ★ 竞态守卫必须在 **append 之前**（第 13 次复评探针 I：此前在
      // append 之后才让位 → 新建的空正文 done=false 气泡落库后无人收口，
      // 内存永久「生成中」、磁盘永久残留，重启变成「已停止」空气泡）。
      if (target == null) {
        if (lastUserIdx < 0) return;
        if (_sending || _sub != null || _sessionId != sessionId || _disposed) {
          return;
        }
        final created = await _repo.append(PiChatMessage(
          sessionId: sessionId,
          role: 'assistant',
          text: '',
          done: false,
        ));
        // ★ append 是 await：窗口内用户可能已 send()。二次守卫触发时
        // **回滚刚落库的气泡**（第 14 次复评探针 I 同型：不回滚则磁盘
        // 留下 done=false 孤儿 → 重启变「已停止」空气泡）。
        if (_sending || _sub != null || _sessionId != sessionId || _disposed) {
          final ghost = _repo.getByKey(created);
          if (ghost != null) await ghost.delete();
          return;
        }
        aKey = created;
        final fresh = _repo.getByKey(created);
        if (fresh == null) return;
        target = fresh;
        _messages.add(fresh);
        _bumpMessages();
      }

      // ★ 竞态守卫（第 11 次复评探针 R1）：state() 是个未受保护的窗口，
      // 用户在此窗口内 send() 的话，继续挂流会掐掉 send 的订阅并覆盖句柄
      // （实测：事件流开 2 份、正文重复叠加）。本轮已开始就让位。
      if (_sending || _sub != null || _sessionId != sessionId || _disposed) {
        return;
      }

      // 已完成且未停止 → 这不是「正在跑的那一轮」，不复活（复评 #4）
      if (target.done && !target.stopped) return;

      // 恢复本轮气泡为生成中
      if (target.done && target.stopped) {
        target
          ..done = false
          ..stopped = false;
        await target.save();
      }
      _bumpMessages();
      _sending = true;
      _notify();

      // 挂流跟随（与 send 的流处理同一套收口语义）
      String? uKey;
      for (final m in _messages.reversed) {
        if (m.role == 'user' && m.key != null) {
          uKey = m.key as String;
          break;
        }
      }
      final aKey2 = aKey;
      if (aKey2 == null) return;
      final assistantMsg = _repo.getByKey(aKey2);
      if (assistantMsg == null) return;

      final buf = StringBuffer(assistantMsg.text);
      var sawTurnEnd = false;
      final finalParts = <String>[];
      var finalLocked = false;
      // 重建流（上一轮已收口后订阅已被取消）：先断旧再挂新，并复位取消标记
      await _sub?.cancel();
      _subCancelled = false;
      _sub = _agent.events(sessionId).listen((e) {
        if (e.isAssistantDelta && !finalLocked) {
          buf.write(e.textDelta);
          assistantMsg.text = buf.toString();
          _notify();
        }
        if (e.type == 'message_end' && e.role == 'assistant' && e.text != null) {
          finalParts.add(e.text!);
          finalLocked = true;
          assistantMsg
            ..text = _joinParts(finalParts)
            ..done = true;
          _notify();
        }
        if (e.isToolEvent) {
          final name = e.toolName ?? '工具';
          final line = '正在调用 $name…';
          assistantMsg.toolActivity = line;
          _notify();
        }
        if (e.isTurnEnd) {
          sawTurnEnd = true;
          final settled =
              finalLocked ? _joinParts(finalParts) : buf.toString();
          assistantMsg
            ..text = settled
            ..done = true;
          // 回调非 async：fire-and-forget 落库。
          // ★ 用户气泡只清 pending，**绝不改正文**（第 11 次复评探针 F2：
          // 此前写 '' 把用户原话清成空串，内存+磁盘双丢，成功主路径上的
          // 破坏性数据丢失）。repo.markUserDelivered 只清标志不动 text。
          final String ak = aKey2;
          final String uk = uKey ?? '';
          if (ak.isNotEmpty) _repo.updateText(ak, settled, done: true);
          if (uk.isNotEmpty) _repo.markUserDelivered(uk);
          _sending = false;
          unawaited(_cancelSub());
          _notify();
        }
      }, onError: (Object err) {
        if (_subCancelled || _disposed) return;
        if (!assistantMsg.done) {
          assistantMsg
            ..error = err is PiApiException ? err.message : '$err'
            ..done = true;
        }
        _sending = false;
        _notify();
      }, onDone: () async {
        if (!assistantMsg.done) {
          assistantMsg
            ..text = buf.toString()
            ..done = true
            ..stopped = !sawTurnEnd;
          await assistantMsg.save();
        }
        _sending = false;
        _notify();
      });
    } catch (_) {
      // 跟随失败不影响已展示的快照
    }
  }

  /// 从服务端回读会话历史并合并进本地（缺的补上，不覆盖本地已有的）。
  Future<void> _mergeServerHistory(String sessionId) async {
    try {
      final detail = await _sessions.detail(sessionId);
      // 真实结构（线上实测）：context 是 Map —— {messages: [...], entryIds, ...}，
      // 消息数组在 context['messages'] 里。此前按 List 解析 → 永远空跑。
      final rawContext = detail['context'];
      final List? context =
          rawContext is Map ? rawContext['messages'] as List? : rawContext as List?;
      if (context == null || context.isEmpty) return;
      // ★ 只补尾部，但切分基准必须是**可落库的有效条目数**而不是原始长度：
      // 服务端 context 里含 tool/空文本条目时它们不会落库，用原始长度切分会
      // 造成「本地数 < 有效数」恒成立 → 每次进会话重复追加尾部
      //（第 8 次复评探针 A 实测：'第二答' 被重复追加）。
      bool hasText(dynamic entry) {
        if (entry is! Map) return false;
        final r = entry['role']?.toString();
        if (r != 'user' && r != 'assistant') return false;
        final c = entry['content'];
        if (c is String) return c.trim().isNotEmpty;
        if (c is List) {
          for (final b in c) {
            if (b is Map && b['type'] == 'text' &&
                (b['text']?.toString().trim().isNotEmpty ?? false)) {
              return true;
            }
          }
        }
        return false;
      }

      final validContext = context.where(hasText).toList();
      if (validContext.isEmpty) return;
      final localCount = _repo.messagesOf(sessionId).length;
      if (validContext.length <= localCount) return; // 本地不比服务端少
      final pending = validContext.sublist(localCount);
      final existing = <PiChatMessage>{};
      var added = 0;
      for (final entry in pending) {
        if (entry is! Map) continue;
        final role = entry['role']?.toString();
        if (role != 'user' && role != 'assistant') continue;
        final text = () {
          final c = entry['content'];
          if (c is String) return c;
          if (c is List) {
            final buf = StringBuffer();
            for (final block in c) {
              if (block is Map && block['type'] == 'text') {
                buf.write(block['text']?.toString() ?? '');
              }
            }
            return buf.toString();
          }
          return '';
        }();
        if (text.trim().isEmpty) continue;
        final msg = PiChatMessage(
          sessionId: sessionId,
          role: role!,
          text: text,
          done: true,
        );
        // 只补尾部已保证幂等；不再按文本查重（会吞掉用户重复提问的合法轮次）
        if (existing.contains(msg)) continue;
        await _repo.append(msg);
        added++;
      }
      if (added > 0 && _sessionId == sessionId && !_disposed) {
        // 刷新内存视图（用户正看着这个会话）
        _messages
          ..clear()
          ..addAll(_repo.messagesOf(sessionId));
        _bumpMessages();
        _notify();
      }
    } catch (_) {
      // 历史合并失败不影响本地已展示的内容
    }
  }

  Future<void> _loadSessionName(String sessionId) async {
    try {
      // 顺手同步当前模型 + 思考档位 + 上下文用量（第 9/10 次复评：
      // 这三样全在同一个 state() 响应里，此前只读了 model；
      // 档位不回填 → 菜单单选永远显示本地 off，对服务端撒谎）
      try {
        final st = await _agent.state(sessionId);
        final model = st['model'];
        if (model is Map && !_disposed) {
          final p = model['provider']?.toString();
          final m = model['modelId']?.toString();
          if (p != null && m != null && m != 'unknown') {
            _currentModelId = '$p/$m';
          }
        }
        final tl = st['thinkingLevel']?.toString();
        if (tl != null && tl.isNotEmpty && !_disposed) {
          _thinkingLevel = tl;
        }
        final cu = st['contextUsage'];
        if (cu is Map<String, dynamic> && !_disposed) {
          _contextUsage = cu;
        }
      } catch (_) {
        // 模型态拿不到就算了
      }
      final detail = await _sessions.detail(sessionId);
      final name = detail['info'] is Map
          ? (detail['info']['name']?.toString() ?? '')
          : (detail['name']?.toString() ?? '');
      if (name.isNotEmpty && _sessionId == sessionId && !_disposed) {
        _sessionName = name;
        _notify();
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

  /// 切换模型（AppBar 模型选择器）。
  Future<void> switchModel(String qualifiedId) async {
    final sid = _sessionId;
    if (sid == null) {
      // 还没会话：把选择记成默认模型，建会话时生效
      await _settings.setDefaultModel(qualifiedId);
      _notify();
      return;
    }
    final i = qualifiedId.indexOf('/');
    if (i <= 0) {
      _lastError = '模型格式应为 provider/modelId：$qualifiedId';
      _notify();
      return;
    }
    try {
      await _agent.command(
        sid,
        {'type': 'set_model', 'provider': qualifiedId.substring(0, i),
         'modelId': qualifiedId.substring(i + 1)},
      );
      await _settings.setDefaultModel(qualifiedId);
      // 同步选中态（探针 D：不写这里，弹层再开时永远滞后一拍）
      _currentModelId = qualifiedId;
      _lastError = null;
    } on PiApiException catch (e) {
      _lastError = '切换模型失败: ${e.message}';
    }
    _notify();
  }

  /// 当前模型（服务端状态里取；未知返回 null）。
  String? get currentModelId => _currentModelId;
  String? _currentModelId;

  /// 把 sessionId 记进配置（「继续上次对话」的数据源）。
  /// 此前只有列表页写它 —— 聊天页内新建/进入会话后断链（复评 #6）。
  Future<void> _rememberSession(String? id) async {
    await _settings.setLastSessionId(id ?? '');
  }

  bool _creating = false;

  /// 正在创建会话（UI 据此禁用按钮 —— 请求最长 180s，无防重入会点出 N 个会话，
  /// 复评 #14）。
  bool get creating => _creating;

  /// 新建一个 pi 会话（ensure_session，不耗额度）并切换过去。
  Future<void> newSession({String? model}) async {
    final cfg = _settings;
    if (!cfg.isConfigured) {
      _lastError = '未配置：请先在设置里填写服务地址与 device token';
      _notify();
      return;
    }
    // controller 层互斥（第 5 次复评前置 3：不能只靠 UI 禁用）——
    // creating 期间快速发送可并发开出第二个会话，随后 openSession
    // 整体替换 _messages 把用户刚发的气泡冲掉。
    if (_creating || _sending) return;
    _creating = true;
    _notify();
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
      _notify();
    } finally {
      _creating = false;
      _notify();
    }
  }

  /// 发送一条用户消息（乐观落库 → prompt → 流式收 assistant）。
  ///
  /// [reuseUserMessage] 为 true 时不落新 user 气泡（重发场景：
  /// 原气泡已在历史里，追加会造成重复）。
  /// 发送一条用户消息。返回 **true = 已被受理**（进入流式）；
  /// false = 未被受理（未配置/忙/建会话失败），调用方应把文本回填输入框，
  /// 否则用户输入会被永久吞掉（第 8 次复评 P2 实锤：建会话失败时文本既不
  /// 落库也不在输入框，无重发载体）。
  Future<bool> send(String text,
      {bool reuseUserMessage = false, List<Object>? images}) async {
    final trimmed = text.trim();
    // creating 期间同样拒绝（controller 层互斥，不依赖 UI 禁用）
    if (trimmed.isEmpty || _sending || _creating) return false;
    if (!_settings.isConfigured) {
      _lastError = '未配置：请先在设置里填写服务地址与 device token';
      _notify();
      return false;
    }
    _lastError = null;
    _sending = true;
    _notify();

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
          // 会话前选的思考档位在这里生效（第 9 次复评前置 3：此前静默丢失）
          thinkingLevel: _thinkingLevel == 'off' ? null : _thinkingLevel,
        ))
            .sessionId;
        unawaited(_rememberSession(_sessionId));
      }
      final sid = _sessionId!;

      // 2) 乐观落库用户消息（重发场景复用已有气泡的真实 key）
      if (reuseUserMessage) {
        PiChatMessage? existing;
        for (final m in _messages.reversed) {
          if (m.role == 'user' && m.text == trimmed) {
            existing = m;
            break;
          }
        }
        // 找不到匹配的 user 气泡就走正常追加（绝不能 orElse 抓 assistant 气泡
        // 来覆写 —— 第 5 次复评 #15 雷区）。key 用 HiveObject 绑定的真实 key。
        if (existing != null && existing.key != null) {
          userKey = existing.key as String;
          existing
            ..pending = true
            ..done = false;
          await existing.save();
        }
      }
      if (userKey == null) {
        final imgCount = images?.length ?? 0;
        userKey = await _repo.append(PiChatMessage(
          sessionId: sid,
          role: 'user',
          text: trimmed,
          pending: true,
          // 图片回显元数据（复评 #6：发出的图此前不回显，记录里找不到）
          imageCount: imgCount,
          // 首图缩略**不再落 base64**（一张 1600px 图 300KB+，会把消息体积
          // 炸掉）；回显用 imageCount 的文字行 —— 数据真实体积为零，
          // downscale 缩略等需要时再加（第 13 次复评前置 4 的最终取舍）。
          firstImageThumb: '',
        ));
        _messages.add(_repo.getByKey(userKey)!);
      _bumpMessages();
      }
      _notify();

      // 3) 建立事件流（服务端会回显用户消息；助手增量在 message_update）
      final assistant = PiChatMessage(
        sessionId: sid,
        role: 'assistant',
        text: '',
        done: false,
        model: _settings.defaultModel.isEmpty ? null : _settings.defaultModel,
      );
      assistantKey = await _repo.append(assistant);
      _turnAssistantKey = assistantKey; // 本轮锚点（append 成功即确定）
      final assistantMsg = _repo.getByKey(assistantKey)!;
      _messages.add(assistantMsg);
      _bumpMessages();
      _notify();

      final buf = StringBuffer();
      var sawTurnEnd = false;
      // 本轮工具活动（渲染成气泡内的工具行）
      final toolLines = <String>[];
      // message_end 的完整正文（权威终稿）；锁定后 agent_end/onDone 不得用
      // delta 累积覆盖（第 8 次复评探针 B）
      // ★ 工具循环会产生多段 assistant 消息（第 10 次复评探针 M：前言+正文
      // 都在），finalText 按段用空行拼接而不是覆盖；finalLocked 只在
      // turnEnd 落锁（此后 buf 的 delta 不再进正文）。
      final finalParts = <String>[];
      var finalLocked = false;
      String finalTextOf() =>
          finalParts.join('\n\n');
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
          // ★ message_end 之后任何写路径只允许写 finalText（第 9 次复评
          // 探针 A：flush 回调不检查 finalLocked，50ms 定时器把终稿覆盖成
          // delta 残句 —— 中止/断流轮次用户把截断文本当完整答案）。
          if (finalLocked) return;
          await _repo.updateText(aKey, buf.toString());
          assistantMsg.text = buf.toString();
          if (!_disposed) notifyListeners();
        });
      }
      // 重建流（新一轮）：复位取消标记，避免新流的错误被静默
      await _sub?.cancel();
      _subCancelled = false;
      _sub = _agent.events(sid).listen(
        (e) {
          // 工具活动：agent 干活的核心过程，此前完全丢弃（复评 #6 最大缺口）
          if (e.isToolEvent) {
            final name = e.toolName ?? '工具';
            final detail = e.toolDetail == null
                ? ''
                : ' · ${e.toolDetail}';
            final line = e.toolPhase == 'start'
                ? '正在调用 $name$detail'
                : '$name$detail';
            // 按 toolCallId 归类（一次调用一行；update 时替换 start 那条）——
            // 此前按整行去重：同工具不同参数调用 6 次出 11 行等宽小字卡片
            // （第 15 次复评 P1-2：长任务下卡片会顶爆气泡）。
            if (e.toolCallId != null) {
              final tag = 'tool#${e.toolCallId}';
              toolLines.removeWhere((l) => l.startsWith('$tag\t'));
              toolLines.add('$tag\t$line');
            } else if (!toolLines.contains(line)) {
              toolLines.add(line);
            }
            // 折叠：保留前 4 行 + 「…等 N 步」
            final visible = toolLines.length > 4
                ? '${toolLines.take(4).join('\n')}\n…等 ${toolLines.length - 4} 步'
                : toolLines.join('\n');
            assistantMsg.toolActivity = visible;
            _notify();
          }
          if (e.isAssistantDelta) {
            buf.write(e.textDelta);
            scheduleFlush();
          }
          if (e.type == 'message_end' && e.role == 'assistant' && e.text != null) {
            // 终稿：服务端给的完整正文是权威（delta 可能丢帧）。
            // ★ 记入 finalText 并锁定，agent_end 不得再用 delta 累积覆盖它
            //（第 8 次复评探针 B：终稿被覆盖成只剩增量的残句）。
            if (e.text!.trim().isNotEmpty) finalParts.add(e.text!);
            // 监听回调非 async：fire-and-forget 落库（内存立即更新）
            _repo.updateText(aKey, finalTextOf(), done: true);
            assistantMsg
              ..text = finalTextOf()
              ..done = true;
            _notify();
          }
          if (e.isTurnEnd) {
            sawTurnEnd = true;
            // ★ 成功轮次在这里收口（复评 P0-1）：pi-web 的 SSE 是长连+心跳
            //（30s 注释帧），agent_end 后流**不断开** → onDone 永不触发。
            // 若只靠 onDone，生产环境每轮成功回复后发送按钮永久转圈、
            // user 气泡永久「发送中」。空回复（纯工具调用轮）也置 done。
            // 终稿已锁定时用它（探针 B：不得被 delta 累积覆盖成残句）
            if (finalParts.isNotEmpty) finalLocked = true;
            final settledText = finalLocked ? finalTextOf() : buf.toString();
            buf
              ..clear()
              ..write(settledText);
            _repo.updateText(aKey, settledText, done: true);
            assistantMsg
              ..text = settledText
              ..done = true;
            // 无条件清 pending（第 4 次复评：回显帧不保证有，成功主路径
            // 不该带门 —— isError/onDone 都无条件，唯独这里带门不是完整收口）
            _repo.updateText(uKey, trimmed, done: true);
            _sending = false;
            // turnEnd 收口即断订阅：长连还在收心跳，若之后断流触发 onError，
            // 会把已成功的回复毒化成「失败+重发」（第 10 次复评探针 E）。
            // 下一轮 send() 会重新建流。回调非 async → unawaited。
            unawaited(_cancelSub());
            _notify();
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
            _notify();
          }
        },
        onError: (Object err) async {
          // 主动取消（切会话/中止/退出）导致的 Connection closed 是正常副作用，
          // 静默处理 —— 此前会把用户吓一跳（实测报错）。
          if (_subCancelled || _disposed) return;
          final detail = err is PiApiException ? err.message : '$err';
          // 本轮已收口（turnEnd 已到）的气泡不再毒化 —— 长连断流不是内容失败
          if (!assistantMsg.done) {
            _repo.markError(aKey, detail);
            assistantMsg
              ..error = detail
              ..done = true;
          }

          // user 气泡同样要收口：断流时清 pending，否则 meta 行永远「发送中」，
          // 且与旁边的「失败+重发」并存成矛盾态（复评 #3）。
          try {
            await _repo.updateText(uKey, trimmed, done: true);
          } catch (_) {}
          _lastError = detail;
          _sending = false;
          _notify();
        },
        onDone: () async {
          if (finalParts.isNotEmpty) finalLocked = true;
          final settled = finalLocked ? finalTextOf() : buf.toString();
          assistantMsg
            ..text = settled
            ..done = true;
          // ★ 未见 turn_end 就断流 = 半截回复，不能伪装成完整答案
          //（第 7 次复评探针 E：一个 delta 后流干净关闭，用户把半截当完整）。
          if (!sawTurnEnd) assistantMsg.stopped = true;
          await assistantMsg.save();
          await _repo.updateText(uKey, trimmed, done: true);
          _sending = false;
          _notify();
        },
      );

      // 4) 发送 prompt（受理即返回；正文走上面的流；带图则在受理后清空）
      await _agent.prompt(sid, trimmed, images: images);
      clearImages();
      _notify();
      return true;
    } on PiApiException catch (e) {
      _lastError = e.isUnauthorized
          ? 'token 无效或已吊销，请到设置检查'
          : e.isThrottled
              ? '请求过于频繁，请稍后再试'
              : '发送失败: ${e.message}';
      await _finalizeFailedTurn(userKey: userKey, assistantKey: assistantKey,
          userText: trimmed, errorMessage: _lastError!);
      _sending = false;
      _notify();
      return false;
    } catch (e) {
      _lastError = '发送失败: $e';
      await _finalizeFailedTurn(userKey: userKey, assistantKey: assistantKey,
          userText: trimmed, errorMessage: _lastError!);
      _sending = false;
      _notify();
      return false;
    }
  }

  /// 把当前会话未完成的 assistant 气泡标记为「已停止」并落库。
  /// dispose / abort / openSession 三处共用。
  Future<void> _stopUnfinishedBubbles({bool clearUserPending = true}) async {
    for (final m in _messages) {
      if (m.role == 'assistant' && !m.done) {
        m
          ..done = true
          ..stopped = true; // 停止状态独立字段，不伪造正文（复评 P2）
        // ★ 必须用消息自身的 save()（HiveObject 绑定的真实 key sid#seq）。
        // 此前用 sessionId 当 key 调 repo.updateText → miss 静默 return
        // → 内存干净、磁盘照旧，重启后「生成中」复活（第 5 次复评 P1 探针实锤）。
        await m.save();
      }
      if (clearUserPending && m.role == 'user' && m.pending) {
        m.pending = false;
        await m.save();
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
      await _finalizeAbort();
    } on PiApiException catch (e) {
      // 中止请求失败也必须复位 sending —— 否则发送按钮永久禁用（复评 P1）。
      _lastError = '中止失败: ${e.message}';
      await _cancelSub();
      await _finalizeAbort();
      _sending = false;
      _notify();
    }
  }

  /// 中止的本地收口（成功/失败两路共用，第 9 次复评：手抄两份必然分叉）。
  Future<void> _finalizeAbort() async {
    // 走统一入口：置 _subCancelled 后取消，让 onError 把随后的
    // Connection closed 当正常副作用静默掉（用户实测报错）。
    await _cancelSub();
    // ★ 只认**本轮锚点**（第 15 次复评 P1-1）：`_currentAssistant()` 取
    // 「最后一条 assistant」，在 send 落气泡窗口内会命中上一轮 —— 把它
    // 标成「已停止」（第 11 次 A2b 的真回归）。锚点在 append 前确定，
    // 窗口内为 null 时本轮还没有内容可标，直接跳过。
    final key = _turnAssistantKey;
    if (key != null) {
      final current = _repo.getByKey(key);
      if (current != null && current.done && !current.stopped &&
          current.text.isNotEmpty) {
        current.stopped = true;
        await current.save();
      }
    }
    await _stopUnfinishedBubbles(clearUserPending: true);
    _sending = false;
    _notify();
  }

// 注：曾用「最后一条 assistant」定位本轮 —— 在 send 落气泡窗口内会命中
// 上一轮（第 15 次复评 P1-1 回归）。现改用 _turnAssistantKey 锚点。

  /// 清空本地记录（不影响服务端会话）。
  Future<void> clearLocal() async {
    final sid = _sessionId;
    if (sid != null) await _repo.clearSession(sid);
    _messages.clear();
    _bumpMessages();
    _notify();
  }

  /// 删除服务端会话 + 本地记录。
  Future<void> deleteSession() async {
    final sid = _sessionId;
    if (sid == null) return;
    try {
      await _sessions.delete(sid);
    } on PiApiException catch (e) {
      _lastError = '删除会话失败: ${e.message}';
      _notify();
      return;
    }
    await _repo.clearSession(sid);
    _messages.clear();
    _bumpMessages();
    _sessionId = null;
    _notify();
  }

  /// 重发最后一条用户消息（失败气泡的「重发」按钮）。
  ///
  /// 实现：把最后一条 user 消息的文本重新走一遍 [send]，并把失败的那条
  /// assistant 气泡从本地移除（避免界面上留下一条无用的错误气泡）。
  Future<void> retryLast({PiChatMessage? failedMessage}) async {
    if (_sending) return;
    // 定位：优先用调用方给的那条失败气泡（第 7 次复评探针 G：多失败轮次时
    // 不带身份会重发错内容 —— 点第一条失败气泡实际重发第二条）。
    // ★ 用稳定 id 定位（第 8 次复评 P1 根因：两条空正文失败气泡 == 相等，
    // indexOf 恒定命中第一条 → 重发错内容）。id 由模型生成，必然唯一。
    PiChatMessage? failedAssistant = failedMessage;
    var fIdx = failedAssistant != null
        ? _messages.indexWhere((m) => m.id == failedAssistant!.id)
        : -1;
    if (fIdx < 0) {
      fIdx = _messages.lastIndexWhere(
          (m) => m.role == 'assistant' && m.error != null);
      failedAssistant = fIdx >= 0 ? _messages[fIdx] : null;
    }
    String? lastUserText;
    if (failedAssistant != null && fIdx >= 0) {
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
      final idx = _messages.indexWhere((m) => m.id == failedAssistant!.id);
      if (idx >= 0) _messages.removeAt(idx);
      _bumpMessages();
      // 精确删除这一条（此前删「最后一条错误」—— 多失败轮次下删错，
      // 被点的气泡永远清不掉，第 7 次复评探针 G）
      await failedAssistant.delete();
      _notify();
    }
    // 复用原 user 气泡重发（此前 send() 会追加一条一模一样的 user 气泡，
    // 历史出现两条重复 —— 复评 #4）。
    await send(lastUserText, reuseUserMessage: true);
  }

  /// 确保基础设施已初始化（main.dart 启动期也可调）。
  Future<void> ensureInit() async {
    await HiveStore.instance.init();
    await _repo.init();
  }

  @override
  void dispose() {
    _disposed = true;
    _subCancelled = true;
    _sub?.cancel();
    // 与 _stopUnfinishedBubbles 同一份收口（此前手抄了一份只管 assistant 的
    // 内联循环 —— 两份逻辑必然分叉，user pending 就是从那个缝隙漏掉的，
    // 第 6 次复评探针 C 实锤）。fire-and-forget：dispose 不能 await。
    _stopUnfinishedBubbles(clearUserPending: true).catchError((_) {});
    super.dispose();
  }
}
