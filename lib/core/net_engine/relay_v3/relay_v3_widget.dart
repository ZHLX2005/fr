// lib/core/net_engine/relay_v3/relay_v3_widget.dart
//
// v3 Lua 状态机大厅 + 游戏入口。
//
// 流程：
//
//   ┌──────────────────────────────────────────────────────┐
//   │  1. 模式选择（创建房间 / 加入房间）                    │
//   │     - 创建：输入别名 → 建房 → 自动进入 lobby         │
//   │     - 加入：输入别名 + 房间码 → 加入 → 进入 lobby    │
//   ├──────────────────────────────────────────────────────┤
//   │  2. Lobby 等待                                       │
//   │     - 房主看到：房间码 + 参与者圆环 + "开始游戏"按钮  │
//   │     - 加入者看到：房间码 + 参与者圆环 + "等待房主开始"│
//   │     - snapshot 自动更新参与者列表（on_join → players）│
//   ├──────────────────────────────────────────────────────┤
//   │  3. 游戏开始（state="playing"）                      │
//   │     - snapshot.state == "playing" → 触发 onStarted    │
//   │     - onStarted 回调传入 RoomHandle，业务层接管      │
//   └──────────────────────────────────────────────────────┘
//
// Lua 状态机脚本决定 state 转换规则。默认用 lobbyChat 脚本：
//   - on_action_START 把 state 设为 "playing"
//
// 用法：
// ```dart
// RelayV3Lobby(
//   relayUrl: 'http://...',
//   script: kLobbyChatScript,
//   onStarted: (handle) {
//     Navigator.push(context, GamePage(handle: handle));
//   },
// )
// ```

import 'dart:async';

import 'package:flutter/material.dart';
import 'relay_device_id.dart';
import 'participants_grid.dart';

import 'relay_v3_transport.dart';

/// 游戏开始回调 — 传入 [RoomHandle]，业务层接管
typedef V3OnStarted = void Function(RoomHandle handle);

/// v3 大厅 Widget
///
/// 统一"建房→大厅→开始"和"加入→大厅→开始"两条路径。
/// [script] Lua 状态机脚本。
/// [onStarted] state=="playing" 时触发。
class RelayV3Lobby extends StatefulWidget {
  const RelayV3Lobby({
    super.key,
    required this.relayUrl,
    this.script,
    this.maxPlayers = 8,
    required this.onStarted,
    this.title = 'P2P 房间',
  });

  final String relayUrl;
  final String? script;
  final int maxPlayers;
  final V3OnStarted onStarted;
  final String title;

  @override
  State<RelayV3Lobby> createState() => _RelayV3LobbyState();
}

enum _LobbyPhase { pickMode, joinInput, loading, lobby, playing }

class _RelayV3LobbyState extends State<RelayV3Lobby> {
  _LobbyPhase _phase = _LobbyPhase.pickMode;

  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _maxPlayers = 8;

  RelayV3Transport? _transport;
  RoomHandle? _handle;
  StreamSubscription<Snapshot>? _snapSub;

  String? _error;
  bool _busy = false;
  bool _isHost = false;

  Snapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _maxPlayers = widget.maxPlayers;
    _aliasCtrl.text = 'guest-${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    _snapSub?.cancel();
    // 不 dispose handle — 所有权已转移给 onStarted 回调的接收者。
    super.dispose();
  }

  // ——— 建房 ———

  Future<void> _createRoom() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入你的名字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _phase = _LobbyPhase.loading;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: widget.relayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      final h = await t.createRoom(
        script: widget.script ?? '',
        initialParams: <String, dynamic>{'device_id': t.deviceId, 'alias': alias},
        maxPlayers: _maxPlayers,
      );
      _transport = t;
      _handle = h;
      _isHost = true;
      _subscribeSnapshot(h);
      if (!mounted) return;
      setState(() {
        _snapshot = h.latest;
        _phase = _LobbyPhase.lobby;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
        _phase = _LobbyPhase.pickMode;
      });
    }
  }

  // ——— 加入 ———

  Future<void> _joinRoom() async {
    final alias = _aliasCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入你的名字');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = '请输入房间码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _phase = _LobbyPhase.loading;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: widget.relayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      final h = await t.joinRoom(code: code);
      _transport = t;
      _handle = h;
      _isHost = false;
      _subscribeSnapshot(h);
      if (!mounted) return;
      setState(() {
        _snapshot = h.latest;
        _phase = _LobbyPhase.lobby;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
        _phase = _LobbyPhase.joinInput; // 回到加入表单
      });
    }
  }

  // ——— snapshot 订阅 ———

  void _subscribeSnapshot(RoomHandle h) {
    _snapSub?.cancel();
    _snapSub = h.snapshots.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      if (snap.state == 'playing' && _phase == _LobbyPhase.lobby) {
        _phase = _LobbyPhase.playing;
        widget.onStarted(h);
      }
    });
  }

  // ——— 开始游戏（仅房主） ———

  Future<void> _startGame() async {
    final h = _handle;
    if (h == null) return;
    setState(() => _busy = true);
    try {
      await h.applyAction(
        type: 'START',
        params: {'device_id': _transport!.deviceId},
      );
      // snapshot 流会触发 onStarted
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '开始失败: $e';
        _busy = false;
      });
    }
  }

  // ——— 断开 ———

  void _disconnect() {
    _snapSub?.cancel();
    _snapSub = null;
    _handle?.dispose();
    _handle = null;
    _transport = null;
    setState(() {
      _snapshot = null;
      _isHost = false;
      _phase = _LobbyPhase.pickMode;
      _error = null;
    });
  }

  // ——— 工具 ———

  /// 从 snapshot context 中安全读取 int 值（JSON 可能返回 int/float）
  static int? _snapshotToInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ——— 从 snapshot 提取玩家列表 ———

  Map<String, String> _extractPlayers() {
    final snap = _snapshot;
    if (snap == null) return const {};
    final raw = snap.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  // ——— UI ————

  @override
  Widget build(BuildContext context) {
    if (_phase == _LobbyPhase.playing) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: SafeArea(child: _buildBody()),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final t = switch (_phase) {
      _LobbyPhase.pickMode => widget.title,
      _LobbyPhase.joinInput => '加入房间',
      _LobbyPhase.loading => '连接中…',
      _LobbyPhase.lobby => '大厅',
      _LobbyPhase.playing => widget.title,
    };
    return AppBar(
      title: Text(t),
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      actions: [
        if (_phase == _LobbyPhase.lobby || _phase == _LobbyPhase.playing)
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _disconnect,
            tooltip: '断开',
          ),
      ],
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _LobbyPhase.pickMode => _buildPickMode(),
      _LobbyPhase.joinInput => _buildJoinInput(),
      _LobbyPhase.loading => const Center(child: CircularProgressIndicator()),
      _LobbyPhase.lobby => _buildLobby(),
      _LobbyPhase.playing => const SizedBox.shrink(),
    };
  }

  // ——— 模式选择（别名 + 创建/加入按钮） ———

  Widget _buildPickMode() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.meeting_room_outlined, size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('创建或加入房间',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline)),
          const SizedBox(height: 40),
          TextField(
            controller: _aliasCtrl,
            decoration: InputDecoration(
              labelText: '你的名字',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _createRoom,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add),
            label: Text(_busy ? '创建中…' : '创建房间'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _phase = _LobbyPhase.joinInput;
                _error = null;
              });
            },
            icon: const Icon(Icons.login),
            label: const Text('加入房间'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 20),
          Text('最多 ${_maxPlayers} 人',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          Slider(
            value: _maxPlayers.toDouble(), min: 2, max: 12, divisions: 10,
            label: '$_maxPlayers',
            onChanged: (v) => setState(() => _maxPlayers = v.toInt()),
          ),
        ],
      ),
    );
  }

  // ——— 加入房间（输入房间码） ———

  Widget _buildJoinInput() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.vpn_key_outlined, size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('加入房间',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          TextField(
            controller: _aliasCtrl,
            decoration: InputDecoration(
              labelText: '你的名字',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: '房间码',
              hintText: '请输入 6 位房间码',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.tag),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _joinRoom,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: Text(_busy ? '加入中…' : '加入房间'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              setState(() {
                _phase = _LobbyPhase.pickMode;
                _error = null;
              });
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  // ——— 大厅 ———

  Widget _buildLobby() {
    final theme = Theme.of(context);
    final snap = _snapshot;
    if (snap == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final players = _extractPlayers();
    final code = snap.roomCode;
    final playerCount = players.length;
    final maxPlayers = _snapshotToInt(snap.context['max_players']) ?? _maxPlayers;
    final canStart = _isHost && !_busy && playerCount >= 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // 房间码
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Text('房间码',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 4),
                  Text(code,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold, letterSpacing: 6,
                        color: theme.colorScheme.primary,
                      )),
                  Text('请将房间码分享给好友',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          LobbyParticipants(
            capacity: maxPlayers,
            participants: players,
            slotSize: 66,
          ),
          const SizedBox(height: 32),
          if (_isHost)
            FilledButton.icon(
              onPressed: canStart ? _startGame : null,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_busy ? '开始中…' : '开始游戏'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('等待房主开始游戏…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline)),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
