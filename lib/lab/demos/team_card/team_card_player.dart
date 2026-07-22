// lib/lab/demos/team_card/team_card_player.dart
// 团建卡牌 — Player 视图（加入房间 + 收身份 + 展示）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'const_team_card.dart';
import 'team_card_types.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({super.key});
  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  fw.RelayTransport? _transport;
  StreamSubscription<fw.RemoteEvent>? _sub;
  bool _busy = false;
  String? _error;
  bool _joined = false;
  String? _myRole;
  int _onlineCount = 0;
  int _roomCapacity = 0;

  @override
  void initState() {
    super.initState();
    AliasPrefs.load().then((saved) {
      if (saved.isNotEmpty && mounted) {
        setState(() => _aliasCtrl.text = saved);
      }
    });
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    if (code.length != 6) { setState(() => _error = '请输入 6 位房间号'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: alias);
      await t.joinRoom(code, '');
      _transport = t;
      _roomCapacity = t.roomInfo?.maxPlayers ?? 0;
      _sub = t.subscribe('room/$code/events').listen((ev) {
        final p = ev.payload;
        if (p['type'] == 'deal') {
          final assignments = (p['assignments'] as Map?)?.cast<String, String>() ?? {};
          final role = assignments[t.myNodeId];
          if (role != null && mounted) setState(() => _myRole = role);
        }
        if (p['type'] == 'peer-joined' || p['type'] == 'peer-online') {
          if (mounted) setState(() => _onlineCount++);
        }
      });
      if (mounted) setState(() { _busy = false; _joined = true; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '加入失败: $e'; });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _transport?.close();
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_myRole != null) return _buildRoleCard(theme);
    if (_joined) {
      final waiting = _roomCapacity > 0;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 24),
              Text('已加入房间，等待发牌...', style: theme.textTheme.titleMedium),
              if (waiting) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_roomCapacity 人房 · 已有 $_onlineCount 人',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return _buildJoinForm(theme);
  }

  Widget _buildJoinForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(
            labelText: '你的名字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => AliasPrefs.save(v.trim()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          decoration: InputDecoration(
            labelText: '房间号（6 位）',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _joinRoom,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: const Text('加入房间'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(ThemeData theme) {
    final color = roleColor(theme, _myRole!);
    return Center(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.style, size: 36, color: color),
              ),
              const SizedBox(height: 20),
              Text('你的身份', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 8),
              Text(_myRole!, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 8),
              Text('只有你能看到这张卡', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
