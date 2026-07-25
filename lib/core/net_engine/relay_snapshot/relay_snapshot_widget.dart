// lib/core/net_engine/relay_snapshot/relay_snapshot_widget.dart
//
// 通用房间 widget — 房主开房 / 玩家加入（v2 snapshot 协议）
//
// 完全替代 v1 RelayRoomWidget：所有 transport 调用走 RelaySnapshotTransport，
// 不再混用 v1+v2。
//
// 用法：
// ```dart
// RelaySnapshotWidget(
//   relayUrl: 'http://...',
//   maxPlayers: 2,
//   onRoomReady: (handle, transport) {
//     // handle 已连接 snapshot 流，可直接进入 chat 页
//   },
// )
// ```

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'relay_snapshot_transport.dart';

/// 房间就绪回调 — handle 已连接 WS + 已订阅 snapshot/<code>
typedef SnapshotRoomReadyCallback = void Function(
  RoomHandle handle,
  RelaySnapshotTransport transport,
);

/// 通用房间 widget（v2 snapshot 协议）
///
/// - **房主模式**：选人数 → 建房 → 直接进入 chat（无 handoff）
/// - **玩家模式**：输入房号 → 加入 → 直接进入 chat
///
/// [maxPlayers] 房间人数上限（房主模式可调，玩家模式由后端返回）
/// [onRoomReady] 房间就绪后回调（handle 已连接 snapshot 流 + 已 subscribe）
class RelaySnapshotWidget extends StatefulWidget {
  const RelaySnapshotWidget({
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
  final SnapshotRoomReadyCallback onRoomReady;

  @override
  State<RelaySnapshotWidget> createState() => _RelaySnapshotWidgetState();
}

enum _Stage { select, waiting }

class _RelaySnapshotWidgetState extends State<RelaySnapshotWidget> {
  _Stage _stage = _Stage.select;
  bool _isHost = true;

  // 房主配置
  int _maxPlayers = 2;

  // 玩家输入
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();

  // 连接状态
  RelaySnapshotTransport? _transport;
  RoomHandle? _handle;
  String? _roomCode;
  bool _busy = false;
  String? _error;

  static const _kAliasPref = 'relay_snapshot.alias';

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
    _handle?.dispose();
    _transport?.close();
    super.dispose();
  }

  // ——— 房主 ———

  Future<void> _createRoom() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '房主' : _aliasCtrl.text.trim();
    setState(() { _busy = true; _error = null; });
    try {
      await _saveAlias(alias);
      final t = RelaySnapshotTransport(relayUrl: widget.relayUrl, alias: alias);
      final handle = await t.createRoom(maxPlayers: _maxPlayers);
      _transport = t;
      _handle = handle;
      _roomCode = handle.code;
      setState(() { _busy = false; _stage = _Stage.waiting; });
      // 立即通知上层进入 chat 页（v2 协议无 handoff）
      widget.onRoomReady(handle, t);
    } catch (e) {
      setState(() { _busy = false; _error = '创建失败: $e'; });
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
      await _saveAlias(alias);
      final t = RelaySnapshotTransport(relayUrl: widget.relayUrl, alias: alias);
      final handle = await t.joinRoom(code);
      _transport = t;
      _handle = handle;
      _roomCode = code;
      setState(() { _busy = false; _stage = _Stage.waiting; });
      // 立即通知上层进入 chat 页（v2 协议无 handoff）
      widget.onRoomReady(handle, t);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().contains('404') ? '房间不存在' : '加入失败: $e';
      });
    }
  }

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
                OutlinedButton.icon(
                  onPressed: _busy ? null : _createRoom,
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
                OutlinedButton.icon(
                  onPressed: _busy ? null : _joinRoom,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text('加入房间'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
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
    // 等待页：显示房间号 + 加载中 + 自动 handoff 到 chat 页
    // （通常 onRoomReady 已经在 _createRoom/_joinRoom 异步路径里立即调用，
    //   此处只在异常兜底）
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_isHost ? '已创建' : '已加入'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('分享房间号给玩家', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 24),
              ],
              const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 12),
              Text('正在进入聊天...', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}