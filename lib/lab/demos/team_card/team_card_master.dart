// lib/lab/demos/team_card/team_card_master.dart
// 团建卡牌 — Master 视图（身份池配置 + 房间大厅 + 发牌 + 查看全部）

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'const_team_card.dart';
import 'team_card_types.dart';

class MasterView extends StatefulWidget {
  const MasterView({super.key});
  @override
  State<MasterView> createState() => MasterViewState();
}

class MasterViewState extends State<MasterView> {
  final rolePool = <RoleDef>[
    RoleDef(label: '卧底', count: 1, key: _newKey()),
    RoleDef(label: '平民', count: 5, key: _newKey()),
  ];
  String _alias = '房主';
  bool _masterJoins = true;

  fw.RelayTransport? _transport;
  String? _roomCode;
  final _onlinePeers = <String, String>{}; // deviceId → alias
  StreamSubscription<fw.RemoteEvent>? _sub;
  Timer? _peersTimer;
  bool _busy = false;
  String? _error;
  bool _dealt = false;
  bool _showAllCards = false;
  List<CardInfo>? _allCards;

  static int _keyCounter = 0;
  static String _newKey() => 'k${_keyCounter++}';

  Future<void> createRoom() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: _alias);
      final info = await t.createRoom(fw.RoomConfig(
        maxPlayers: max(rolePool.length + 2, 10),
        schema: {'roles': [for (final r in rolePool) {'label': r.label, 'count': r.count}]},
        canStartBeforeFull: true,
      ));
      _transport = t;
      _roomCode = info.code;
      if (_masterJoins) _onlinePeers[t.myNodeId] = _alias;

      _sub = t.subscribe('room/${info.code}/events').listen((ev) {
        final type = ev.payload['type'] as String?;
        if (type == 'peer-joined' || type == 'peer-online') {
          final did = ev.payload['deviceId'] as String?;
          final alias = ev.payload['alias'] as String? ?? '?';
          if (did != null) _onlinePeers[did] = alias;
          if (mounted) setState(() {});
        }
        if (type == 'peer-left') {
          final did = ev.payload['deviceId'] as String?;
          if (did != null) _onlinePeers.remove(did);
          if (mounted) setState(() {});
        }
      });
      _peersTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchPeers());
      setState(() => _busy = false);
    } catch (e) {
      setState(() { _busy = false; _error = '创建失败: $e'; });
    }
  }

  Future<void> fetchPeers() async {
    final code = _roomCode;
    if (code == null) return;
    try {
      final resp = await http.get(Uri.parse('$kRelayUrl/api/v1/relay/rooms/$code/peers'));
      if (resp.statusCode == 200) {
        final list = (jsonDecode(resp.body)['peers'] as List?) ?? [];
        for (final p in list) {
          final did = (p as Map)['deviceId'] as String?;
          final alias = p['alias'] as String? ?? '?';
          if (did != null) _onlinePeers[did] = alias;
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void dealCards() async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;

    // 从角色池生成 N 张
    final n = _onlinePeers.length;
    final pool = <String>[];
    for (final def in rolePool) {
      for (var i = 0; i < def.count; i++) { pool.add(def.label); }
    }
    while (pool.length < n) { pool.add(rolePool.last.label); }
    pool.shuffle();

    final deviceIds = _onlinePeers.keys.toList();
    final assignments = <String, String>{};
    final cards = <CardInfo>[];
    for (var i = 0; i < n; i++) {
      assignments[deviceIds[i]] = pool[i];
      cards.add(CardInfo(deviceId: deviceIds[i], alias: _onlinePeers[deviceIds[i]] ?? '?', role: pool[i]));
    }
    _allCards = cards;

    await t.publish('room/$code/events', {
      'type': 'deal', 'assignments': assignments,
    });
    if (mounted) setState(() => _dealt = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _peersTimer?.cancel();
    _transport?.close();
    for (final r in rolePool) { r.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_roomCode == null) return _buildSetup(theme);
    return _buildLobby(theme);
  }

  // —————— 身份池配置 ——————

  Widget _buildSetup(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('身份池配置', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...rolePool.asMap().entries.map((e) => _RoleCard(
          index: e.key,
          def: e.value,
          onRemove: rolePool.length > 1 ? () => setState(() {
            e.value.dispose();
            rolePool.removeAt(e.key);
          }) : null,
        )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => rolePool.add(RoleDef(label: '', count: 1, key: 'k${++_keyCounter}'))),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加身份'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 参与开关
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SwitchListTile(
              title: const Text('我参与游戏'),
              subtitle: Text(_masterJoins ? '发牌后每人看到自己的身份' : '发牌后可查看所有人身份'),
              value: _masterJoins,
              onChanged: (v) => setState(() => _masterJoins = v),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            labelText: '你的名字',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => _alias = v.trim().isEmpty ? '房主' : v.trim(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : createRoom,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.meeting_room),
          label: const Text('创建房间'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // —————— 房间大厅 ——————

  Widget _buildLobby(ThemeData theme) {
    if (_allCards != null && !_masterJoins && _showAllCards) return _buildAllCardsView(theme);
    final showAllBtn = _dealt && !_masterJoins;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 房间号
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('房间号', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 8),
                Text(_roomCode!, style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold, letterSpacing: 6, color: theme.colorScheme.primary,
                )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 在线玩家
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('在线 (${_onlinePeers.length})', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (!_masterJoins && _dealt)
                      Text('房主旁观中', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_onlinePeers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('等待玩家加入...', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  )
                else
                  ..._onlinePeers.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _avatarLabel(e.value, theme),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                            Text(e.key.length > 12 ? '${e.key.substring(0, 12)}...' : e.key,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (showAllBtn)
          FilledButton.icon(
            onPressed: () => setState(() => _showAllCards = true),
            icon: const Icon(Icons.visibility),
            label: const Text('查看所有人身份'),
            style: _btnStyle(theme),
          )
        else
          FilledButton.icon(
            onPressed: _dealt ? null : dealCards,
            icon: Icon(_dealt ? Icons.check_circle : Icons.style),
            label: Text(_dealt ? '已发牌' : '开始发牌'),
            style: _btnStyle(theme),
          ),
      ],
    );
  }

  // —————— 查看全部身份 ——————

  Widget _buildAllCardsView(ThemeData theme) {
    final cards = _allCards!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _showAllCards = false)),
            const SizedBox(width: 8),
            Text('所有人身份', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        ...cards.map((c) => Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _avatarLabel(c.alias, theme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.alias, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      Text('ID: ${c.deviceId.length > 10 ? c.deviceId.substring(0, 10) : c.deviceId}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: roleColor(theme, c.role).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(c.role, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: roleColor(theme, c.role))),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  ButtonStyle _btnStyle(ThemeData theme) => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

// —————— 身份编辑卡片 ——————

class _RoleCard extends StatefulWidget {
  final int index;
  final RoleDef def;
  final VoidCallback? onRemove;
  const _RoleCard({required this.index, required this.def, this.onRemove});

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  late RoleDef d;

  @override
  void initState() {
    super.initState();
    d = widget.def;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('${widget.index + 1}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onPrimaryContainer))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: d.nameCtrl,
                decoration: const InputDecoration(hintText: '身份名称', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()),
                onChanged: (_) => d.sync(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextField(
                controller: d.countCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '数量', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8), border: OutlineInputBorder()),
                onChanged: (_) => d.sync(),
              ),
            ),
            if (widget.onRemove != null)
              IconButton(icon: Icon(Icons.remove_circle_outline, size: 20, color: theme.colorScheme.error), onPressed: widget.onRemove),
          ],
        ),
      ),
    );
  }
}

// —————— 头像首字母标签 ——————

Widget _avatarLabel(String text, ThemeData theme) {
  return Container(
    width: 32, height: 32,
    decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
    child: Center(child: Text(text.isNotEmpty ? text[0].toUpperCase() : '?', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer))),
  );
}
