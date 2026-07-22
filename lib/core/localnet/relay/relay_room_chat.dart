// lib/core/localnet/relay/relay_room_chat.dart
//
// 2人房聊天 widget（房主开房 → 玩家输入房号加入 → 自动开聊）
//
// 流程：
// 1. 房主：createRoom(maxPlayers: 2) → 显示 6 位房号 + 等待页
// 2. 玩家：输入 6 位房号 + 名字 → joinRoom(code) → 自动订阅
// 3. 双方都连上 → 自动切换到聊天界面
// 4. 消息通过 publish('room/<code>/events', {type:'chat', from, alias, text}) 广播
// 5. 客户端按 from 字段渲染消息列表

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

/// 2人房聊天 widget
///
/// [relayUrl] 后端 relay 地址
/// [myAlias] 自己的名字（房主/玩家都可自定义）
class RelayRoomChatWidget extends StatefulWidget {
  const RelayRoomChatWidget({
    super.key,
    required this.relayUrl,
    this.myAlias = '我',
  });

  final String relayUrl;
  final String myAlias;

  @override
  State<RelayRoomChatWidget> createState() => _RelayRoomChatWidgetState();
}

enum _Stage { role, hostLobby, guestJoin, chat }

class _RelayRoomChatWidgetState extends State<RelayRoomChatWidget> {
  _Stage _stage = _Stage.role;

  // 连接状态
  fw.RelayTransport? _transport;
  String? _roomCode;
  String? _myNodeId;
  String? _myRole; // 'host' | 'guest'
  bool _busy = false;
  String? _error;

  // 玩家输入
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();

  // 聊天
  final _textCtrl = TextEditingController();
  final List<_Msg> _msgs = [];
  StreamSubscription<fw.RemoteEvent>? _sub;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    _textCtrl.dispose();
    _sub?.cancel();
    _transport?.close();
    super.dispose();
  }

  // ——— 房主 ———

  Future<void> _createRoom() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = await fw.RelayTransport.create(relayUrl: widget.relayUrl, alias: widget.myAlias);
      final info = await t.createRoom(fw.RoomConfig(
        maxPlayers: 2,
        schema: {'type': '1v1-chat'},
        canStartBeforeFull: false,
      ));
      setState(() {
        _myNodeId = t.myNodeId;
        _roomCode = info.code;
        _busy = false;
        _stage = _Stage.hostLobby;
      });
      _subscribe(t, info.code);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '创建失败: $e';
      });
    }
  }

  // ——— 玩家 ———

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间号');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final t = await fw.RelayTransport.create(relayUrl: widget.relayUrl, alias: alias);
      await t.joinRoom(code, '');
      setState(() {
        _myNodeId = t.myNodeId;
        _roomCode = code;
        _busy = false;
        _stage = _Stage.chat;
      });
      _subscribe(t, code);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().contains('404') ? '房间不存在或已满' : e.toString();
      });
    }
  }

  // ——— 共享订阅 + 消息处理 ———

  void _subscribe(fw.RelayTransport t, String code) {
    _transport = t;
    _sub?.cancel();
    _sub = t.subscribe('room/$code/events').listen((ev) {
      final p = ev.payload;
      if (p['type'] == 'chat') {
        setState(() {
          _msgs.add(_Msg(
            fromNodeId: ev.fromNodeId,
            alias: (p['alias'] as String?) ?? '?',
            text: (p['text'] as String?) ?? '',
            mine: ev.fromNodeId == _myNodeId,
          ));
        });
      } else if (p['type'] == 'peer-joined' || p['type'] == 'peer-online') {
        // 房主等玩家就位：监测到 2 人都连上后自动切到聊天
        if (_stage == _Stage.hostLobby) {
          // 房主自己 + 1 个玩家 = 2 人
          _stage = _Stage.chat;
        }
      }
    });
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
      'alias': _myRole == 'guest' ? _aliasCtrl.text.trim() : widget.myAlias,
      'text': text,
    });
    _textCtrl.clear();
  }

  // ——— UI 路由 ———

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_stage) {
        _Stage.role => _buildRoleSelect(theme),
        _Stage.hostLobby => _buildHostLobby(theme),
        _Stage.guestJoin => _buildRoleSelect(theme), // 复用选择页
        _Stage.chat => _buildChat(theme),
      },
    );
  }

  Widget _buildRoleSelect(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('2 人房聊天', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('房主开房后分享房间号给对方', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(child: _roleCard(theme, 'host', '我是房主', '创建房间并等待', Icons.meeting_room)),
                  const SizedBox(width: 12),
                  Expanded(child: _roleCard(theme, 'guest', '我是玩家', '输入 6 位房号加入', Icons.login)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCard(ThemeData theme, String role, String title, String subtitle, IconData icon) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _busy ? null : () {
        if (role == 'host') {
          _createRoom();
        } else {
          _showJoinSheet(theme);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showJoinSheet(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 24, right: 24, top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加入房间', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: _aliasCtrl,
              decoration: InputDecoration(labelText: '你的名字', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: '房间号（6位）', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : () {
                  Navigator.of(ctx).pop();
                  _joinRoom();
                },
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('加入'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          ],
        ),
      ),
    );
  }

  Widget _buildHostLobby(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('房主·等待加入'), backgroundColor: theme.colorScheme.surface, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pulse(Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.hourglass_empty, size: 40, color: theme.colorScheme.primary),
              )),
              const SizedBox(height: 24),
              const Text('等待对方加入...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('将房间号分享给对方', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 2),
                ),
                child: Text(
                  _roomCode!,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 8, color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChat(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: const Text('2 人房'), backgroundColor: theme.colorScheme.surface, elevation: 0),
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
            margin: const EdgeInsets.symmetric(vertical: 4),
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
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
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

  Widget _pulse(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 900),
      builder: (_, scale, __) => Transform.scale(scale: scale, child: child),
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
