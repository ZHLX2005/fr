// 团建卡牌（v3 Lua 状态机版）
//
// 单文件 demo（方案 A：`lab/demos/<name>_demo.dart`，单文件含常量/视图/组件）
//
// 流程（一人房主 + 多人玩家，使用 v3 Lua 状态机）：
//   1. 顶部 SegmentedButton：选「房主」/「玩家」
//   2. 房主：身份池配置（可保存自定义预设）→ 建房 → 自动 join host → lobby
//   3. 玩家：输入房间码加入 → lobby
//   4. lobby: 显示房间码 + 参与者圆环 + "准备好了" 按钮
//   5. 全员 ack 后 → state="ready"
//      房主看到 "开始发牌" 按钮 + "已就绪 N/N" 提示
//   6. 服务端 Lua 洗牌 → snapshot.state="playing"
//   7. playing: 我方玩家看到自己的身份卡；旁观模式房主看所有人
//
// UI/UX：
//   - 单一 (host=true/false) 切换，三阶段渲染(state)
//   - 房间容量用本地角色池算（避免 Lua count-drop 后端 bug）
//   - 所有阶段都通过 snapshot 流驱动

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/net_p2p/scripts/lua_scripts.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/net_engine/widgets/participants_grid.dart';

// ══════════════════════════════════════════════════════════════
// 常量 + 持久化
// ══════════════════════════════════════════════════════════════

const String _kRelayUrl = 'http://47.110.80.47:8988';
const String _kAliasKey = 'team_card_lua.alias';
const String _kCustomKey = 'team_card_lua.custom_preset';

class AliasPrefs {
  static Future<String> load() async => (await SharedPreferences.getInstance()).getString(_kAliasKey) ?? '';
  static Future<void> save(String alias) async =>
      (await SharedPreferences.getInstance()).setString(_kAliasKey, alias);
}

class CustomPresetPrefs {
  static Future<void> save(List<RoleDef> roles) async {
    final data = jsonEncode(roles.map((r) => r.toJson()).toList());
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCustomKey, data);
  }
  static Future<List<RoleDef>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kCustomKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as List).map((e) => RoleDef.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return null; }
  }
}

// ══════════════════════════════════════════════════════════════
// 角色定义
// ══════════════════════════════════════════════════════════════

class RoleDef {
  RoleDef({required this.label, this.count = 1})
      : nameCtrl = TextEditingController(text: label),
        countCtrl = TextEditingController(text: count.toString());
  String label;
  int count;
  final TextEditingController nameCtrl;
  final TextEditingController countCtrl;

  int get total => count;

  void sync() {
    label = nameCtrl.text.trim().isEmpty ? '?' : nameCtrl.text.trim();
    count = (int.tryParse(countCtrl.text) ?? 1).clamp(1, 99);
  }
  void dispose() { nameCtrl.dispose(); countCtrl.dispose(); }

  Map<String, dynamic> toJson() => {'label': label, 'count': count};
  factory RoleDef.fromJson(Map<String, dynamic> j) =>
      RoleDef(label: j['label'] as String? ?? '', count: (j['count'] as num?)?.toInt() ?? 1);
}

Color roleColor(ThemeData theme, String role) {
  if (role == '卧底' || role == '狼人') return theme.colorScheme.error;
  if (role == '预言家') return Colors.blue;
  if (role == '女巫') return theme.colorScheme.tertiary;
  if (role == '猎人' || role == '守卫') return Colors.teal;
  return theme.colorScheme.primary;
}

typedef _R = ({String label, int count});

class RolePreset {
  final String name;
  final List<_R> roles;
  const RolePreset({required this.name, required this.roles});
  int get total => roles.fold(0, (s, r) => s + r.count);
  List<RoleDef> toRoleDefs() => roles.map((r) => RoleDef(label: r.label, count: r.count)).toList();
}

