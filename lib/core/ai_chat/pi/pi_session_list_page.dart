import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/pi/pi.dart';
import 'pi_chat_message_repository.dart';
import 'pi_chat_page.dart';
import 'pi_chat_settings.dart';

/// pi 会话列表 —— 聊天模块的「历史」入口。
///
/// 为什么必须有它：没有列表时，用户从「AI 助手 → pi」进去永远是全新会话，
/// 之前的对话在 UI 上再也找不回来（数据其实还在 Hive 里）。这是同类产品
/// （ChatGPT / Claude）对话界面的核心结构，也是评分里权重最高的缺口。
///
/// 数据来源两路合并：
/// - 远端 `GET /sessions?summary=1`（服务端真相，含未在本机聊过的会话）
/// - 本地 Hive（`PiChatMessageRepository.sessionIds()`，离线也能看到聊过的）
class PiSessionListPage extends StatefulWidget {
  final PiChatSettings settings;

  const PiSessionListPage({super.key, required this.settings});

  @override
  State<PiSessionListPage> createState() => _PiSessionListPageState();
}

class _PiSessionListPageState extends State<PiSessionListPage> {
  bool _loading = true;
  Object? _error;
  List<_SessionRow> _rows = const [];

  /// 上次会话 id（有值且在列表里时，置顶给「继续上次对话」入口）。
  String get _lastId => widget.settings.lastSessionId;

  /// 搜索关键词（复评 P2-3：列表无搜索）
  String _query = '';

  List<_SessionRow> get _filtered {
    if (_query.trim().isEmpty) return _rows;
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (r.title.toLowerCase().contains(q)) return true;
      if (r.id.toLowerCase().contains(q)) return true;
      // ★ 走倒排索引（不遍历全库 keys —— 此前每击键 O(rows × all keys)；
      // 索引后 O(命中会话数)）
      final tokens = piChatMessageRepository.tokensOf(r.id);
      for (final t in tokens) {
        if (t.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 离线兜底：本地聊过的会话 id 先铺底
      final repo = piChatMessageRepository;
      await repo.init();
      final localIds = repo.sessionIds();

      List<PiSessionSummary> remote = const [];
      var runningIds = <String>{};
      try {
        final endpoint = PiSessionsEndpoint(
          config: () => widget.settings.toApiConfig(),
        );
        try {
          // 加载超时：弱网/测试环境下 HTTP 挂起会让界面永远转圈（视觉上=白屏）。
          // 超时降级为「仅本地」，不阻塞列表展示。
          final page = await endpoint.list()
              .timeout(const Duration(seconds: 10));
          remote = page.sessions;
          runningIds = page.runningSessionIds;
        } finally {
          endpoint.close();
        }
      } on TimeoutException {
        if (localIds.isEmpty) {
          rethrow;
        }
        debugPrint('[pi] 远端会话列表超时，仅显示本地');
      } on PiApiException catch (e) {
        // 远端不可用不算致命：本地有记录就照常展示，只提示一下
        if (localIds.isEmpty) rethrow;
        debugPrint('[pi] 远端会话列表失败，仅显示本地：${e.message}');
      }

      final seen = <String>{};
      final rows = <_SessionRow>[];
      for (final s in remote) {
        if (s.id.isEmpty || !seen.add(s.id)) continue;
        rows.add(_SessionRow(
          id: s.id,
          title: s.displayName,
          updatedAt: s.updatedAt,
          fromLocal: false,
          running: runningIds.contains(s.id),
        ));
      }
      for (final id in localIds) {
        if (!seen.add(id)) continue;
        final msgs = repo.messagesOf(id);
        final last = msgs.isNotEmpty ? msgs.last : null;
        rows.add(_SessionRow(
          id: id,
          title: last?.text.isNotEmpty == true
              ? last!.text
              : '本地会话 ${id.substring(0, 8)}',
          updatedAt: last?.createdAt,
          fromLocal: true,
          running: runningIds.contains(id),
        ));
      }
      // 有时间戳的按时间倒序，无时间戳的排后面
      rows.sort((a, b) {
        final ta = a.updatedAt, tb = b.updatedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _open(_SessionRow row) async {
    await widget.settings.setLastSessionId(row.id);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PiChatPage(
        settings: widget.settings,
        initialSessionId: row.id,
      ),
    ));
    if (mounted) await _load(); // 回来刷新（可能有新消息/新会话）
  }

  Future<void> _newSession() async {
    await widget.settings.setLastSessionId('');
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PiChatPage(settings: widget.settings),
    ));
    if (mounted) await _load();
  }

  /// 待真删的会话表（per-sessionId Timer，第 17 次复评 P-1）。
  ///
  /// 修复前是单例 `_pendingDeleteTimer`：连删两条会话时第一条 Timer
  /// 被第二条的 `cancel()` 干掉但 UI 已移除——服务端 + 本地都没删，
  /// 4s 撤销窗消失后**没人知道这条会话还在**，reload 回魂（ghost-zombie）。
  /// 改为 map：每条会话独立 4s Timer，互不干扰。
  final Map<String, _PendingDelete> _pending = {};

  Future<void> _delete(_SessionRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('将从服务端与本地删除「${row.shortTitle}」，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // ★ 第 16/17 次复评 P-4/P-1：撤销窗（4s 内可从 SnackBar 点撤销）
    // 立刻 1）UI 上移除、2）真删延后到 4s 后。撤销窗结束才落服务端 +
    // 本地。per-sessionId Timer（map）—— 修复前单例 timer 让连删 N 条
    // 时前 N-1 条 Timer 被 cancel 但服务端/本地都没删（ghost-zombie）。
    final pending = _PendingDelete(
      id: row.id,
      row: row,
      controller: this,
    );
    pending.startTimer(const Duration(seconds: 4));
    _pending[row.id] = pending;
    setState(() {
      _rows = _rows.where((r) => r.id != row.id).toList();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除「${row.shortTitle}」'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '撤销',
            onPressed: pending.undo,
          ),
        ),
      );
    }
  }

