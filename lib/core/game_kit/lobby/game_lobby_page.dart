// lib/core/game_kit/lobby/game_lobby_page.dart
//
// GameLobbyPage —— Lua 联机游戏入口页通用壳。
//
// 两种 flow 类型：
//   · smartMatch：单按钮「进入对局」→ tryJoinOrCreate → 成功立即 onStarted
//   · dualEntry ：双按钮「创建房间」「加入房间」→ 创建路径 push 可选配置页 →
//                  tryJoinOrCreate → snapshot 门控 onStarted
//                  （state ∈ {lobby,ready,playing,ended}）
//
// 颜色统一走 Theme.of(context).colorScheme + context.colors，
// 不再让调用方传入 BoardTheme / chessColors —— 消灭入口页主题不一致。
//
// 对外契约：
//   · spec: GameLobbySpec (const 数据)
//   · slots: GameLobbySlots (可选插槽)
//   · onStarted(handle, ctx): 进入房间后回调
//   · demo 通过 returned GameLobbyHandle.resetToEntry() 在 pop 时重置

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/lua/lua_game_alias.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '_lobby_form.dart';
import 'game_lobby_slots.dart';
import 'game_lobby_spec.dart';

class GameLobbyPage extends StatefulWidget {
  final GameLobbySpec spec;
  final GameLobbySlots slots;
  final LobbyOnStarted onStarted;

  const GameLobbyPage({
    super.key,
    required this.spec,
    required this.slots,
    required this.onStarted,
  });

  @override
  State<GameLobbyPage> createState() => GameLobbyPageState();
}

