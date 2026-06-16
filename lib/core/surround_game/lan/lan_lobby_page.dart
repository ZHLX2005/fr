// lib/core/surround_game/lan/lan_lobby_page.dart
//
// 局域网模式"建房前"入口页 — 仅当用户在 lobby 选完"局域网对局"后进入。
//
// 本轮改造：
// - 进入时自动启动 adapter（如无已保存 alias 则显示页内编辑字段）
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

    // 无已保存 alias → 自动启动 adapter（用默认名），并聚焦输入框
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

  /// 失焦时保存 alias 并同步到 adapter
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
    // 建房前确保 alias 已保存
    _onAliasSubmitted(_aliasCtrl.text);
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
          // 本机名称编辑区 — 页内内联编辑
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.person, size: 28, color: theme.colorScheme.primary),
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: boardTheme.btnText,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            hintText: '输入你的名称',
                            hintStyle: TextStyle(
                              color: boardTheme.btnSub.withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: boardTheme.btnBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: boardTheme.btnBorder.withValues(alpha: 0.4),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          maxLength: 16,
                          // 实时更新「创建房间」按钮状态
                          onChanged: (_) => setState(() {}),
                          // 失焦或按回车时保存
                          onSubmitted: _onAliasSubmitted,
                          onEditingComplete: () {
                            _onAliasSubmitted(_aliasCtrl.text);
                            _aliasFocus.unfocus();
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
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
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: boardTheme.btnSub,
                            ),
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
                onPressed: _hasValidAlias ? _onCreateRoom : null,
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
