// lib/core/net_engine/relay/relay_room_chat.dart
//
// 2人房聊天 widget — 使用 RelayRoomWidget 作为房间大厅
//
// 流程：
// 1. RelayRoomWidget 处理建房/加入 + 等待页 + 参与者圆环
// 2. onRoomReady 回调后自动切换到聊天界面
// 3. 消息通过 publish('room/<code>/events', {type:'chat', ...}) 广播

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

/// 2人房聊天 widget
///
/// [relayUrl] 后端 relay 地址
class RelayRoomChatWidget extends StatefulWidget {
  const RelayRoomChatWidget({
    super.key,
    required this.relayUrl,
  });

  final String relayUrl;

  @override
  State<RelayRoomChatWidget> createState() => _RelayRoomChatWidgetState();
}

class _RelayRoomChatWidgetState extends State<RelayRoomChatWidget> {
  // RelayRoomWidget 交付后
  fw.RelayTransport? _transport;
  String? _roomCode;
  String? _myNodeId;
  bool _inChat = false;

  // 聊天
  final _textCtrl = TextEditingController();
  final List<_Msg> _msgs = [];
  StreamSubscription<fw.RemoteEvent>? _sub;

  @override
  void dispose() {
    _textCtrl.dispose();
    _sub?.cancel();
    _transport?.close();
    super.dispose();
  }

  void _onRoomReady(fw.RelayTransport transport, String code) {
    _transport = transport;
    _roomCode = code;
    _myNodeId = transport.myNodeId;
    _sub?.cancel();
    _sub = transport.subscribe('room/$code/events').listen((ev) {
      final p = ev.payload;
      if (p['type'] == 'chat') {
        if (!mounted) return;
        setState(() {
          _msgs.add(_Msg(
            fromNodeId: ev.fromNodeId,
            alias: (p['alias'] as String?) ?? '?',
            text: (p['text'] as String?) ?? '',
            mine: ev.fromNodeId == _myNodeId,
          ));
        });
      }
    });
    if (mounted) setState(() => _inChat = true);
  }

  Future<void> _send() async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    await t.publish('room/$code/events', {
      'type': 'chat',
      'from': _myNodeId,
      'text': text,
    });
    _textCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_inChat) return _buildChat();
    return fw.RelayRoomWidget(
      relayUrl: widget.relayUrl,
      defaultMaxPlayers: 2,
      maxPlayersRange: const [2],
      title: '2 人聊天',
      onRoomReady: _onRoomReady,
    );
  }

  Widget _buildChat() {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('聊天'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(child: _buildMsgList(theme)),
          _buildInput(theme),
        ],
      ),
    );
  }

  Widget _buildMsgList(ThemeData theme) {
    if (_msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            const Text('连接成功！', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('开始聊天吧', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _msgs.length,
      itemBuilder: (_, i) {
        final m = _msgs[i];
        return Align(
          alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 280),
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
                if (!m.mine) Text(m.alias, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(m.text, style: TextStyle(fontSize: 15, color: m.mine ? Colors.white : null)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInput(ThemeData theme) {
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
                hintText: '说点什么...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: theme.colorScheme.outlineVariant)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
              ),
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

class _Msg {
  final String fromNodeId;
  final String alias;
  final String text;
  final bool mine;
  _Msg({required this.fromNodeId, required this.alias, required this.text, required this.mine});
}