/// State 暴露给外部的句柄（demo 用：resetToEntry）。
class GameLobbyPageState extends State<GameLobbyPage> {
  final TextEditingController _aliasCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  // dualEntry-only：
  _DualEntryPhase _phase = _DualEntryPhase.entry;
  RoomHandle? _handle;
  StreamSubscription<Snapshot>? _snapSub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    _snapSub?.cancel();
    super.dispose();
  }

  /// 暴露给 demo / parent widget 的句柄获取点（用于 push 后续页面时调用）。
  GameLobbyHandle get exposed => GameLobbyHandle(
        handle: _handle,
        resetToEntry: _resetToEntry,
      );

  // —————— 验证 ——————

  ({String alias, String code})? _validateAndExtract() {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return null;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    final codeError = RoomCodeRules.validate(
      code,
      minLen: widget.spec.minCodeLength,
      maxLen: widget.spec.maxCodeLength,
    );
    if (codeError != null) {
      setState(() => _error = codeError);
      return null;
    }
    return (alias: alias, code: code);
  }

  // —————— smartMatch 流程 —————-

  Future<void> _goSmartMatch() async {
    final validated = _validateAndExtract();
    if (validated == null) return;
    final alias = validated.alias;
    final code = validated.code;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deviceId = await widget.spec.identityResolver.resolve();
      final t = widget.slots.transportBuilder?.call(alias, deviceId) ??
          RelayV3Transport(
            relayUrl: widget.spec.relayUrl,
            alias: alias,
            deviceId: deviceId,
          );
      await LuaGameAlias.save(alias);
      final initialParams = <String, dynamic>{
        'device_id': t.deviceId,
        'alias': alias,
      };
      // slots.onInitialParamsBuilder 可补充（多为 null）
      final extra =
          widget.slots.initialParamsBuilder?.call(LobbySubmitData(
        alias: alias,
        code: code,
      ), null);
      if (extra != null) initialParams.addAll(extra);

      final h = await t.tryJoinOrCreate(
        code: code,
        script: widget.spec.script,
        initialParams: initialParams,
        maxPlayers: widget.spec.maxPlayers,
      );
      if (!mounted) return;
      _handle = h;
      _started = true;
      setState(() => _busy = false);
      widget.onStarted(h, const LobbyStartedCtx());
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapEntryError(e, code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  // —————— dualEntry 流程 —————-

  Future<void> _goDualAsHost() async {
    final validated = _validateAndExtract();
    if (validated == null) return;
    final alias = validated.alias;
    final code = validated.code;
    Map<String, dynamic>? cfgResult;
    if (widget.slots.configPageBuilder != null) {
      cfgResult = await widget.slots.configPageBuilder!(
        context,
        data: LobbySubmitData(alias: alias, code: code),
      );
      if (cfgResult == null) return; // 用户取消
      if (!mounted) return;
    }
    await _submitDual(cfgResult, alias: alias, code: code);
  }

  Future<void> _goDualAsGuest() async {
    final validated = _validateAndExtract();
    if (validated == null) return;
    final alias = validated.alias;
    final code = validated.code;
    await _submitDual(null, alias: alias, code: code);
  }

  Future<void> _submitDual(
    Map<String, dynamic>? cfgResult, {
    required String alias,
    required String code,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deviceId = await widget.spec.identityResolver.resolve();
      final t = widget.slots.transportBuilder?.call(alias, deviceId) ??
          RelayV3Transport(
            relayUrl: widget.spec.relayUrl,
            alias: alias,
            deviceId: deviceId,
          );
      await LuaGameAlias.save(alias);
      final initialParams = <String, dynamic>{
        'device_id': t.deviceId,
        'alias': alias,
      };
      if (cfgResult != null) {
        // chess: host_color / first_mover / initial_fen
        initialParams.addAll(cfgResult);
      }
      // slots.initialParamsBuilder 可补充
      final extra = widget.slots.initialParamsBuilder?.call(
        LobbySubmitData(alias: alias, code: code),
        cfgResult,
      );
      if (extra != null) initialParams.addAll(extra);

      final h = await t.tryJoinOrCreate(
        code: code,
        script: widget.spec.script,
        initialParams: initialParams,
        maxPlayers: widget.spec.maxPlayers,
      );
      if (!mounted) return;
      _handle = h;
      _subscribeSnapshot(h);
      setState(() {
        _phase = _DualEntryPhase.room;
        _busy = false;
      });
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapEntryError(e, code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  void _subscribeSnapshot(RoomHandle h) {
    _snapSub?.cancel();
    _snapSub = h.snapshots.listen((snap) {
      if (!mounted) return;
      // dualEntry 门：state ∈ {lobby, ready, playing, ended} 都触发
      if (!_started &&
          (snap.state == 'lobby' ||
              snap.state == 'ready' ||
              snap.state == 'playing' ||
              snap.state == 'ended')) {
        _started = true;
        final ctx = LobbyStartedCtx();
        widget.slots.onStartedExtras?.call(ctx);
        widget.onStarted(h, ctx);
      }
    });
  }

  Future<void> _resetToEntry() async {
    _started = false;
    _snapSub?.cancel();
    _snapSub = null;
    final h = _handle;
    _handle = null;
    if (!mounted) return;
    setState(() {
      _phase = _DualEntryPhase.entry;
      _busy = false;
      _error = null;
    });
    await h?.dispose();
  }

  // —————— 共享错误映射 —————-

  String _mapEntryError(RelayV3Exception e, String code) {
    final body = e.body.toLowerCase();
    if (e.statusCode == 409 && body.contains('code collision')) {
      return '房间号 $code 已被占用，请换一个';
    }
    if (e.statusCode == 409 && body.contains('join rejected')) {
      return '房间 $code 已满员，无法加入';
    }
    if (e.statusCode == 404) {
      return '房间号 $code 不存在且创建失败';
    }
    return '进入失败（${e.statusCode}）';
  }

  // —————— Build —————-

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.spec.title),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          ...?widget.slots.actionsBuilder?.call(context),
          if (widget.spec.flow == LobbyFlowType.dualEntry &&
              _phase == _DualEntryPhase.room)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _resetToEntry,
              tooltip: '断开',
            ),
        ],
      ),
      body: SafeArea(
        child: switch (widget.spec.flow) {
          LobbyFlowType.smartMatch => _buildSmartMatchEntry(),
          LobbyFlowType.dualEntry =>
            _phase == _DualEntryPhase.entry
                ? _buildDualEntryEntry()
                : const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildSmartMatchEntry() {
    return LobbyForm(
      spec: widget.spec,
      aliasCtrl: _aliasCtrl,
      codeCtrl: _codeCtrl,
      busy: _busy,
      error: _error,
      showSecondaryButton: false,
      formExtras: widget.slots.formExtras,
      onPrimary: _busy ? () {} : _goSmartMatch,
    );
  }

  Widget _buildDualEntryEntry() {
    return LobbyForm(
      spec: widget.spec,
      aliasCtrl: _aliasCtrl,
      codeCtrl: _codeCtrl,
      busy: _busy,
      error: _error,
      showSecondaryButton: true,
      formExtras: widget.slots.formExtras,
      onPrimary: _busy ? () {} : _goDualAsHost,
      onSecondary: _busy ? () {} : _goDualAsGuest,
    );
  }
}

enum _DualEntryPhase { entry, room }