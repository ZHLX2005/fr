// lib/core/surround_game/lan/relay_lobby_page.dart
//
// 网络对局入口页 — 通过房间号发现对端，底层走 WS 通讯。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;
import '../board_theme.dart';
import 'game_room.dart';
import 'lan_room_page.dart';
import 'persistence/player_profile_service.dart';
import 'service/lan_service_adapter.dart';

class RelayLobbyPage extends StatefulWidget {
  const RelayLobbyPage({super.key});

  @override
  State<RelayLobbyPage> createState() => _RelayLobbyPageState();
}

class _RelayLobbyPageState extends State<RelayLobbyPage> {
  final _adapter = LanServiceAdapter.instance;
  final _aliasCtrl = TextEditingController();
  final _roomCodeCtrl = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<LanServiceError>? _errorSub;
  bool _isBusy = false;
  String? _error;
  fw.RelayTransport? _transport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final savedAlias = await PlayerProfileService.loadAlias();
    if (!mounted) return;
    _aliasCtrl.text = savedAlias ?? '';
    _errorSub = _adapter.watchErrors().listen(_onError);
  }

  Future<void> _createRoom() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请先输入名称');
      return;
    }
    PlayerProfileService.saveAlias(alias);
    setState(() { _isBusy = true; _error = null; });

    try {
      final transport = await fw.RelayTransport.create(
        relayUrl: 'http://47.110.80.47:8988',
        alias: alias,
      );
      final code = await transport.createRoom();
      await transport.joinScope('peers');
      _adapter.attach(transport, alias: alias);
      _transport = transport;
      if (!mounted) return;
      setState(() => _isBusy = false);

      final room = GameRoom.placeholder(roomId: code);
      await _adapter.createRoom(room);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LanRoomPage(
            roomId: code,
            role: 'host',
            initialRoom: room.copyWith(
              hostId: _adapter.myDeviceId,
              hostName: alias,
            ),
          ),
        ),
      ).then((_) {
        _adapter.closeRoom(code);
        _adapter.detach();
        _transport?.stop();
      });
    } catch (e) {
      if (mounted) setState(() { _isBusy = false; _error = '创建房间失败: $e'; });
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位房间号');
      return;
    }
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请先输入名称');
      return;
    }
    setState(() { _isBusy = true; _error = null; });

    try {
      final transport = await fw.RelayTransport.create(
        relayUrl: 'http://47.110.80.47:8988',
        alias: alias,
      );
      await transport.joinRoom(code);
      await transport.joinScope('peers');
      _adapter.attach(transport, alias: alias);
      _transport = transport;
      if (!mounted) return;
      setState(() => _isBusy = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LanRoomPage(
            roomId: code,
            role: 'client',
            initialRoom: GameRoom(
              roomId: code,
              hostId: 'relay',
              hostName: 'Host',
            ),
          ),
        ),
      ).then((_) {
        _adapter.closeRoom(code);
        _adapter.detach();
        _transport?.stop();
      });
    } catch (e) {
      if (mounted) setState(() { _isBusy = false; _error = '加入房间失败: $e'; });
    }
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _aliasCtrl.dispose();
    _roomCodeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('网络对局'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud, size: 64, color: theme.piecePlayerA),
            const SizedBox(height: 24),
            Text('跨网络对战',
                style: textTheme.titleLarge?.copyWith(color: theme.btnText)),
            const SizedBox(height: 16),

            // 别名
            SizedBox(
              width: 200,
              child: TextField(
                controller: _aliasCtrl,
                focusNode: _focusNode,
                style: TextStyle(color: theme.btnText),
                decoration: InputDecoration(
                  hintText: '输入你的名称',
                  hintStyle:
                      TextStyle(color: theme.btnSub.withValues(alpha: 0.5)),
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: theme.btnSub),
                ),
                maxLength: 16,
              ),
            ),
            const SizedBox(height: 24),

            // 创建房间
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isBusy ? null : _createRoom,
                icon: _isBusy
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline),
                label: Text(_isBusy ? '创建中...' : '创建房间'),
                style: FilledButton.styleFrom(
                    backgroundColor: theme.piecePlayerA),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('或', style: TextStyle(color: Colors.grey))),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            // 房间号输入
            SizedBox(
              width: 200,
              child: TextField(
                controller: _roomCodeCtrl,
                style: TextStyle(
                    color: theme.btnText, letterSpacing: 4),
                decoration: InputDecoration(
                  hintText: '输入 6 位房间号',
                  hintStyle:
                      TextStyle(color: theme.btnSub.withValues(alpha: 0.5)),
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key, color: theme.btnSub),
                ),
                maxLength: 6,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _joinRoom(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _joinRoom,
                icon: const Icon(Icons.login),
                label: Text(_isBusy ? '加入中...' : '加入房间'),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13),
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
