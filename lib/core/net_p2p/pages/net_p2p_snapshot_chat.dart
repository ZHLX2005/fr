// lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart
//
// 快照驱动的聊天页（v3 RelayV3Transport）
//
// 整个页面只渲染一个 Snapshot 对象：
// - snapshot.context['messages'] → 聊天消息列表（业务自定义字段）
// - snapshot.state → 房间状态（waiting / playing / ended）
// 任何 WS 推送触发 snapshot 替换，UI 自动重绘。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 快照驱动的聊天页面（v3）
class NetP2PSnapshotChatPage extends StatefulWidget {
  const NetP2PSnapshotChatPage({
    super.key,
    required this.handle,
    this.onLeave,
  });

  final RoomHandle handle;
  final VoidCallback? onLeave;

  @override
  State<NetP2PSnapshotChatPage> createState() => _NetP2PSnapshotChatPageState();
}

class _NetP2PSnapshotChatPageState extends State<NetP2PSnapshotChatPage> {
  final _input = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.handle.latest;
    // Lobby widget already called connect() before handing us the handle.
    // RoomHandle.connect() is idempotent, so this is safe either way.
    widget.handle.connect();
    _sub = widget.handle.snapshots.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollCtrl.dispose();
    _sub?.cancel();
    // leave() will call handle.dispose(); if user navigates away without
    // leaving first, leave() was never called and we must dispose here.
    // RoomHandle.dispose() is idempotent so a double call from leave() + this
    // dispose() path is safe.
    widget.handle.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _extractMessages() {
    final snap = _snapshot;
    if (snap == null) return const [];
    final raw = snap.context['messages'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      await widget.handle.applyAction(
        type: 'CHAT',
        params: {'text': text, 'alias': widget.handle.transport.alias},
      );
    } on RelayV3Exception catch (e) {
      // CAS mismatch (409) or Lua/validation error (422) etc.
      // Spec §8 originally embedded the current snapshot in a 409 body, but
      // the backend's ApplyAction controller stopped doing so — clients must
      // refetch to reconcile.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: ${e.statusCode} ${e.body}')),
      );
      if (e.statusCode == 409) {
        try {
          await widget.handle.transport.fetchSnapshot(widget.handle.code);
        } catch (_) {
          // Best-effort refetch; WS will reconcile on next push anyway.
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    if (snap == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('加载中…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final msgs = _extractMessages();

    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${snap.roomCode} · ${snap.state}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final nav = Navigator.of(context);
              final onLeave = widget.onLeave;
              await widget.handle.leave();
              if (!mounted) return;
              nav.pop();
              onLeave?.call();
            },
            tooltip: '断开',
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(child: _buildMsgList(msgs)),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMsgList(List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 56,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '连接成功，开始聊天吧',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) => _bubble(msgs[i]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final theme = Theme.of(context);
    final alias = m['alias']?.toString() ?? '?';
    final text = m['text']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              alias,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(text, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              decoration: InputDecoration(
                hintText: '输入消息...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
        ],
      ),
    );
  }
}