final List<RolePreset> kBuiltinPresets = [
  RolePreset(name: '谁是卧底（4人）', roles: [(label: '卧底', count: 1), (label: '平民', count: 3)]),
  RolePreset(name: '谁是卧底（6人）', roles: [(label: '卧底', count: 1), (label: '平民', count: 5)]),
  RolePreset(name: '谁是卧底（8人）', roles: [(label: '卧底', count: 2), (label: '平民', count: 6)]),
  RolePreset(name: '狼人杀（6人）', roles: [(label: '狼人', count: 2), (label: '预言家', count: 1), (label: '女巫', count: 1), (label: '村民', count: 2)]),
  RolePreset(name: '狼人杀（8人）', roles: [(label: '狼人', count: 2), (label: '预言家', count: 1), (label: '女巫', count: 1), (label: '猎人', count: 1), (label: '村民', count: 3)]),
  RolePreset(name: '狼人杀（12人）', roles: [(label: '狼人', count: 4), (label: '预言家', count: 1), (label: '女巫', count: 1), (label: '猎人', count: 1), (label: '守卫', count: 1), (label: '村民', count: 4)]),
];

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class TeamCardLuaDemo extends DemoPage {
  TeamCardLuaDemo();
  @override String get title => '团建卡牌 v3';
  @override String get slug => 'team-card-lua';
  @override String get description => '谁是卧底/狼人杀 · Lua 服务端权威 + 准备门';
  @override bool get preferFullScreen => true;
  @override Widget buildPage(BuildContext context) => const _TeamCardLuaDemoPage();
}

