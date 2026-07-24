// lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart
//
// 快照驱动的聊天页 — 完全替换 NetP2PChatPage 的事件流方式
//
// 整个页面只渲染一个 Snapshot 对象：
// - snapshot.players → 参与者圆环
// - snapshot.custom['messages'] → 聊天消息列表（业务自定义字段）
// - snapshot.status → 房间状态（waiting / playing / ended）
// 任何 WS 推送触发 snapshot 替换，UI 自动重绘。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_snapshot/relay_snapshot_transport.dart';
import 'package:xiaodouzi_fr/core/net_engine/widgets/participants_grid.dart';

/// 聊天消息（从 snapshot.custom['messages'] 提取）
class _ChatMsg {
  final String fromDeviceId;
  final String fromAlias;
  final String text;
  final DateTime ts;
  final bool mine;
  _ChatMsg({
    required this.fromDeviceId,
    required this.fromAlias,
    required this.text,
    required this.ts,
    required this.mine,
  });

  factory _ChatMsg.fromJson(Map<String, dynamic> j, String myDeviceId) => _ChatMsg(
        fromDeviceId: j['from'] as String? ?? '',
        fromAlias: j['alias'] as String? ?? '?',
        text: j['text'] as String? ?? '',
        ts: DateTime.tryParse(j['ts'] as String? ?? '') ?? DateTime.now(),
        mine: j['from'] == myDeviceId,
      );
}

/// 快照驱动的聊天页面
class NetP2PSnapshotChatPage extends StatefulWidget {
  const NetP2PSnapshotChatPage({
    super.key,
    required this.handle,
    required this.myDeviceId,
    this.onLeave,
  });

  final RoomHandle handle;
  final String myDeviceId;
  final VoidCallback? onLeave;

  @override
  State<NetP2PSnapshotChatPage> createState() => _NetP2PSnapshotChatPageState();
}

class _NetP2PSnapshotChatPageState extends State<NetP2PSnapshotChatPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.handle.latest;
    _sub = widget.handle.snapshots.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _sub?.cancel();
    widget.handle.dispose();
    super.dispose();
  }

  List<_ChatMsg> _extractMessages() {
    final snap = _snapshot;
    if (snap == null) return const [];
    final raw = snap.custom['messages'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) => _ChatMsg.fromJson(m.cast<String, dynamic>(), widget.myDeviceId)).toList();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    await widget.handle.applyAction('chat', {
      'from': widget.myDeviceId,
      'alias': widget.handle.transport.alias,
      'text': text,
      'ts': DateTime.now().toIso8601String(),
    });
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

    // 参与者：host + players（排除 host 重复）
    final all = <String, SnapshotPlayer>{
      snap.host.deviceId: snap.host,
      for (final p in snap.players) p.deviceId: p,
    };
    final peers = all.values.toList();
    peers.sort((a, b) => a.alias.compareTo(b.alias));
    final peersMap = <String, String>{
      for (final p in peers) p.deviceId: p.alias,
    };

    final msgs = _extractMessages();

    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${snap.code} · ${snap.status}'),
        actions: [
          if (widget.onLeave != null)
            IconButton(icon: const Icon(Icons.close), onPressed: widget.onLeave, tooltip: '断开'),
        ],
      ),
      body: Column(
        children: [
          // 参与者圆环卡片（复用 LobbyParticipants）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: LobbyParticipants(
              capacity: snap.maxPlayers,
              participants: peersMap,
              slotSize: 56,
            ),
          ),
          const SizedBox(height: 8),
          // 聊天消息
          Expanded(child: _buildMsgList(msgs)),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMsgList(List<_ChatMsg> msgs) {
    if (msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('连接成功，开始聊天吧',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
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

  Widget _bubble(_ChatMsg m) {
    final theme = Theme.of(context);
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: m.mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.mine ? 16 : 4),
            bottomRight: Radius.circular(m.mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!m.mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(m.fromAlias,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    )),
              ),
            Text(m.text,
                style: TextStyle(
                  fontSize: 15,
                  color: m.mine ? theme.colorScheme.onPrimary : null,
                )),
            const SizedBox(height: 2),
            Text(
              '${m.ts.hour.toString().padLeft(2, '0')}:${m.ts.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: m.mine
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                    : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
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
              controller: _textCtrl,
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