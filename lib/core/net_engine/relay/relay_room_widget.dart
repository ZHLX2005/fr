// lib/core/net_engine/relay/relay_room_widget.dart
//
// 通用房间 widget — 房主开房（自定义人数）→ 等待 → 玩家加入 → 房间就绪
//
// 业务层只需：
// 1. 渲染 RelayRoomWidget
// 2. onRoomReady 回调拿到已连接的 transport + roomCode
// 3. 通过 transport.publish 广播业务元数据
//
// 用法：
// ```dart
// RelayRoomWidget(
//   relayUrl: 'http://...',
//   maxPlayers: 4,
//   onRoomReady: (transport, roomCode) {
//     // transport 已连接，roomCode 已知
//     // 可以 transport.publish('room/$roomCode/events', {...}) 广播业务数据
//   },
// )
// ```

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../net_engine.dart' as fw;
import '../widgets/participants_grid.dart';

/// 房间就绪回调 — transport 已连接，可安全 publish/subscribe
typedef RoomReadyCallback = void Function(fw.RelayTransport transport, String roomCode);

/// 通用房间 widget
///
/// - **房主模式**：选人数 → 建房 → 等待页（显示房号+在线人数）→ [onRoomReady]
/// - **玩家模式**：输入房号 → 加入 → 等待页 → [onRoomReady]
///
/// [maxPlayers] 房间人数上限（房主模式可调，玩家模式由后端返回）
/// [onRoomReady] 房间就绪后回调（transport 已连接 + 已 subscribe room events）
class RelayRoomWidget extends StatefulWidget {
  const RelayRoomWidget({
    super.key,
    required this.relayUrl,
    this.defaultMaxPlayers = 2,
    this.maxPlayersRange = const [2, 3, 4, 6, 8, 10, 12],
    this.title = '房间',
    required this.onRoomReady,
  });

  final String relayUrl;
  final int defaultMaxPlayers;
  final List<int> maxPlayersRange;
  final String title;
  final RoomReadyCallback onRoomReady;

  @override
  State<RelayRoomWidget> createState() => _RelayRoomWidgetState();
}

enum _Stage { select, waiting }

class _RelayRoomWidgetState extends State<RelayRoomWidget> {
  _Stage _stage = _Stage.select;
  bool _isHost = true;

  // 房主配置
  int _maxPlayers = 2;

  // 玩家输入
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();

  // 连接状态
  fw.RelayTransport? _transport;
  String? _roomCode;
  bool _busy = false;
  String? _error;

  // 在线追踪
  final _onlineAliases = <String, String>{};
  StreamSubscription<fw.RemoteEvent>? _sub;
  Timer? _peersTimer;
  bool _handedOff = false;

  static const _kAliasPref = 'localnet.alias';

  @override
  void initState() {
    super.initState();
    _maxPlayers = widget.defaultMaxPlayers;
    _loadAlias();
  }

  Future<void> _loadAlias() async {
    final p = await SharedPreferences.getInstance();
    final alias = p.getString(_kAliasPref) ?? '';
    if (mounted && alias.isNotEmpty) setState(() => _aliasCtrl.text = alias);
  }

