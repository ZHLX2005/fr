// lib/core/net_p2p/pages/net_p2p_chat_page.dart
//
// 通用聊天页面 — 基于 Transport 的 pub/sub

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

/// 聊天消息模型
class _ChatMsg {
  final String fromNodeId;
  final String fromAlias;
  final String text;
  final DateTime ts;
  final bool mine;
  _ChatMsg({
    required this.fromNodeId,
    required this.fromAlias,
    required this.text,
    required this.ts,
    required this.mine,
  });
}

/// 通用聊天页面
///
/// 基于 Transport 的 scope API：
/// - 发送：getScope(scope).merge({'messages': [...]}) + broadcastScope(scope)
/// - 接收：watchScope(scope) 流
class NetP2PChatPage extends StatefulWidget {
  const NetP2PChatPage({
    super.key,
    required this.transport,
    required this.scope,
    required this.myNodeId,
    required this.peerAlias,
    this.onLeave,
  });

  final fw.Transport transport;
  final String scope;
  final String myNodeId;
  final String peerAlias;
  final VoidCallback? onLeave;

  @override
  State<NetP2PChatPage> createState() => _NetP2PChatPageState();
}

class _NetP2PChatPageState extends State<NetP2PChatPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _msgs = <_ChatMsg>[];
  StreamSubscription<fw.DataLog>? _scopeSub;

  @override
  void initState() {
    super.initState();
    // 必须先 joinScope 注册 scope 到 transport 内部状态，
    // 否则 getScope/broadcastScope 会因 _scopes[scope]==null 而静默失效
    widget.transport.joinScope(widget.scope);
    _scopeSub = widget.transport.watchScope(widget.scope).listen(_onScopeUpdate);
    // 广播自己的加入（让对端看到已有消息）
    widget.transport.broadcastScope(widget.scope);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _scopeSub?.cancel();
    super.dispose();
  }

  void _onScopeUpdate(fw.DataLog log) {
    final raw = log.state['messages'];
    if (raw is! List) return;
    setState(() {
      _msgs.clear();
      for (final entry in raw) {
        if (entry is! Map) continue;
        final from = entry['from'] as String? ?? '';
        final alias = entry['alias'] as String? ?? '?';
        final text = entry['text'] as String? ?? '';
        final tsStr = entry['ts'] as String? ?? '';
        final ts = DateTime.tryParse(tsStr) ?? DateTime.now();
        _msgs.add(_ChatMsg(
          fromNodeId: from,
          fromAlias: alias,
          text: text,
          ts: ts,
          mine: from == widget.myNodeId,
        ));
      }
    });
    _scrollToBottom();
  }

  void _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final t = widget.transport;
    final scope = widget.scope;
    final log = t.getScope(scope);
    if (log == null) return;

    // 追加消息到 scope 状态
    final list = (log.state['messages'] as List?)?.cast<Map>() ?? <Map>[];
    list.add({
      'from': widget.myNodeId,
      'alias': '我',
      'text': text,
      'ts': DateTime.now().toIso8601String(),
    });
    log.merge({'messages': list}, localNodeId: widget.myNodeId);
    // 本地立即显示
    _onScopeUpdate(log);
    // 广播给对端
    t.broadcastScope(scope);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerAlias),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if (widget.onLeave != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onLeave,
              tooltip: '断开',
            ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          Expanded(child: _buildMsgList()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMsgList() {
    if (_msgs.isEmpty) {
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _msgs.length,
      itemBuilder: (_, i) {
        final m = _msgs[i];
        return Align(
          alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: m.mine
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          color: Theme.of(context).colorScheme.primary,
                        )),
                  ),
                Text(m.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: m.mine ? Theme.of(context).colorScheme.onPrimary : null,
                    )),
                const SizedBox(height: 2),
                Text(
                  '${m.ts.hour.toString().padLeft(2, '0')}:${m.ts.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: m.mine
                        ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _send,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
