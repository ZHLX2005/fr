// lib/core/jungle_chess/lan/lan_lobby_page.dart
//
// 局域网模式"建房前"入口页。
//
// 进入时自动启动 adapter；房间列表由 framework 发现的 HostRoomAnnounced 事件填充。
// 错误流（adapter 启动失败 / 协议解析失败）以 SnackBar 展示。
// dispose：取消所有订阅 + adapter.stop()。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart' show Device;
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_room_page.dart';
import 'persistence/player_profile_service.dart';
import 'protocol/lan_messages.dart';
import 'service/lan_service_adapter.dart';
import 'game_room.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  late final LanHostViewModel _vm;
  late final TextEditingController _aliasCtrl;
  late final FocusNode _aliasFocus;
  StreamSubscription<LanRoomEvent>? _roomSub;
  StreamSubscription<List<Device>>? _deviceSub;
  StreamSubscription<LanServiceError>? _errorSub;
  List<Device> _devices = const [];
  List<HostRoomAnnounced> _rooms = const [];
  bool _adapterStarted = false;

  @override
  void initState() {
    super.initState();
    _vm = LanHostViewModel();
    _aliasCtrl = TextEditingController();
    _aliasFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final savedAlias = await PlayerProfileService.loadAlias();
    if (!mounted) return;

    if (savedAlias != null && savedAlias.isNotEmpty) {
      _aliasCtrl.text = savedAlias;
      await _startAdapter();
      return;
    }
    await _startAdapter();
    _aliasFocus.requestFocus();
  }

  Future<void> _startAdapter() async {
    try {
      await LanServiceAdapter.instance.start(myAlias: _aliasCtrl.text);
      if (!mounted) return;
      setState(() => _adapterStarted = true);
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

  void _onAliasSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    PlayerProfileService.saveAlias(trimmed);
    if (_adapterStarted) {
      LanServiceAdapter.instance.updateAlias(trimmed);
    }
  }

  bool get _hasValidAlias =>
      _aliasCtrl.text.trim().isNotEmpty && _adapterStarted;

  void _onRoomEvent(LanRoomEvent ev) {
    if (ev is HostRoomAnnounced) {
      setState(() {
        _rooms = [
          ..._rooms.where((r) => r.roomId != ev.roomId),
          ev,
        ];
      });
    } else if (ev is HostRoomClosed) {
      setState(() => _rooms = []);
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
    _onAliasSubmitted(_aliasCtrl.text);
    final roomId = DateTime.now().millisecondsSinceEpoch.toString();
    _vm.dispatch(HostCreateRoom(
      roomId: roomId,
      hostName: LanServiceAdapter.instance.myAlias,
    ));
    final state = _vm.value;
    final room = state is HostWaiting
        ? state.room
        : GameRoom(
            roomId: roomId,
            hostDeviceId: LanServiceAdapter.instance.myDeviceId,
            hostName: LanServiceAdapter.instance.myAlias,
          );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: room.roomId,
          role: 'host',
          initialRoom: room,
        ),
      ),
    );
  }

  void _onJoinRoom(HostRoomAnnounced ann) {
    final room = GameRoom(
      roomId: ann.roomId,
      hostDeviceId: ann.hostDeviceId,
      hostName: ann.hostName,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: ann.roomId,
          role: 'client',
          initialRoom: room,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _aliasFocus.dispose();
    _roomSub?.cancel();
    _deviceSub?.cancel();
    _errorSub?.cancel();
    _vm.dispose();
    _aliasCtrl.dispose();
    if (_adapterStarted) {
      LanServiceAdapter.instance.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('斗兽棋 - 局域网'),
        actions: [
          if (_adapterStarted)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_devices.length} 设备',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 本机名称编辑区
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.person, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _aliasCtrl,
                          focusNode: _aliasFocus,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6,
                            ),
                            hintText: '输入你的名称',
                            border: OutlineInputBorder(),
                          ),
                          maxLength: 16,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _onAliasSubmitted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: ShapeDecoration(
                              shape: const CircleBorder(),
                              color: _adapterStarted ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_adapterStarted ? '已连接' : '启动中...'),
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
                onPressed: _hasValidAlias ? _onCreateRoom : null,
                icon: const Icon(Icons.add),
                label: const Text('创建房间'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // 房间列表
          Expanded(child: _buildRoomList()),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    if (_rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_find, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '暂无可用房间',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _devices.isEmpty ? '等待其他设备上线...' : '等待房间广播...',
              style: Theme.of(context).textTheme.bodySmall,
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
          title: Text('${r.hostName} 的房间'),
          subtitle: Text('ID: ${r.roomId}'),
          onTap: () => _onJoinRoom(r),
        );
      },
    );
  }
}