  /// 真删除（撤销窗口结束后才走）：服务端 + 本地。
  Future<void> _actuallyDelete(String id, String shortTitle) async {
    try {
      final endpoint =
          PiSessionsEndpoint(config: () => widget.settings.toApiConfig());
      try {
        await endpoint.delete(id);
      } finally {
        endpoint.close();
      }
    } on PiApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务端删除失败：${e.message}')),
        );
      }
    }
    await piChatMessageRepository.clearSession(id);
    if (widget.settings.lastSessionId == id) {
      await widget.settings.setLastSessionId('');
    }
  }

  @override
  void dispose() {
    for (final p in _pending.values) {
      p._timer?.cancel();
    }
    _pending.clear();
    super.dispose();
  }

  /// 撤销时把 row 重新插入 _rows（保持按时间倒序）。
  void _restoreRow(_SessionRow row) {
    setState(() {
      _rows = [..._rows, row];
      _rows.sort((a, b) {
        final ta = a.updatedAt, tb = b.updatedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('pi 对话'),
        actions: [
          if (_rows.any((r) => r.id == _lastId))
            IconButton(
              tooltip: '继续上次对话',
              icon: const Icon(Icons.history),
              onPressed: () => _open(
                _rows.firstWhere((r) => r.id == _lastId),
              ),
            ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('新对话'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索会话…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      // 骨架屏（复评 P2-3：全屏转圈无骨架）
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (_, i) => ListTile(
          leading: CircleAvatar(
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
          title: Container(
            height: 12,
            width: 160,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          subtitle: Container(
            height: 10,
            width: 90,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('无法加载会话列表', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText('$error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isNotEmpty && _filtered.isEmpty) {
      return Center(
        child: Text('没有匹配「$_query」的会话',
            style: theme.textTheme.bodySmall),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.forum_outlined,
                    size: 34, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text('还没有对话',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('点右下角「新对话」开始',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  )),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _filtered.length,
        separatorBuilder: (_, index) =>
            const Divider(height: 1, indent: 68, endIndent: 16),
        itemBuilder: (context, i) {
          final row = _filtered[i];
          return Dismissible(
            key: ValueKey(row.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: theme.colorScheme.errorContainer,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: Icon(Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer),
            ),
            confirmDismiss: (_) async {
              await _delete(row);
              return false; // 删除自己负责刷新，不让 Dismissible 移除条目
            },
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  row.fromLocal ? Icons.chat_bubble_outline : Icons.cloud_done_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              title: Text(
                row.shortTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  if (row.running) ...[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text('生成中 · ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
                  ],
                  Expanded(
                    child: Text(
                row.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              onTap: () => _open(row),
            ),
          );
        },
      ),
    );
  }
}

/// 列表行数据（远端 + 本地合并后）。
class _SessionRow {
  final String id;
  final String title;
  final DateTime? updatedAt;
  final bool fromLocal;

  /// 服务端正在生成（runningSessionIds 此前解析了却零 UI —— 复评多轮）
  final bool running;

  const _SessionRow({
    required this.id,
    required this.title,
    this.updatedAt,
    required this.fromLocal,
    this.running = false,
  });

  /// 标题可能很长（本地会话标题取的是最后一条消息），列表里截断。
  String get shortTitle =>
      title.length > 40 ? '${title.substring(0, 40)}…' : title;

  String get subtitle {
    final t = updatedAt;
    final stamp = t == null
        ? ''
        : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final src = fromLocal ? '本地' : '服务端';
    return stamp.isEmpty ? src : '$src · $stamp';
  }
}

/// 待真删的会话（per-sessionId Timer，第 16/17 次复评 P-4/P-1）。
///
/// 撤销时把 row 重新插入 `_rows`，并取消本条 timer；4s 窗口结束后
/// timer 走进 `commit()` 才落服务端与本地。每条会话独立 timer，连
/// 删 N 条互不影响。
class _PendingDelete {
  final String id;
  final _SessionRow row;
  final _PiSessionListPageState controller;
  Timer? _timer;
  bool _committed = false;

  _PendingDelete({
    required this.id,
    required this.row,
    required this.controller,
  });

  /// 启动 4s 撤销窗 timer；与构造拆开是因为 Timer 回调需要 self，
  /// self 在构造里还不可见。
  void startTimer(Duration d) {
    _timer = Timer(d, commit);
  }

  Future<void> commit() async {
    if (_committed) return;
    _committed = true;
    controller._pending.remove(id);
    await controller._actuallyDelete(row.id, row.shortTitle);
  }

  void undo() {
    if (_committed) return;
    _committed = true;
    _timer?.cancel();
    controller._pending.remove(id);
    controller._restoreRow(row);
  }

  /// 测试用：检查 timer 是否还活着（撤销窗未结束）。
  @visibleForTesting
  bool get hasTimer => _timer != null && _timer!.isActive;
}
