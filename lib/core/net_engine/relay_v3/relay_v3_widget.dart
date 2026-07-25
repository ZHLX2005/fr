// lib/core/net_engine/relay_v3/relay_v3_widget.dart
//
// 通用房间 widget — 房主开房（v3 snapshot 协议 + Lua 脚本）
//
// 与 v2 RelaySnapshotWidget 的差异：
// - 必传 defaultScript：snapshot 模式需要服务器执行 Lua 脚本
// - 回调只传 RoomHandle（v3 single transport, no separate transport handoff）
// - 简化的"创建房间"流程（玩家加入走 joinRoom API，不在 widget 里）
//
// 用法：
// ```dart
// RelayV3Widget(
//   relayUrl: 'http://...',
//   defaultScript: chatScriptBundle,
//   onRoomReady: (handle) {
//     // handle 已连接 WS 流，可直接进入 chat 页
//   },
// )
// ```

import 'package:flutter/material.dart';

import 'relay_v3_transport.dart';

/// 房间就绪回调 — handle 已连接 WS + 已订阅 snapshot 流
typedef V3RoomReadyCallback = void Function(RoomHandle handle);

/// 通用房间 widget（v3 snapshot 协议 + Lua 脚本）
///
/// - **房主模式**：选别名 → 建房 → 直接进入 chat
///
/// [defaultScript] 预打包的 Lua 脚本（snapshot 驱动逻辑）
/// [onRoomReady] 房间就绪后回调（handle 已连接 snapshot 流）
class RelayV3Widget extends StatefulWidget {
  const RelayV3Widget({
    super.key,
    required this.relayUrl,
    required this.defaultScript,
    this.defaultMaxPlayers = 8,
    this.title = 'v3 Relay',
    required this.onRoomReady,
  });

  final String relayUrl;
  final String defaultScript;
  final int defaultMaxPlayers;
  final String title;
  final V3RoomReadyCallback onRoomReady;

  @override
  State<RelayV3Widget> createState() => _RelayV3WidgetState();
}

class _RelayV3WidgetState extends State<RelayV3Widget> {
  final _aliasCtrl = TextEditingController();
  int _maxPlayers = 8;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _maxPlayers = widget.defaultMaxPlayers;
    _aliasCtrl.text = 'guest-${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '房主' : _aliasCtrl.text.trim();
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: widget.relayUrl,
        alias: alias,
        deviceId: 'host-${DateTime.now().microsecondsSinceEpoch}',
      );
      final h = await t.createRoom(
        script: widget.defaultScript,
        initialParams: const {},
        maxPlayers: _maxPlayers,
      );
      await h.connect();
      widget.onRoomReady(h);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.meeting_room_outlined, size: 56, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(widget.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              TextField(
                controller: _aliasCtrl,
                decoration: InputDecoration(
                  labelText: '你的名字',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              Text('人数：$_maxPlayers', style: theme.textTheme.bodyMedium),
              Slider(
                value: _maxPlayers.toDouble(),
                min: 2,
                max: 12,
                divisions: 10,
                label: '$_maxPlayers',
                onChanged: (v) => setState(() => _maxPlayers = v.toInt()),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                label: const Text('创建房间'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