void registerTeamCardLuaDemo() => demoRegistry.register(TeamCardLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class _TeamCardLuaDemoPage extends StatefulWidget {
  const _TeamCardLuaDemoPage();
  @override State<_TeamCardLuaDemoPage> createState() => _TeamCardLuaDemoPageState();
}

class _TeamCardLuaDemoPageState extends State<_TeamCardLuaDemoPage> {
  bool _isMaster = true;
  RoomHandle? _handle;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onStarted(RoomHandle handle) => setState(() => _handle = handle);
  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    if (_handle != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('团建卡牌 v3')),
        body: _PlayingView(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('团建卡牌 v3')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('我是房主')),
                ButtonSegment(value: false, label: Text('我是玩家')),
              ],
              selected: {_isMaster},
              onSelectionChanged: (s) => setState(() => _isMaster = s.first),
            ),
          ),
          Expanded(
            child: _isMaster
                ? _SetupPage(
                    initialRoles: [RoleDef(label: '卧底', count: 1), RoleDef(label: '平民', count: 5)],
                    onStarted: _onStarted,
                  )
                : _JoinPage(onStarted: _onStarted),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 身份池配置（房主建房前）
// ══════════════════════════════════════════════════════════════

class _SetupPage extends StatefulWidget {
  const _SetupPage({required this.initialRoles, required this.onStarted});
  final List<RoleDef> initialRoles;
  final void Function(RoomHandle) onStarted;

  @override State<_SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<_SetupPage> {
  late final List<RoleDef> rolePool = widget.initialRoles.map((r) => RoleDef(label: r.label, count: r.count)).toList();
  final _aliasCtrl = TextEditingController();
  bool _masterJoins = true;
  bool _busy = false;
  String? _error;
  List<RoleDef>? _customPresets;

  @override
  void initState() {
    super.initState();
    AliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
    CustomPresetPrefs.load().then((p) {
      if (mounted && p != null) setState(() => _customPresets = p);
    });
  }

  @override void dispose() {
    _aliasCtrl.dispose();
    for (final r in rolePool) { r.dispose(); }
    super.dispose();
  }

  int get _total => rolePool.fold(0, (s, r) => s + r.count);

  void _applyPreset(RolePreset p) {
    for (final r in rolePool) { r.dispose(); }
    rolePool..clear()..addAll(p.toRoleDefs());
    setState(() {});
  }

  void _loadCustomPreset(List<RoleDef> p) {
    for (final r in rolePool) { r.dispose(); }
    rolePool.clear();
    for (final r in p) { rolePool.add(RoleDef(label: r.label, count: r.count)); }
    setState(() {});
  }

  Future<void> _saveCustom() async {
    for (final r in rolePool) { r.sync(); }
    await CustomPresetPrefs.save(rolePool);
    final p = await CustomPresetPrefs.load();
    if (!mounted) return;
    setState(() => _customPresets = p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自定义预设已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _create() async {
    for (final r in rolePool) { r.sync(); }
    final alias = _aliasCtrl.text.trim().isEmpty ? '房主' : _aliasCtrl.text.trim();
    await AliasPrefs.save(alias);
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: _kRelayUrl,
        alias: alias,
        deviceId: 'host-${DateTime.now().microsecondsSinceEpoch}',
      );
      final total = _total;
      final roles = rolePool.map((r) => {'label': r.label, 'count': r.count}).toList();
      final h = await t.createRoom(
        script: kTeamCardScript,
        initialParams: <String, dynamic>{
          'device_id': t.deviceId,
          'alias': alias,
          'roles': roles,
          'master_joins': _masterJoins,
          // 后端 luaToGo bug：roles[*].count 在 snapshot 中丢失，
          // 所以客户端必须显式把牌数传给 Lua（max_players / min_players）。
          // UI 端同样信任本地计算的 total。
          'max_players': total,
          'min_players': total,
        },
        maxPlayers: total,
      );
      if (!mounted) return;
      widget.onStarted(h);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final matched = kBuiltinPresets.where((p) => p.total == total).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            Text('身份池', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('共 $total 人',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                      color: theme.colorScheme.onPrimaryContainer)),
            ),
          ],
        ),
        if (matched.isNotEmpty || _customPresets != null) ...[
          const SizedBox(height: 12),
          Text('快速预设（$total 人）',
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              ...matched.map((p) => _PresetChip(
                label: p.name, onTap: () => _applyPreset(p), theme: theme,
              )),
              if (_customPresets != null)
                _PresetChip(
                  label: '我的预设',
                  onTap: () => _loadCustomPreset(_customPresets!),
                  theme: theme, isCustom: true,
                ),
            ],
          ),
        ],
        ...rolePool.asMap().entries.map((e) => _RoleRow(
          index: e.key,
          def: e.value,
          canRemove: rolePool.length > 1,
          onRemove: () {
            setState(() {
              e.value.dispose();
              rolePool.removeAt(e.key);
            });
          },
        )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => rolePool.add(RoleDef(label: '', count: 1))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加身份'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _saveCustom,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('保存', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          title: const Text('我参与游戏'),
          subtitle: Text(_masterJoins ? '发牌后每人看到自己的身份' : '发牌后可查看所有人身份',
              style: theme.textTheme.bodySmall),
          value: _masterJoins,
          onChanged: (v) => setState(() => _masterJoins = v),
        ),
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
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.meeting_room),
          label: Text(_busy ? '创建中…' : '创建房间'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 玩家入口：输入房间码加入
// ══════════════════════════════════════════════════════════════

class _JoinPage extends StatefulWidget {
  const _JoinPage({required this.onStarted});
  final void Function(RoomHandle) onStarted;

  @override State<_JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<_JoinPage> {
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override void initState() {
    super.initState();
    AliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override void dispose() {
    _aliasCtrl.dispose(); _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (code.length != 6) { setState(() => _error = '房间码 6 位'); return; }
    await AliasPrefs.save(alias);
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: _kRelayUrl, alias: alias,
        deviceId: 'guest-${DateTime.now().microsecondsSinceEpoch}',
      );
      final h = await t.joinRoom(code: code);
      if (!mounted) return;
      widget.onStarted(h);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      children: [
        Icon(Icons.vpn_key_outlined, size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Text('加入房间', textAlign: TextAlign.center,
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
            labelText: '房间码', hintText: '6 位数字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.tag),
          ),
          keyboardType: TextInputType.number, maxLength: 6,
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _join,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: Text(_busy ? '加入中…' : '加入'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 大厅 / 已发牌（snapshot-driven）
// ══════════════════════════════════════════════════════════════

class _PlayingView extends StatefulWidget {
  const _PlayingView({required this.handle, required this.onLeave});
  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override State<_PlayingView> createState() => _PlayingViewState();
}

class _PlayingViewState extends State<_PlayingView> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  String? _myAlias;
  bool _isHost = false;
  bool _busy = false;

  @override void initState() {
    super.initState();
    _snap = widget.handle.latest;
    _myAlias = widget.handle.transport.alias;
    _isHost = widget.handle.transport.deviceId.startsWith('host-');
    _sub = widget.handle.snapshots.listen((s) {
      if (!mounted) return;
      setState(() => _snap = s);
    });
  }

  @override void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Map<String, String> _players() {
    final s = _snap;
    if (s == null) return const {};
    final raw = s.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 实际需要 ack 才能发牌的人（含房主参加模式或不参加模式）
  List<String> _eligibleIds() {
    final s = _snap;
    if (s == null) return const [];
    final ids = <String>[];
    for (final did in _players().keys) {
      final isHostInPool = (_snap?.context['host_id']?.toString() ?? '') == did;
      final masterJoins = (_snap?.context['master_joins'] as bool?) ?? true;
      if (!masterJoins && isHostInPool && _isHost) continue;
      ids.add(did);
    }
    return ids;
  }

  bool _isMeReady() {
    final s = _snap;
    if (s == null) return false;
    final ready = s.context['ready'];
    if (ready is! Map) return false;
    return ready[widget.handle.transport.deviceId] == true;
  }

  String? _myRole() {
    final s = _snap;
    if (s == null) return null;
    final a = s.context['assignments'];
    if (a is! Map) return null;
    return a[widget.handle.transport.deviceId]?.toString();
  }

  Future<void> _ack() async {
    try { await widget.handle.applyAction(type: 'ACK', params: const {}); }
    catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('准备失败: $e')));
    }
  }

  Future<void> _unack() async {
    try { await widget.handle.applyAction(type: 'UNACK', params: const {}); }
    catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取消失败: $e')));
    }
  }

  Future<void> _deal() async {
    setState(() => _busy = true);
    try { await widget.handle.applyAction(type: 'DEAL', params: const {}); }
    catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发牌失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    try { await widget.handle.applyAction(type: 'RESET', params: const {}); }
    catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重置失败: $e')));
    }
  }

  @override Widget build(BuildContext context) {
    final s = _snap;
    final state = s?.state ?? 'lobby';
    if (state == 'playing') {
      final role = _myRole();
      if (role != null) return _IdentityCard(role: role, alias: _myAlias ?? '?');
      if (_isHost) return _SpectatorHostView(players: _players(), onLeave: widget.onLeave);
      return const Center(child: Text('已发牌'));
    }
    // lobby / ready
    return _LobbyView(
      snap: s,
      isHost: _isHost,
      busy: _busy,
      onAck: _ack,
      onUnack: _unack,
      onDeal: _deal,
      onReset: _reset,
      onLeave: widget.onLeave,
      players: _players(),
      eligibleIds: _eligibleIds(),
      isMeReady: _isMeReady(),
    );
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({
    required this.snap, required this.isHost, required this.busy,
    required this.onAck, required this.onUnack, required this.onDeal, required this.onReset,
    required this.onLeave, required this.players,
    required this.eligibleIds, required this.isMeReady,
  });

  final Snapshot? snap;
  final bool isHost;
  final bool busy;
  final VoidCallback onAck;
  final VoidCallback onUnack;
  final VoidCallback onDeal;
  final VoidCallback onReset;
  final Future<void> Function() onLeave;
  final Map<String, String> players;
  final List<String> eligibleIds;
  final bool isMeReady;

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = snap?.roomCode ?? '------';
    final state = snap?.state ?? 'lobby';
    // 后端 luaToGo bug: snapshot.context.max_players 不可靠，
    // 用本地角色池重算 total 作为容量。
    final capacity = eligibleIds.length > 0 && state == 'ready'
        ? eligibleIds.length
        : eligibleIds.length; // 用当前应该就绪的人数作容量
    final readyMap = (snap?.context['ready'] as Map?) ?? const {};
    final readyCount = eligibleIds.where((id) => readyMap[id] == true).length;
    final allReady = state == 'ready';
    final canDeal = isHost && allReady;
    final remaining = (capacity - readyCount).clamp(0, capacity);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Center(child: _RoomCodeBadge(code: code, theme: theme)),
        const SizedBox(height: 12),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state == 'ready'
                    ? '已就绪 · 房主可以开始'
                    : (capacity == 0
                        ? '等待玩家加入…'
                        : (remaining == 0
                            ? '等待房主开始…'
                            : '差 $remaining 人未准备')),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: state == 'ready' ? theme.colorScheme.primary : theme.colorScheme.outline,
                  fontWeight: state == 'ready' ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: capacity == 0 ? 0 : readyCount / capacity),
            ],
          ),
        ),
        const SizedBox(height: 32),
        LobbyParticipants(
          capacity: capacity,
          participants: players,
        ),
        const SizedBox(height: 24),
        // 准备好了 / 取消准备 按钮（互斥切换）
        if (isMeReady)
          OutlinedButton.icon(
            onPressed: onUnack,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('取消准备'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )
        else
          FilledButton.tonalIcon(
            onPressed: onAck,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('准备好了'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        const SizedBox(height: 12),
        if (isHost) Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canDeal && !busy ? onDeal : null,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.style),
                label: Text(busy ? '发牌中…' : '开始发牌'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              tooltip: '重新发牌',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: onLeave,
            icon: const Icon(Icons.exit_to_app),
            label: const Text('离开房间'),
          ),
        ),
      ],
    );
  }
}


