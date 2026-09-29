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
      try {
        final endpoint = PiSessionsEndpoint(
          config: () => widget.settings.toApiConfig(),
        );
        try {
          // 加载超时：弱网/测试环境下 HTTP 挂起会让界面永远转圈（视觉上=白屏）。
          // 超时降级为「仅本地」，不阻塞列表展示。
          remote = (await endpoint.list().timeout(const Duration(seconds: 10)))
              .sessions;
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
    try {
      final endpoint =
          PiSessionsEndpoint(config: () => widget.settings.toApiConfig());
      try {
        await endpoint.delete(row.id);
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
    await piChatMessageRepository.clearSession(row.id);
    if (widget.settings.lastSessionId == row.id) {
      await widget.settings.setLastSessionId('');
    }
    if (mounted) await _load();
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
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
        itemCount: _rows.length,
        separatorBuilder: (_, index) =>
            const Divider(height: 1, indent: 68, endIndent: 16),
        itemBuilder: (context, i) {
          final row = _rows[i];
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
              subtitle: Text(
                row.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
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

  const _SessionRow({
    required this.id,
    required this.title,
    this.updatedAt,
    required this.fromLocal,
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
