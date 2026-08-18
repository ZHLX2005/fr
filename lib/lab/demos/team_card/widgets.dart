// lib/lab/demos/team_card/widgets.dart
// 团建卡牌 — UI 组件

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';

import '../../../core/net_engine/relay_v3/relay_device_id.dart';

import 'constants.dart';
import 'engine.dart';
import '../../../widgets/context_game_colors.dart';

// ══════════════════════════════════════════════════════════════
// Setup Page（房主建房前）
// ══════════════════════════════════════════════════════════════

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.initialRoles, required this.onStarted});
  final List<RoleDef> initialRoles;
  final void Function(RoomHandle, int capacity) onStarted;

  @override State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final List<RoleDef> rolePool = [];
  final _aliasCtrl = TextEditingController();
  int _playerSlots = 4;
  int _spectatorSlots = 0;
  bool _busy = false;
  bool _loaded = false;
  String? _error;
  /// 用户命名预设库：`{ playerSlots: [NamedPreset, ...] }`
  Map<int, List<NamedPreset>> _presetLib = {};

  @override
  void initState() {
    super.initState();
    // 别名
    AliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
    // 预设库
    PresetLibrary.load().then((lib) {
      if (mounted) setState(() => _presetLib = lib);
    });
    // 恢复上次配置（数值 + 角色池）
    SetupPrefs.load().then((s) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (s != null) {
          _playerSlots = s.playerSlots;
          _spectatorSlots = s.spectatorSlots;
          rolePool
            ..clear()
            ..addAll(s.roles);
        } else {
          rolePool
            ..clear()
            ..addAll(widget.initialRoles
                .map((r) => RoleDef(label: r.label, count: r.count)));
        }
      });
    });
  }

  @override
  void dispose() {
    _persistSetup();
    _aliasCtrl.dispose();
    for (final r in rolePool) {
      r.dispose();
    }
    super.dispose();
  }

  /// 角色池总数量
  int get _totalRoles => rolePool.fold(0, (s, r) => s + r.count);

  /// 持久化当前配置（数值 + 角色池）
  void _persistSetup() {
    if (!_loaded) return;
    for (final r in rolePool) {
      r.sync();
    }
    // 深拷贝一份 RoleDef（避免 dispose 后 controller 无法读）
    final snapshot = rolePool.map((r) => RoleDef(label: r.label, count: r.count)).toList();
    SetupPrefs.save(SetupState(
      playerSlots: _playerSlots,
      spectatorSlots: _spectatorSlots,
      roles: snapshot,
    ));
    // controller 无用后释放
    for (final r in snapshot) {
      r.dispose();
    }
  }

  void _applyBuiltinPreset(RolePreset p) {
    for (final r in rolePool) {
      r.dispose();
    }
    rolePool
      ..clear()
      ..addAll(p.toRoleDefs());
    setState(() {});
    _persistSetup();
  }

  void _applyNamedPreset(NamedPreset p) {
    for (final r in rolePool) {
      r.dispose();
    }
    rolePool
      ..clear()
      ..addAll(p.toRoleDefs());
    setState(() {});
    _persistSetup();
  }

  Future<void> _saveNamedPreset() async {
    for (final r in rolePool) {
      r.sync();
    }
    // 弹对话框询问预设名
    final name = await _promptPresetName();
    if (name == null || name.trim().isEmpty) return;
    final lib = await PresetLibrary.add(
      playerSlots: _playerSlots,
      preset: NamedPreset.fromRoleDefs(name.trim(), rolePool),
    );
    if (!mounted) return;
    setState(() => _presetLib = lib);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('预设 "${name.trim()}" 已保存到 $_playerSlots 人分组'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _deleteNamedPreset(NamedPreset p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('删除 "${p.name}"？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;
    final lib = await PresetLibrary.remove(playerSlots: _playerSlots, name: p.name);
    if (!mounted) return;
    setState(() => _presetLib = lib);
  }

  Future<String?> _promptPresetName() async {
    final ctrl = TextEditingController();
    final existing = _presetLib[_playerSlots]?.map((p) => p.name).toList() ?? [];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为预设'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '预设名（如：狼人杀 6 人版）',
                border: OutlineInputBorder(),
              ),
            ),
            if (existing.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('已有预设：${existing.join('、')}',
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(ctx).colorScheme.outline)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    for (final r in rolePool) {
      r.sync();
    }
    final alias = _aliasCtrl.text.trim().isEmpty ? '房主' : _aliasCtrl.text.trim();
    await AliasPrefs.save(alias);
    _persistSetup();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kTeamCardRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      final roles = rolePool.map((r) => {'label': r.label, 'count': r.count}).toList();
      final total = _playerSlots + _spectatorSlots;
      final h = await TeamCardRoom.create(t,
        playerSlots: _playerSlots,
        spectatorSlots: _spectatorSlots,
        roles: roles,
        alias: alias,
      );
      if (!mounted) return;
      widget.onStarted(h, total);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return Center(child: CircularProgressIndicator());
    }
    // 匹配当前 playerSlots 的内置 + 用户预设
    final matchedBuiltin =
        kBuiltinPresets.where((p) => p.total == _playerSlots).toList();
    final myPresets = _presetLib[_playerSlots] ?? const [];
    final total = _playerSlots + _spectatorSlots;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ——— 房间容量 ———
        Text('房间容量', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 12),
        _SlotStepper(
          label: '玩家区',
          icon: Icons.people,
          value: _playerSlots,
          min: 1,
          onChanged: (v) {
            setState(() => _playerSlots = v);
            _persistSetup();
          },
        ),
        SizedBox(height: 8),
        _SlotStepper(
          label: '旁观区',
          icon: Icons.remove_red_eye_outlined,
          value: _spectatorSlots,
          min: 0,
          onChanged: (v) {
            setState(() => _spectatorSlots = v);
            _persistSetup();
          },
        ),
        SizedBox(height: 4),
        Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('共 $total 人',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: theme.colorScheme.onPrimaryContainer)),
          ),
        ),
        SizedBox(height: 20),

        // ——— 身份池 ———
        Row(
          children: [
            Text('身份池', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _totalRoles == _playerSlots
                    ? '共 $_totalRoles 人 ✓'
                    : (_totalRoles < _playerSlots
                        ? '还差 ${_playerSlots - _totalRoles} 人'
                        : '超出 ${_totalRoles - _playerSlots} 人'),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _totalRoles == _playerSlots
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.error),
              ),
            ),
          ],
        ),
        if (_totalRoles != _playerSlots)
          Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              _totalRoles < _playerSlots
                  ? '至少需要 $_playerSlots 张身份牌（匹配玩家区人数）'
                  : '身份牌 ($_totalRoles) 超出玩家区人数 ($_playerSlots) 了',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
            ),
          ),

        // ——— 预设区（内置 + 用户命名 + 空态提示） ———
        SizedBox(height: 12),
        Text('快速预设（$_playerSlots 人）',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
        SizedBox(height: 6),
        if (matchedBuiltin.isEmpty && myPresets.isEmpty)
          Text('当前人数下暂无预设，编辑好后点保存按钮起个名字存起来',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, fontStyle: FontStyle.italic))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...matchedBuiltin.map((p) => _PresetChip(
                    label: p.name,
                    onTap: () => _applyBuiltinPreset(p),
                    theme: theme,
                  )),
              ...myPresets.map((p) => _PresetChip(
                    label: p.name,
                    onTap: () => _applyNamedPreset(p),
                    onDelete: () => _deleteNamedPreset(p),
                    theme: theme,
                    isCustom: true,
                  )),
            ],
          ),
        SizedBox(height: 12),
        ...rolePool.asMap().entries.map((e) => _RoleRow(
              index: e.key,
              def: e.value,
              canRemove: rolePool.length > 1,
              onChanged: () {
                setState(() {});
                _persistSetup();
              },
              onRemove: () {
                setState(() {
                  e.value.dispose();
                  rolePool.removeAt(e.key);
                });
                _persistSetup();
              },
            )),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => rolePool.add(RoleDef(label: '', count: 1)));
                    _persistSetup();
                  },
                  icon: Icon(Icons.add, size: 18),
                  label: const Text('添加身份'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _totalRoles == _playerSlots ? _saveNamedPreset : null,
                icon: Icon(Icons.save_outlined, size: 16),
                label: const Text('保存预设', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 4),
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(
            labelText: '你的名字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => AliasPrefs.save(v.trim()),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
        SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy || _totalRoles != _playerSlots ? null : _create,
          icon: _busy
              ? SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.meeting_room),
          label: Text(_busy ? '创建中…' : '创建房间'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(
              color: _busy ? theme.colorScheme.outlineVariant : theme.colorScheme.primary,
              width: 1.5,
            ),
            foregroundColor: _busy ? theme.colorScheme.outline : theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Join Page（玩家加入）
// ══════════════════════════════════════════════════════════════

class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.onStarted});
  final void Function(RoomHandle, int capacity) onStarted;

  @override State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '房间码 6 位');
      return;
    }
    await AliasPrefs.save(alias);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kTeamCardRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      final h = await TeamCardRoom.join(t, code: code);
      if (!mounted) return;
      widget.onStarted(h, 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(32, 32, 32, 32),
      children: [
        Icon(Icons.vpn_key_outlined,
            size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
        SizedBox(height: 16),
        Text('加入房间',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: 32),
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(
            labelText: '你的名字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          decoration: InputDecoration(
            labelText: '房间码',
            hintText: '6 位数字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.tag),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
        SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _join,
          icon: _busy
              ? SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.login),
          label: Text(_busy ? '加入中…' : '加入'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(
              color: _busy ? theme.colorScheme.outlineVariant : theme.colorScheme.primary,
              width: 1.5,
            ),
            foregroundColor: _busy ? theme.colorScheme.outline : theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Playing View（snapshot 驱动主视图）
// ══════════════════════════════════════════════════════════════

class PlayingView extends StatefulWidget {
  const PlayingView({
    super.key,
    required this.handle,
    required this.hostCapacity,
    required this.onLeave,
  });
  final RoomHandle handle;
  final int hostCapacity;
  final Future<void> Function() onLeave;

  @override State<PlayingView> createState() => _PlayingViewState();
}

class _PlayingViewState extends State<PlayingView> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  late TeamCardRoom _engine;
  bool _isHost = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _snap = widget.handle.latest;
    _engine = TeamCardRoom(widget.handle);
    _isHost = _engine.isHost;
    _sub = widget.handle.snapshots.listen((s) {
      if (!mounted) return;
      setState(() => _snap = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _amSpectator => myZone(_snap, widget.handle.transport.deviceId) == 'spectator';
  bool get _isMeReady {
    final s = _snap;
    if (s == null) return false;
    final ready = s.context['ready'];
    if (ready is! Map) return false;
    return ready[widget.handle.transport.deviceId] == true;
  }

  /// 发牌：先起翻牌音效（fire-and-forget），再走引擎 DEAL。
  Future<void> _onDeal() async {
    // ignore: discard_futures
    DealingCardsSound.play();
    await _engine.deal();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    final state = s?.state ?? 'lobby';
    if (state == 'playing') {
      final role = myRole(_snap, widget.handle.transport.deviceId);
      final zone = myZone(_snap, widget.handle.transport.deviceId);
      if (zone == 'player' && role != null) {
        return _IdentityCard(role: role, alias: widget.handle.transport.alias);
      }
      if (zone == 'spectator') {
        return SpectatorView(
          players: extractStringMap(_snap, 'players'),
          zoneMap: extractStringMap(_snap, 'zones'),
          assignments: extractDynamicMap(_snap, 'assignments'),
          onLeave: widget.onLeave,
        );
      }
      return Center(child: Text('已发牌'));
    }

    // lobby / ready
    return LobbyView(
      snap: s,
      isHost: _isHost,
      busy: _busy,
      onAck: _amSpectator ? null : _engine.ack,
      onUnack: _amSpectator ? null : _engine.unack,
      onDeal: _onDeal,
      onReset: _engine.reset,
      onMoveZone: _amSpectator
          ? () => _engine.sit(zone: 'player')
          : () => _engine.sit(zone: 'spectator'),
      onLeave: widget.onLeave,
      players: extractStringMap(_snap, 'players'),
      zoneMap: extractStringMap(_snap, 'zones'),
      playerSlots: extractInt(_snap, 'player_slots'),
      spectatorSlots: extractInt(_snap, 'spectator_slots'),
      readyMap: extractReadyMap(_snap),
      myReady: _isMeReady,
      myZone: myZone(_snap, widget.handle.transport.deviceId),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Lobby View（大厅 + 双区）
// ══════════════════════════════════════════════════════════════

class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.snap,
    required this.isHost,
    required this.busy,
    required this.onAck,
    required this.onUnack,
    required this.onDeal,
    required this.onReset,
    required this.onMoveZone,
    required this.onLeave,
    required this.players,
    required this.zoneMap,
    required this.playerSlots,
    required this.spectatorSlots,
    required this.readyMap,
    required this.myReady,
    required this.myZone,
  });

  final Snapshot? snap;
  final bool isHost, busy;
  final VoidCallback? onAck, onUnack;
  final Future<void> Function() onDeal, onReset;
  final VoidCallback? onMoveZone;
  final Future<void> Function() onLeave;
  final Map<String, String> players, zoneMap;
  final int playerSlots, spectatorSlots;
  final Map<String, bool> readyMap;
  final bool myReady;
  /// 当前所在区 "player" / "spectator" / null
  final String? myZone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = snap?.roomCode ?? '------';
    final state = snap?.state ?? 'lobby';
    final pCount = zoneMap.values.where((z) => z == 'player').length;
    final readyCount = readyMap.values.where((v) => v).length;
    final allReady = state == 'ready';
    final canDeal = isHost && allReady;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Center(child: _RoomCodeBadge(code: code, theme: theme)),
        SizedBox(height: 12),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state == 'ready'
                    ? '已就绪 · 房主可以开始'
                    : (pCount < playerSlots
                        ? '玩家区 $pCount / $playerSlots · 还差 ${playerSlots - pCount} 人'
                        : (readyCount < pCount
                            ? '等待 ${pCount - readyCount} 人准备…'
                            : '等待房主开始…')),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: state == 'ready'
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  fontWeight: state == 'ready' ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              SizedBox(height: 4),
              LinearProgressIndicator(
                  value: playerSlots == 0 ? 0 : pCount / playerSlots),
            ],
          ),
        ),
        SizedBox(height: 24),
        // 玩家区卡片
        _LobbyZoneCard(
          title: '参与者',
          icon: Icons.people,
          slots: playerSlots,
          players: players,
          zoneMap: zoneMap,
          zoneFilter: 'player',
          readyMap: readyMap,
        ),
        // 旁观区卡片
        if (spectatorSlots > 0) ...[
          SizedBox(height: 12),
          _LobbyZoneCard(
            title: '旁观区',
            icon: Icons.remove_red_eye_outlined,
            slots: spectatorSlots,
            players: players,
            zoneMap: zoneMap,
            zoneFilter: 'spectator',
            readyMap: readyMap,
          ),
        ],
        SizedBox(height: 24),
        // ——— 操作按钮 ———
        if (onAck != null && onUnack != null) ...[
          if (myReady)
            OutlinedButton.icon(
              onPressed: onUnack,
              icon: Icon(Icons.cancel_outlined),
              label: Text('取消准备'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: Theme.of(context).colorScheme.tertiary, width: 1.5),
                foregroundColor: Theme.of(context).colorScheme.tertiary,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: onAck,
              icon: Icon(Icons.check_circle_outlined),
              label: Text('准备好了'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          SizedBox(height: 12),
        ],
        // 换区按钮 — 目标区颜色 + 目标区图标 + 从哪来到哪去
        if (onMoveZone != null && spectatorSlots > 0 && playerSlots > 0) ...[
          Builder(builder: (_) {
            final goingToPlayer = myZone != 'player';
            final targetIcon = goingToPlayer ? Icons.people : Icons.remove_red_eye_outlined;
            final targetLabel = goingToPlayer ? '去玩家区' : '去旁观区';
            final currentLabel = myZone == 'player'
                ? '当前：玩家'
                : (myZone == 'spectator' ? '当前：旁观' : '未入座');
            final tint = goingToPlayer ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.tertiary;
            return Material(
              color: tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onMoveZone,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tint.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(targetIcon, color: tint, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              targetLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: tint,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              currentLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: tint, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
          SizedBox(height: 12),
        ],
        if (isHost)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canDeal && !busy ? onDeal : null,
                  icon: Icon(
                    busy ? null : Icons.style,
                    color: canDeal && !busy ? theme.colorScheme.primary : null,
                  ),
                  label: Text(busy ? '发牌中…' : '开始发牌'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                      color: canDeal
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              OutlinedButton(
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  shape: const CircleBorder(),
                  side: BorderSide(color: Theme.of(context).colorScheme.tertiary, width: 1.5),
                  foregroundColor: Theme.of(context).colorScheme.tertiary,
                  minimumSize: const Size(52, 52),
                ),
                child: Icon(Icons.refresh),
              ),
            ],
          ),
        SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: onLeave,
            icon: Icon(Icons.exit_to_app),
            label: const Text('离开房间'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
              foregroundColor: theme.colorScheme.outline,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 身份卡（发牌后玩家区自己看到）
// ══════════════════════════════════════════════════════════════

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.role, required this.alias});
  final String role;
  final String alias;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = roleColor(theme, role);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.95, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
          child: SizedBox(
            width: 280,
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.style, size: 40, color: color),
                  ),
                  SizedBox(height: 24),
                  Text('你的身份',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline, letterSpacing: 2)),
                  SizedBox(height: 8),
                  Text(role,
                      style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
                  SizedBox(height: 12),
                  Container(
                    height: 3,
                    width: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text('只有你能看到这张卡',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 旁观者视图（发牌后看到所有人身份）
// ══════════════════════════════════════════════════════════════

class SpectatorView extends StatelessWidget {
  const SpectatorView({
    super.key,
    required this.players,
    required this.zoneMap,
    required this.assignments,
    required this.onLeave,
  });
  final Map<String, String> players;
  final Map<String, String> zoneMap;
  final Map<String, dynamic> assignments;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(children: [
              IconButton(icon: Icon(Icons.arrow_back), onPressed: onLeave),
              SizedBox(width: 4),
              Text('旁观模式 · 所有人身份',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 8),
            Text(
                '你不在分配名单 — 共 ${zoneMap.values.where((z) => z == 'player').length} 名玩家',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            SizedBox(height: 16),
            ...players.entries
                .where((e) => zoneMap[e.key] == 'player')
                .map((e) => Card(
                      elevation: 0,
                      margin: EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                  e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary)),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.value,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w500)),
                                SizedBox(height: 2),
                                Text(
                                  '身份: ${assignments[e.key]?.toString() ?? '?'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: roleColor(
                                        theme, assignments[e.key]?.toString() ?? ''),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    )),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 双区卡片
// ══════════════════════════════════════════════════════════════

class _LobbyZoneCard extends StatelessWidget {
  const _LobbyZoneCard({
    required this.title,
    required this.icon,
    required this.slots,
    required this.players,
    required this.zoneMap,
    required this.zoneFilter,
    required this.readyMap,
  });
  final String title;
  final IconData icon;
  final int slots;
  final Map<String, String> players, zoneMap;
  final String zoneFilter;
  final Map<String, bool> readyMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoneEntries = players.entries.where((e) => zoneMap[e.key] == zoneFilter).toList();
    final isSpectator = zoneFilter == 'spectator';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 14,
                    color: isSpectator
                        ? theme.colorScheme.outline
                        : Theme.of(context).colorScheme.primary),
                SizedBox(width: 6),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(width: 6),
                Text('${zoneEntries.length}/$slots',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 28,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: List.generate(slots, (i) {
                if (i < zoneEntries.length) {
                  final e = zoneEntries[i];
                  final color = context.gameColors.avatarColors[i % context.gameColors.avatarColors.length];
                  final isReady = readyMap[e.key] == true;
                  if (isSpectator) {
                    return _AnimatedSlot(
                      delay: i * 60,
                      child: _MiniAvatar(
                        slotSize: 56,
                        letter: e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                        color: theme.colorScheme.outline,
                        isSpectator: true,
                        name: e.value,
                        label: '旁观者',
                      ),
                    );
                  }
                  return _AnimatedSlot(
                    delay: i * 60,
                    child: _MiniAvatar(
                      slotSize: 56,
                      letter: e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                      color: color,
                      isReady: isReady,
                      name: e.value,
                      label: isReady ? '已准备' : '未准备',
                    ),
                  );
                }
                return _AnimatedSlot(delay: i * 60, child: _EmptySlot(slotSize: 56));
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 小头像圆环
// ══════════════════════════════════════════════════════════════

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({
    required this.slotSize,
    required this.letter,
    required this.color,
    this.isReady = false,
    this.isSpectator = false,
    required this.name,
    required this.label,
  });
  final double slotSize;
  final String letter;
  final Color color;
  final bool isReady, isSpectator;
  final String name, label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: slotSize,
          height: slotSize,
          decoration: BoxDecoration(
            gradient: isSpectator
                ? null
                : RadialGradient(
                    colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.08)],
                  ),
            shape: BoxShape.circle,
            border: Border.all(
              color: isReady
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)
                  : (isSpectator
                      ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                      : color.withValues(alpha: 0.35)),
              width: isReady ? 3.5 : (isSpectator ? 1.5 : 2.0),
            ),
            boxShadow: isReady
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: isSpectator
              ? Icon(Icons.person_outline,
                  size: slotSize * 0.45,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5))
              : Center(
                  child: Text(letter,
                      style: TextStyle(
                        fontSize: slotSize * 0.4,
                        fontWeight: FontWeight.bold,
                        color: isReady ? Theme.of(context).colorScheme.primary : color,
                      )),
                ),
        ),
        SizedBox(height: 4),
        Text(name,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isReady
                    ? Theme.of(context).colorScheme.primary
                    : (isSpectator
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6)))),
        Text(label,
            style: TextStyle(
                fontSize: 9,
                color: isReady
                    ? Theme.of(context).colorScheme.primary
                    : (isSpectator
                        ? theme.colorScheme.outline.withValues(alpha: 0.6)
                        : theme.colorScheme.outline))),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 飞入动画 slot
// ══════════════════════════════════════════════════════════════

class _AnimatedSlot extends StatefulWidget {
  final int delay;
  final Widget child;
  const _AnimatedSlot({required this.delay, required this.child});

  @override
  State<_AnimatedSlot> createState() => _AnimatedSlotState();
}

class _AnimatedSlotState extends State<_AnimatedSlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value.clamp(0.0, 1.0);
        return Transform.scale(scale: _anim.value, child: Opacity(opacity: v, child: child));
      },
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 空位呼吸圆环
// ══════════════════════════════════════════════════════════════

class _EmptySlot extends StatefulWidget {
  final double slotSize;
  const _EmptySlot({required this.slotSize});

  @override
  State<_EmptySlot> createState() => _EmptySlotState();
}

class _EmptySlotState extends State<_EmptySlot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _ctrl.repeat(reverse: true);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) =>
          Opacity(opacity: 0.4 + _ctrl.value * 0.3, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(Icons.person_add_alt_1,
                  size: 20, color: theme.colorScheme.outlineVariant),
            ),
          ),
          SizedBox(height: 4),
          Text('等待中',
              style: TextStyle(fontSize: 9, color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 通用小组件
// ══════════════════════════════════════════════════════════════

class _RoomCodeBadge extends StatelessWidget {
  const _RoomCodeBadge({required this.code, required this.theme});
  final String code;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
          SizedBox(width: 8),
          Text(code,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 6,
                color: theme.colorScheme.primary,
              )),
        ]),
      );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
    required this.theme,
    this.isCustom = false,
    this.onDelete,
  });
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isCustom;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (onDelete != null) {
      return InputChip(
        label: Text(label),
        avatar: Icon(Icons.person,
            size: 16, color: theme.colorScheme.onPrimaryContainer),
        onPressed: onTap,
        onDeleted: onDelete,
        deleteIcon: Icon(Icons.close, size: 16),
        backgroundColor: theme.colorScheme.primaryContainer,
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
      );
    }
    return ActionChip(
      label: Text(label),
      avatar: Icon(isCustom ? Icons.person : Icons.auto_awesome,
          size: 16,
          color: isCustom
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onTertiaryContainer),
      onPressed: onTap,
      backgroundColor: isCustom
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.tertiaryContainer,
      side: isCustom
          ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4))
          : BorderSide.none,
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.index,
    required this.def,
    required this.canRemove,
    required this.onRemove,
    this.onChanged,
  });
  final int index;
  final RoleDef def;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.onPrimaryContainer,
                  ))),
        ),
        SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: def.nameCtrl,
            decoration: InputDecoration(
              hintText: '身份名称',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              def.sync();
              onChanged?.call();
            },
          ),
        ),
        SizedBox(width: 8),
        _StepperButton(
          icon: Icons.remove,
          onTap: def.count > 1
              ? () {
                  def.count = def.count - 1;
                  def.countCtrl.text = def.count.toString();
                  onChanged?.call();
                }
              : null,
        ),
        SizedBox(
          width: 32,
          child: Center(
            child: Text('${def.count}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          onTap: () {
            def.count = def.count + 1;
            def.countCtrl.text = def.count.toString();
            onChanged?.call();
          },
        ),
        if (canRemove)
          IconButton(
            icon: Icon(Icons.remove_circle_outline,
                size: 20, color: theme.colorScheme.error),
            onPressed: onRemove,
          ),
      ]),
    );
  }
}

class _SlotStepper extends StatelessWidget {
  const _SlotStepper({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final int value, min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.outline),
        SizedBox(width: 10),
        Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        Spacer(),
        _StepperButton(
          icon: Icons.remove,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 44,
          child: Center(
            child: Text('$value',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          onTap: () => onChanged(value + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(
            color: onTap != null
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
          foregroundColor:
              onTap != null ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
