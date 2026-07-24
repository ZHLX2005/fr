// lib/core/net_engine_biz/net_engine_discovery_host.dart
//
// NetEngine biz 入口 — 使用 v2 引擎 + 自定义人数开房

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

import 'net_engine_message.dart';
import 'net_engine_service.dart';

class NetEngineBizHostPage extends StatefulWidget {
  const NetEngineBizHostPage({super.key});
  @override
  State<NetEngineBizHostPage> createState() => _NetEngineBizHostPageState();
}

enum _Role { master, player }

class _NetEngineBizHostPageState extends State<NetEngineBizHostPage> {
  _Role _role = _Role.master;
  int _maxPlayers = 4;
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;

  // 连接后
  String? _roomCode;
  StreamSubscription<RoomEvent>? _sub;
  final _msgs = <NetEngineMessage>[];
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _aliasCtrl.text = '游客${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _sub?.cancel();
    netEngineService.stop();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() { _busy = true; });
    try {
      await netEngineService.createRoom(
        relayUrl: 'http://47.110.80.47:8988',
        alias: _aliasCtrl.text.trim(),
        maxPlayers: _maxPlayers,
      );
      netEngineService.subscribeRoom(netEngineService.roomCode!);
      _sub = netEngineService.events.listen(_onEvent);
      setState(() {
        _roomCode = netEngineService.roomCode;
        _busy = false;
      });
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) { setState(() => _codeCtrl.text = ''); return; }
    setState(() { _busy = true; });
    try {
      await netEngineService.joinRoom(
        relayUrl: 'http://47.110.80.47:8988',
        alias: _aliasCtrl.text.trim(),
        roomCode: code,
      );
      netEngineService.subscribeRoom(code);
      _sub = netEngineService.events.listen(_onEvent);
      setState(() { _roomCode = code; _busy = false; });
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入失败: $e')));
    }
  }

  void _onEvent(RoomEvent e) {
    if (e is MessageReceived) {
      setState(() => _msgs.add(e.msg));
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: 100.ms, curve: Curves.easeOut);
      });
    }
  }

  void _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    await netEngineService.sendMessage(text: text);
    _textCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_roomCode != null) return _buildChat(theme);
    return _buildLobby(theme);
  }

  Widget _buildLobby(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('NetEngine'), actions: [
        IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => fw.NetEngineSettingsPage(mode: fw.MessageNetMode.relay, relayUrl: 'http://47.110.80.47:8988')))),
        IconButton(icon: const Icon(Icons.bug_report), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const fw.NetEngineDebugPage()))),
      ]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SegmentedButton<_Role>(
              segments: const [
                ButtonSegment(value: _Role.master, label: Text('房主'), icon: Icon(Icons.meeting_room)),
                ButtonSegment(value: _Role.player, label: Text('加入'), icon: Icon(Icons.login)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(labelText: '你的名字', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            if (_role == _Role.master) ...[
              Row(children: [
                const Text('房间人数'),
                const Spacer(),
                Text('$_maxPlayers 人', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              Slider(value: _maxPlayers.toDouble(), min: 2, max: 12, divisions: 10, label: '$_maxPlayers', onChanged: (v) => setState(() => _maxPlayers = v.round())),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _busy ? null : _createRoom, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add), label: const Text('创建房间')),
            ] else ...[
              TextField(controller: _codeCtrl, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '房间号（6位）', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _busy ? null : _joinRoom, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login), label: const Text('加入房间')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChat(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: Text('房间 $_roomCode')),
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Center(child: Text('开始聊天吧'))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final mine = m.fromNodeId == netEngineService.myNodeId;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!mine) Text(m.fromAlias, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              Text(m.text, style: TextStyle(fontSize: 15, color: mine ? Colors.white : null)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(color: theme.colorScheme.surface, border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
            child: Row(
              children: [
                Expanded(child: TextField(
                  controller: _textCtrl,
                  decoration: InputDecoration(hintText: '说点什么...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), filled: true, fillColor: theme.colorScheme.surfaceContainerHighest),
                  onSubmitted: (_) => _send(),
                )),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on int { Duration get ms => Duration(milliseconds: this); }
