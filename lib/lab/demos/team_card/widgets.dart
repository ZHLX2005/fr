// lib/lab/demos/team_card/widgets.dart
// 团建卡牌 — UI 组件

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/game_audio/dealing_cards_sound.dart';

import '../../../core/net_engine/relay_v3/relay_device_id.dart';

import 'constants.dart';
import 'engine.dart';
import '../../../widgets/context_team_avatar_colors.dart';

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
      // Commit 2 中间过渡：SetupPage 用 tryJoinOrCreate 路径
      // （commit 3 会把 SetupPage/JoinPage 合并为单表单 LobbyEntryPage）
      final code = _generateCode();
      final h = await TeamCardRoom.tryJoinOrCreate(
        t,
        code: code,
        playerSlots: _playerSlots,
        spectatorSlots: _spectatorSlots,
        roles: roles,
        alias: alias,
      );
      if (!mounted) return;
      widget.onStarted(h, _playerSlots + _spectatorSlots);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// 临时生成 6 位数字房间码（commit 3 后由 LobbyEntryPage 的输入框替代）
  String _generateCode() {
    final r = DateTime.now().millisecondsSinceEpoch;
    final code = ((r % 900000) + 100000).toString();
    return code;
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
      // Commit 2 过渡：直接走 tryJoinOrCreate（已存在房间号走 join；不存在则创建失败）
      final h = await TeamCardRoom.tryJoinOrCreate(
        t,
        code: code,
        playerSlots: 6,
        spectatorSlots: 0,
        alias: alias,
      );
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

  @override
  void initState() {
    super.initState();
    _snap = widget.handle.latest;
    _engine = TeamCardRoom(widget.handle);
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

  /// 服务端权威的房主判定（来自 snapshot.context['host_id']）
  bool get _isHost => myIsHost(_snap, widget.handle.transport.deviceId);

  String? get _hostId => hostIdOf(_snap);

  /// 发牌：先起翻牌音效（fire-and-forget），再走引擎 START。
  Future<void> _onStart() async {
    // ignore: discard_futures
    DealingCardsSound.play();
    await _engine.start();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    final state = s?.state ?? 'lobby';
    if (state == 'playing') {
      final role = myRole(_snap, widget.handle.transport.deviceId);
      final zone = myZone(_snap, widget.handle.transport.deviceId);
      if (zone == 'host') {
        return HostView(
          players: extractStringMap(_snap, 'players'),
          zoneMap: extractStringMap(_snap, 'zones'),
          assignments: extractDynamicMap(_snap, 'assignments'),
          hostMessages: extractHostMessages(_snap),
          onSend: (to, text) => _engine.hostSend(to: to, text: text),
          onLeave: widget.onLeave,
        );
      }
      if (zone == 'player' && role != null) {
        return PlayerPlayingView(
          role: role,
          alias: widget.handle.transport.alias,
          hostMessages: myHostMessages(_snap, widget.handle.transport.deviceId),
          onLeave: widget.onLeave,
        );
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

    // lobby
    return LobbyView(
      snap: s,
      isHost: _isHost,
      busy: false,
      onStart: _onStart,
      onReset: _engine.reset,
      onSit: (zone) => _engine.sit(zone: zone),
      onLeave: widget.onLeave,
      players: extractStringMap(_snap, 'players'),
      zoneMap: extractStringMap(_snap, 'zones'),
      playerSlots: extractInt(_snap, 'player_slots'),
      spectatorSlots: extractInt(_snap, 'spectator_slots'),
      hostId: _hostId,
      myZone: myZone(_snap, widget.handle.transport.deviceId),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Lobby View（大厅 + 三区：host/player/spectator）
// ══════════════════════════════════════════════════════════════

class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.snap,
    required this.isHost,
    required this.busy,
    required this.onStart,
    required this.onReset,
    required this.onSit,
    required this.onLeave,
    required this.players,
    required this.zoneMap,
    required this.playerSlots,
    required this.spectatorSlots,
    required this.hostId,
    required this.myZone,
  });

  final Snapshot? snap;
  final bool isHost, busy;
  final Future<void> Function() onStart, onReset;
  /// SIT（换区）回调。参数是目标区名 host/player/spectator。
  final void Function(String zone) onSit;
  final Future<void> Function() onLeave;
  final Map<String, String> players, zoneMap;
  final int playerSlots, spectatorSlots;
  final String? hostId;
  /// 当前所在区 "host" / "player" / "spectator" / null
  final String? myZone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = snap?.roomCode ?? '------';
    final state = snap?.state ?? 'lobby';
    final pCount = zoneMap.values.where((z) => z == 'player').length;
    final canStart = isHost && pCount == playerSlots && state == 'lobby';

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
                state == 'playing'
                    ? '游戏中 · 等待下一局'
                    : (pCount < playerSlots
                        ? '玩家区 $pCount / $playerSlots · 还差 ${playerSlots - pCount} 人'
                        : '玩家区满 · 房主可开始'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: state == 'playing'
                      ? theme.colorScheme.tertiary
                      : (canStart
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline),
                  fontWeight: canStart ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              SizedBox(height: 4),
              LinearProgressIndicator(
                  value: playerSlots == 0 ? 0 : pCount / playerSlots),
            ],
          ),
        ),
        SizedBox(height: 24),

        // 主持区（容量 1，可空）
        _LobbyZoneCard(
          title: '主持区',
          icon: Icons.workspace_premium,
          slots: 1,
          players: players,
          zoneMap: zoneMap,
          zoneFilter: 'host',
          hostId: hostId,
        ),
        SizedBox(height: 12),
        // 玩家区（必须满员才能开局）
        _LobbyZoneCard(
          title: '玩家区',
          icon: Icons.people,
          slots: playerSlots,
          players: players,
          zoneMap: zoneMap,
          zoneFilter: 'player',
          hostId: hostId,
        ),
        SizedBox(height: 12),
        // 旁观区（slots=0 表示无限）
        _LobbyZoneCard(
          title: '旁观区',
          icon: Icons.remove_red_eye_outlined,
          slots: spectatorSlots,
          players: players,
          zoneMap: zoneMap,
          zoneFilter: 'spectator',
          hostId: hostId,
        ),
        SizedBox(height: 24),

        // ——— 换区按钮（房主：host ↔ player；玩家：player → spectator）———
        if ((myZone == 'host' || myZone == 'player' || myZone == 'spectator') &&
            state == 'lobby')
          _SitButton(
            myZone: myZone,
            isHost: isHost,
            playerFull: pCount >= playerSlots,
            spectatorFull: spectatorSlots > 0 &&
                zoneMap.values.where((z) => z == 'spectator').length >=
                    spectatorSlots,
            onSit: onSit,
          ),

        // ——— START 按钮（房主 + 玩家区满）——
        if (isHost)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canStart && !busy ? onStart : null,
                  icon: Icon(
                    busy ? null : Icons.style,
                    color: canStart && !busy ? theme.colorScheme.primary : null,
                  ),
                  label: Text(busy
                      ? '发牌中…'
                      : (canStart ? '开始发牌' : '等待玩家区满员')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                      color: canStart
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
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.tertiary, width: 1.5),
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
// 换区按钮（lobby 阶段，按规则显示可去的区）
// ══════════════════════════════════════════════════════════════

class _SitButton extends StatelessWidget {
  const _SitButton({
    required this.myZone,
    required this.isHost,
    required this.playerFull,
    required this.spectatorFull,
    required this.onSit,
  });
  final String? myZone;
  final bool isHost;
  final bool playerFull;
  final bool spectatorFull;
  final void Function(String zone) onSit;

  @override
  Widget build(BuildContext context) {
    // 房主可以 host ↔ player；其他人可以 player ↔ spectator
    final targets = <(String zone, String label, IconData icon, Color tint)>[];
    if (myZone == 'host') {
      targets.add(('player', '去玩家区参与游戏', Icons.people,
          Theme.of(context).colorScheme.primary));
    } else if (myZone == 'player') {
      if (isHost) {
        targets.add(('host', '回到主持区', Icons.workspace_premium,
            Colors.amber.shade700));
      }
      if (!spectatorFull) {
        targets.add(('spectator', '去旁观区', Icons.remove_red_eye_outlined,
            Theme.of(context).colorScheme.tertiary));
      }
    } else if (myZone == 'spectator') {
      if (!playerFull) {
        targets.add(('player', '回到玩家区', Icons.people,
            Theme.of(context).colorScheme.primary));
      }
    }
    if (targets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: targets.map((t) {
          return OutlinedButton.icon(
            onPressed: () => onSit(t.$1),
            icon: Icon(t.$3, size: 16, color: t.$4),
            label: Text(t.$2,
                style: TextStyle(color: t.$4, fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: t.$4.withValues(alpha: 0.5), width: 1.2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 玩家游戏界面（发牌后看自己的身份 + 收主持人私信）
// ══════════════════════════════════════════════════════════════

class PlayerPlayingView extends StatelessWidget {
  const PlayerPlayingView({
    super.key,
    required this.role,
    required this.alias,
    required this.hostMessages,
    required this.onLeave,
  });
  final String role;
  final String alias;
  final List<Map<String, dynamic>> hostMessages;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = roleColor(theme, role);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(children: [
              IconButton(icon: Icon(Icons.arrow_back), onPressed: onLeave),
              SizedBox(width: 4),
              Text('你的身份',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 24),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.95, end: 1),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: SizedBox(
                  width: 280,
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(
                          color: color.withValues(alpha: 0.3), width: 2),
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
                                color: theme.colorScheme.outline,
                                letterSpacing: 2)),
                        SizedBox(height: 8),
                        Text(role,
                            style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: color,
                                letterSpacing: 1)),
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
                        Text('玩家名：$alias',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            if (hostMessages.isNotEmpty) ...[
              SizedBox(height: 24),
              _HostMessageList(messages: hostMessages),
            ],
          ],
        ),
      ),
    );
  }
}

class _HostMessageList extends StatelessWidget {
  const _HostMessageList({required this.messages});
  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.shade300, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.workspace_premium,
                  size: 16, color: Colors.amber.shade700),
              SizedBox(width: 6),
              Text('主持人消息',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 8),
            ...messages.map((m) => Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(m['text']?.toString() ?? '',
                      style: theme.textTheme.bodyMedium),
                )),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 主持人界面（发牌后看所有身份 + 给玩家发私信）
// ══════════════════════════════════════════════════════════════

class HostView extends StatefulWidget {
  const HostView({
    super.key,
    required this.players,
    required this.zoneMap,
    required this.assignments,
    required this.hostMessages,
    required this.onSend,
    required this.onLeave,
  });
  final Map<String, String> players;
  final Map<String, String> zoneMap;
  final Map<String, dynamic> assignments;
  final List<Map<String, dynamic>> hostMessages;
  final Future<void> Function(String to, String text) onSend;
  final Future<void> Function() onLeave;

  @override
  State<HostView> createState() => _HostViewState();
}

class _HostViewState extends State<HostView> {
  String? _selectedDid;
  final _msgCtrl = TextEditingController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _selectedDid;
    final text = _msgCtrl.text.trim();
    if (to == null || text.isEmpty) return;
    await widget.onSend(to, text);
    _msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playerEntries = widget.players.entries
        .where((e) => widget.zoneMap[e.key] == 'player')
        .toList();
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(children: [
              IconButton(icon: Icon(Icons.arrow_back), onPressed: widget.onLeave),
              SizedBox(width: 4),
              Icon(Icons.workspace_premium,
                  size: 18, color: Colors.amber.shade700),
              SizedBox(width: 6),
              Text('主持人视角 · 全部身份',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: 12),
            Text('你不在分配名单 — 共 ${playerEntries.length} 名玩家',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            SizedBox(height: 16),
            ...playerEntries.map((e) {
              final role = widget.assignments[e.key]?.toString() ?? '?';
              final color = roleColor(theme, role);
              final isSelected = _selectedDid == e.key;
              return Card(
                elevation: 0,
                margin: EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedDid = e.key),
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: color),
                          ),
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
                            Text('身份: $role',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary, size: 20),
                    ]),
                  ),
                ),
              );
            }),
            SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Colors.amber.shade300, width: 1.5),
              ),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.send,
                          size: 16, color: Colors.amber.shade700),
                      SizedBox(width: 6),
                      Text('给玩家发私信',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                    SizedBox(height: 8),
                    Text(
                      _selectedDid == null
                          ? '先在上方点选一名玩家'
                          : '将发给：${widget.players[_selectedDid] ?? '?'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: _selectedDid == null
                              ? theme.colorScheme.outline
                              : theme.colorScheme.primary),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: _msgCtrl,
                      enabled: _selectedDid != null,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '悄悄话内容…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed:
                            _selectedDid == null ? null : _send,
                        icon: Icon(Icons.send, size: 16),
                        label: Text('发送'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.hostMessages.isNotEmpty) ...[
              SizedBox(height: 16),
              _HostMessageList(messages: widget.hostMessages),
            ],
          ],
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
    required this.hostId,
  });
  final String title;
  final IconData icon;
  /// 0 = 无限（旁观区）；>=1 = 槽位数（host=1, player=N）
  final int slots;
  final Map<String, String> players, zoneMap;
  final String zoneFilter;
  final String? hostId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoneEntries =
        players.entries.where((e) => zoneMap[e.key] == zoneFilter).toList();
    final isSpectator = zoneFilter == 'spectator';
    final isHostZone = zoneFilter == 'host';
    final isUnlimited = slots == 0;
    final renderedCount = isUnlimited ? zoneEntries.length : slots;

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
                        : (isHostZone
                            ? Colors.amber.shade700
                            : theme.colorScheme.primary)),
                SizedBox(width: 6),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(width: 6),
                Text(
                  isUnlimited
                      ? '${zoneEntries.length}'
                      : '${zoneEntries.length}/$slots',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 28,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: List.generate(renderedCount, (i) {
                if (i < zoneEntries.length) {
                  final e = zoneEntries[i];
                  final isHostAvatar = e.key == hostId;
                  final color = isHostAvatar
                      ? Colors.amber.shade700
                      : context.teamAvatar
                          .avatarColors[i % context.teamAvatar.avatarColors.length];
                  if (isSpectator) {
                    return _AnimatedSlot(
                      delay: i * 60,
                      child: _MiniAvatar(
                        slotSize: 56,
                        letter:
                            e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                        color: isHostAvatar
                            ? Colors.amber.shade700
                            : theme.colorScheme.outline,
                        isSpectator: true,
                        name: e.value,
                        label: isHostAvatar ? '主持人' : '旁观者',
                        showCrown: isHostAvatar,
                      ),
                    );
                  }
                  return _AnimatedSlot(
                    delay: i * 60,
                    child: _MiniAvatar(
                      slotSize: 56,
                      letter:
                          e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                      color: color,
                      name: e.value,
                      label: isHostZone ? '主持人' : '玩家',
                      showCrown: isHostAvatar,
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
    this.isSpectator = false,
    required this.name,
    required this.label,
    this.showCrown = false,
  });
  final double slotSize;
  final String letter;
  final Color color;
  final bool isSpectator;
  final String name, label;
  final bool showCrown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circle = Container(
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
          color: showCrown
              ? Colors.amber.shade700
              : (isSpectator
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.4)
                  : color.withValues(alpha: 0.35)),
          width: showCrown ? 2.5 : (isSpectator ? 1.5 : 2.0),
        ),
        boxShadow: showCrown
            ? [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.45),
                  blurRadius: 12,
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
                    color: color,
                  )),
            ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topRight,
          children: [
            circle,
            if (showCrown) const _HostCrownBadge(),
          ],
        ),
        SizedBox(height: 4),
        Text(name,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: showCrown
                    ? Colors.amber.shade800
                    : (isSpectator
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6)))),
        Text(label,
            style: TextStyle(
                fontSize: 9,
                color: showCrown
                    ? Colors.amber.shade700
                    : theme.colorScheme.outline)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 房主皇冠角标（贴在 _MiniAvatar 右上方）
// ══════════════════════════════════════════════════════════════

class _HostCrownBadge extends StatelessWidget {
  const _HostCrownBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -6,
      right: -6,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.amber.shade400,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(color: Colors.amber.shade50, width: 1.5),
        ),
        padding: const EdgeInsets.all(2),
        child: const Icon(Icons.workspace_premium, size: 14, color: Colors.white),
      ),
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