  Future<void> _saveAlias(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAliasPref, alias);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    _sub?.cancel();
    _peersTimer?.cancel();
    if (!_handedOff) _transport?.close();
    super.dispose();
  }

  // ——— 房主 ———

  Future<void> _createRoom() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '房主' : _aliasCtrl.text.trim();
    setState(() { _busy = true; _error = null; });
    try {
      await _saveAlias(alias);
      final t = await fw.RelayTransport.create(relayUrl: widget.relayUrl, alias: alias);
      final info = await t.createRoom(fw.RoomConfig(
        maxPlayers: _maxPlayers,
        canStartBeforeFull: true,
      ));
      _transport = t;
      _roomCode = info.code;
      _onlineAliases[t.myNodeId] = alias;
      _subscribe(t, info.code);
      _startPeersPoll(info.code);
      setState(() { _busy = false; _stage = _Stage.waiting; });
    } catch (e) {
      setState(() { _busy = false; _error = '创建失败: $e'; });
    }
  }

  // ——— 玩家 ———

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    if (code.length != 6) { setState(() => _error = '请输入 6 位房间号'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await _saveAlias(alias);
      final t = await fw.RelayTransport.create(relayUrl: widget.relayUrl, alias: alias);
      await t.joinRoom(code, '');
      _transport = t;
      _roomCode = code;
      _maxPlayers = t.roomInfo?.maxPlayers ?? 0;
      _onlineAliases[t.myNodeId] = alias;
      _subscribe(t, code);
      _startPeersPoll(code);
      setState(() { _busy = false; _stage = _Stage.waiting; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString().contains('404') ? '房间不存在' : '加入失败: $e'; });
    }
  }

  // ——— 订阅 + 在线追踪 ———

  void _subscribe(fw.RelayTransport t, String code) {
    _sub?.cancel();
    _sub = t.subscribe('room/$code/events').listen((ev) {
      final type = ev.payload['type'] as String?;
      if (type == 'peer-joined' || type == 'peer-online') {
        final did = ev.payload['deviceId'] as String? ?? '';
        final alias = ev.payload['alias'] as String? ?? '?';
        if (did.isNotEmpty) _onlineAliases[did] = alias;
        if (mounted) setState(() {});
      } else if (type == 'peer-left') {
        final did = ev.payload['deviceId'] as String? ?? '';
        _onlineAliases.remove(did);
        if (mounted) setState(() {});
      }
    });
  }

  void _startPeersPoll(String code) {
    _peersTimer?.cancel();
    _peersTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchPeers(code));
  }

  Future<void> _fetchPeers(String code) async {
    try {
      final resp = await http.get(Uri.parse('${widget.relayUrl}/api/v1/relay/rooms/$code/peers'));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final list = (body['peers'] as List?) ?? [];
        for (final p in list) {
          final did = (p as Map)['deviceId'] as String?;
          final alias = p['alias'] as String? ?? '?';
          if (did != null) _onlineAliases[did] = alias;
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // ——— 交付 ———

  void _handoff() {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    _handedOff = true;
    _sub?.cancel();
    _peersTimer?.cancel();
    widget.onRoomReady(t, code);
  }

  int get _capacity => _maxPlayers;
  int get _online => _onlineAliases.length;
  int get _waiting => _capacity > 0 ? _capacity - _online : 0;

  // ——— UI ———

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_stage == _Stage.waiting) return _buildWaiting(theme);
    return _buildSelect(theme);
  }

  Widget _buildSelect(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
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
              // 别名
              TextField(
                controller: _aliasCtrl,
                decoration: InputDecoration(
                  labelText: '你的名字',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('房主'), icon: Icon(Icons.add)),
                  ButtonSegment(value: false, label: Text('加入'), icon: Icon(Icons.login)),
                ],
                selected: {_isHost},
                onSelectionChanged: (s) => setState(() => _isHost = s.first),
              ),
              const SizedBox(height: 20),
              if (_isHost) ...[
                // 人数选择
                Wrap(
                  spacing: 8, runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: widget.maxPlayersRange.map((n) => ChoiceChip(
                    label: Text('$n 人'),
                    selected: _maxPlayers == n,
                    onSelected: (_) => setState(() => _maxPlayers = n),
                  )).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _createRoom,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                  label: const Text('创建房间'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: '房间号（6 位）',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _joinRoom,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                  label: const Text('加入房间'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
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

  Widget _buildWaiting(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_isHost ? '等待玩家' : '等待开始'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 房号
              if (_isHost) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 2),
                  ),
                  child: Text(
                    _roomCode!,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Text('分享房间号给玩家', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 24),
              ],
              // 在线人数
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: _online),
                duration: const Duration(milliseconds: 300),
                builder: (_, count, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_capacity 人房 · 已到 $count 人${_waiting > 0 ? ' · 还需 $_waiting 人' : ''}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 参与者圆环卡片（复用 LobbyParticipants）
              LobbyParticipants(
                capacity: _capacity,
                participants: _onlineAliases,
              ),
              const SizedBox(height: 32),
              // 进入按钮
              if (_isHost)
                FilledButton.icon(
                  onPressed: _handoff,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_waiting > 0 ? '提前开始（$_online/$_capacity）' : '开始'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                )
              else
                Column(
                  children: [
                    const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)),
                    const SizedBox(height: 12),
                    Text('等待房主开始...', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
