// lib/core/surround_game/lan/lan_lobby_page.dart
//
// 局域网模式"建房前"入口页 — 仅当用户在 lobby 选完"局域网对局"后进入。
//
// 本轮改造：
// - 进入时弹 aliasDialog 取本机名称
// - 启动 LanServiceAdapter.instance
// - 房间列表由 framework 发现的 HostRoomAnnounced 事件填充
// - 错误流（adapter 启动失败 / 协议解析失败）以 SnackBar 展示
// - dispose: 取消所有订阅 + adapter.stop()
//
// 此页是 LanHostViewModel 的持有者（建房状态机）。
// LanClient 流程不经过此页（客户端进 LanRoomPage(role: 'client') 直接选房）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../models/game_room.dart';
import 'lan_room_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'profile/alias_dialog.dart';
import 'persistence/player_profile_service.dart';
import 'service/lan_service_adapter.dart';
import 'protocol/lan_messages.dart';
import '../../localnet/device/device.dart' show Device;

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  late final LanHostViewModel _vm;
  StreamSubscription<LanRoomEvent>? _roomSub;
  StreamSubscription<List<Device>>? _deviceSub;
  StreamSubscription<LanServiceError>? _errorSub;
  String _alias = '';
  List<Device> _devices = const [];
  List<HostRoomAnnounced> _rooms = const [];
  bool _adapterStarted = false;

  @override
  void initState() {
    super.initState();
    _vm = LanHostViewModel();
    // 等第一帧渲染后再弹 dialog，避免 initState 中 context 未 attach 导致 showDialog 静默失败
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final savedAlias = await PlayerProfileService.loadAlias();
    if (!mounted) return;

    // 已有 alias → 直接用，不弹 dialog
    if (savedAlias != null && savedAlias.isNotEmpty) {
      await _startAdapter(alias: savedAlias);
      return;
    }

    // 首次 → 弹 dialog
    final alias = await AliasDialog.show(context, initialAlias: null);
    if (!mounted) return;
    if (alias == null || alias.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    await _startAdapter(alias: alias);
  }

  Future<void> _startAdapter({String? alias}) async {
    if (alias != null) {
      setState(() => _alias = alias);
    }
    try {
      // alias 为 null 时由 adapter 内部使用持久化值（T3 已支持）
      await LanServiceAdapter.instance.start(myAlias: alias);
      if (!mounted) return;
      setState(() => _adapterStarted = true);
      // 订阅（adapter 启动成功后才订阅）
      _roomSub =
          LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
      _deviceSub =
          LanServiceAdapter.instance.watchDevices().listen(_onDeviceEvent);
      _errorSub =
          LanServiceAdapter.instance.watchErrors().listen(_onError);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('框架启动失败: $e')),
        );
      }
    }
  }

  void _onRoomEvent(LanRoomEvent ev) {
    if (ev is HostRoomAnnounced) {
      setState(() {
        _rooms = [
          ..._rooms.where((r) => r.room.roomId != ev.room.roomId),
          ev,
        ];
      });
    }
  }

  void _onDeviceEvent(List<Device> devices) {
    setState(() => _devices = devices);
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  void _onCreateRoom() {
    _vm.dispatch(const HostCreateRoomPressed());
    final state = _vm.value;
    final roomId = state is HostWaiting ? state.room.roomId : 'new';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: roomId,
          role: 'host',
          initialRoom: state is HostWaiting
              ? state.room
              : GameRoom.placeholder(roomId: roomId),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _deviceSub?.cancel();
    _errorSub?.cancel();
    _vm.dispose();
    if (_adapterStarted) {
      LanServiceAdapter.instance.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boardTheme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: boardTheme.boardSurface,
      appBar: AppBar(
        title: const Text('局域网对局'),
        backgroundColor: boardTheme.panelBg,
        foregroundColor: boardTheme.btnText,
        actions: [
          if (_adapterStarted)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_devices.length} 设备',
                  style: TextStyle(color: boardTheme.btnSub, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 本机状态
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.person, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('本机: $_alias', style: theme.textTheme.titleMedium),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _adapterStarted
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _adapterStarted ? '已连接' : '启动中...',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 创建房间按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _adapterStarted ? _onCreateRoom : null,
                icon: const Icon(Icons.add),
                label: const Text('创建房间'),
                style: FilledButton.styleFrom(
                  backgroundColor: boardTheme.piecePlayerA,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // 房间列表
          Expanded(child: _buildRoomList(theme, boardTheme)),
        ],
      ),
    );
  }

  Widget _buildRoomList(ThemeData theme, BoardThemeData boardTheme) {
    if (_rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_find,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '暂无可用房间',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              _devices.isEmpty
                  ? '等待其他设备上线...'
                  : '等待房间广播...',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _rooms.length,
      itemBuilder: (ctx, i) {
        final r = _rooms[i];
        return ListTile(
          leading: const Icon(Icons.meeting_room),
          title: Text('${r.hostAlias} 的房间'),
          subtitle: Text('ID: ${r.room.roomId}'),
          onTap: () {
            // 把 r.hostDeviceId（真 deviceId）写进 room.hostId，让 Client 端
            // sendJoinRequest 拿到的 hostDeviceId 是真值（不是 placeholder 的 'host' 字面量）
            final realRoom = r.room.copyWith(
              hostId: r.hostDeviceId,
              hostName: r.hostAlias,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LanRoomPage(
                  roomId: r.room.roomId,
                  role: 'client',
                  initialRoom: realRoom,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