// ══════════════════════════════════════════════════════════════
// 我的身份卡 / 房主旁观视图
// ══════════════════════════════════════════════════════════════

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.role, required this.alias});
  final String role;
  final String alias;

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = roleColor(theme, role);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.95, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
          child: SizedBox(
            width: 280,
            child: Card(
              elevation: 0, color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.style, size: 40, color: color),
                  ),
                  const SizedBox(height: 24),
                  Text('你的身份', style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(role, style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Container(
                    height: 3, width: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('只有你能看到这张卡',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectatorHostView extends StatelessWidget {
  const _SpectatorHostView({required this.players, required this.onLeave});
  final Map<String, String> players;
  final Future<void> Function() onLeave;

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onLeave),
              const SizedBox(width: 4),
              Text('房主旁观 · 所有人',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text('你不在分配名单 — 旁观 ${players.length} 名玩家',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 16),
            ...players.entries.map((e) => Card(
              elevation: 0, margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(e.value.isNotEmpty ? e.value[0].toUpperCase() : '?',
                          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(e.value,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
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
// 通用小组件
// ══════════════════════════════════════════════════════════════

class _RoomCodeBadge extends StatelessWidget {
  const _RoomCodeBadge({required this.code, required this.theme});
  final String code;
  final ThemeData theme;

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
      const SizedBox(width: 8),
      Text(code, style: TextStyle(
        fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 6,
        color: theme.colorScheme.primary,
      )),
    ]),
  );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap,
      required this.theme, this.isCustom = false});
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isCustom;

  @override Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    avatar: Icon(isCustom ? Icons.person : Icons.auto_awesome, size: 16,
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

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.index, required this.def,
      required this.canRemove, required this.onRemove});
  final int index;
  final RoleDef def;
  final bool canRemove;
  final VoidCallback onRemove;

  @override Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text('${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13,
                color: theme.colorScheme.onPrimaryContainer,
              ))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: def.nameCtrl,
            decoration: InputDecoration(
              hintText: '身份名称',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => def.sync(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: TextField(
            controller: def.countCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '数量',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => def.sync(),
          ),
        ),
        if (canRemove)
          IconButton(
            icon: Icon(Icons.remove_circle_outline, size: 20, color: theme.colorScheme.error),
            onPressed: onRemove,
          ),
      ]),
    );
  }
}
