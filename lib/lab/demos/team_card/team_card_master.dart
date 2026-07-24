// lib/lab/demos/team_card/team_card_master.dart
// 团建卡牌 — Master 视图（身份池配置 + 房间大厅 + 发牌 + 查看全部）

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;
import 'package:xiaodouzi_fr/core/net_engine/widgets/participants_grid.dart';

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
  final _aliasCtrl = TextEditingController();
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

  // 当 master 参与时，自己的身份
  String? _myRole;

  // 需要等待的玩家数（在线数）
  int get _needed => _masterJoins ? _totalCount - _onlinePeers.length : (_totalCount + 1) - _onlinePeers.length;

  // 房间总人数容量
  int get _roomCapacity => _masterJoins ? _totalCount : _totalCount + 1;

  // 自定义预设
  List<RoleDef>? _customPresets;

  int get _totalCount => rolePool.fold(0, (s, r) => s + r.count);

  @override
  void initState() {
    super.initState();
    AliasPrefs.load().then((saved) {
      if (saved.isNotEmpty && mounted) {
        setState(() {
          _alias = saved;
          _aliasCtrl.text = saved;
        });
      } else if (mounted) {
      }
    });
    CustomPresetPrefs.load().then((preset) {
      if (preset != null && mounted) {
        setState(() {
          _customPresets = preset;
        });
      } else if (mounted) {
      }
    });
  }

  /// 应用预设到 rolePool
  void _applyPreset(RolePreset preset) {
    for (final r in rolePool) { r.dispose(); }
    rolePool.clear();
    rolePool.addAll(preset.toRoleDefs());
    setState(() {});
  }

  /// 保存当前配置为自定义预设
  Future<void> _saveCustomPreset() async {
    for (final r in rolePool) { r.sync(); }
    await CustomPresetPrefs.save(rolePool);
    // 重建 _customPresets 从预存
    CustomPresetPrefs.load().then((p) {
      if (mounted) setState(() => _customPresets = p);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自定义预设已保存'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// 加载自定义预设到 rolePool
  void _loadCustomPreset(List<RoleDef> preset) {
    for (final r in rolePool) { r.dispose(); }
    rolePool.clear();
    // deep copy
    for (final r in preset) {
      rolePool.add(RoleDef(label: r.label, count: r.count, key: 'k${_keyCounter++}'));
    }
    setState(() {});
  }

  Future<void> createRoom() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: _alias);
      final info = await t.createRoom(fw.RoomConfig(
        maxPlayers: _roomCapacity,
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
          // 房主不参与时不计算自己
          if (did != null && (did != _transport?.myNodeId || _masterJoins)) {
            _onlinePeers[did] = alias;
          }
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
    // 如果 master 参与，立即显示自己的身份
    if (_masterJoins) {
      final myId = t.myNodeId;
      final card = cards.where((c) => c.deviceId == myId).firstOrNull;
      if (card != null) _myRole = card.role;
    }
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

  // —————— 身份池配置 + 预选方案 ——————

  Widget _buildSetup(ThemeData theme) {
    // 匹配当前总人数的预设
    final matchedPresets = kBuiltinPresets.where((p) => p.total == _totalCount).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 身份池 + 总人数
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
              child: Text('共 $_totalCount 人', style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13,
                color: theme.colorScheme.onPrimaryContainer,
              )),
            ),
          ],
        ),

        // 匹配的预选方案列表
        if (matchedPresets.isNotEmpty || _customPresets != null) ...[
          const SizedBox(height: 12),
          Text('快速预选（$_totalCount 人配置）', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 8),
          ...matchedPresets.map((p) => _PresetTile(
            name: p.name,
            roles: p.roles.map((r) => '${r.label}×${r.count}').join(' · '),
            onTap: () => _applyPreset(p),
            theme: theme,
          )),
          if (_customPresets != null)
            _PresetTile(
              name: '我的预设',
              roles: _customPresets!.map((r) => '${r.label}×${r.count}').join(' · '),
              onTap: () => _loadCustomPreset(_customPresets!),
              theme: theme,
              isCustom: true,
            ),
        ],

        // 无匹配时引导
        if (matchedPresets.isEmpty && _customPresets == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('可自行添加身份或修改数量以匹配预设', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),

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
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _saveCustomPreset,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存预设', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 参与开关
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.colorScheme.outlineVariant)),
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
        const SizedBox(height: 12),
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(labelText: '你的名字', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) {
            _alias = v.trim().isEmpty ? '房主' : v.trim();
            AliasPrefs.save(v.trim());
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy ? null : createRoom,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.meeting_room),
          label: const Text('创建房间'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  // —————— 房间大厅（会议风格 + 动画）——————

  Widget _buildLobby(ThemeData theme) {
    if (_myRole != null) return _buildMyCard(theme);
    if (_allCards != null && !_masterJoins && _showAllCards) return _buildAllCardsView(theme);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        // 房号徽章
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Center(
            key: ValueKey(_roomCode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(_roomCode!, style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 6, color: theme.colorScheme.primary,
                  )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 人数状态（带计数器变化动画）
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: _onlinePeers.length),
          duration: const Duration(milliseconds: 300),
          builder: (_, count, _) => Center(
            child: Text(
              !_dealt
                  ? '$_roomCapacity 人房 · 已到 $count 人 · 还需 $_needed 人'
                  : '发牌完成',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 32),

        // 参与人网格
        _buildParticipantsGrid(theme),

        const SizedBox(height: 32),

        // 底部按钮
        if (!_dealt)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _onlinePeers.isNotEmpty ? dealCards : null,
              icon: const Icon(Icons.style, size: 20),
              label: Text('开始发牌'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          )
        else if (!_masterJoins && !_showAllCards)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showAllCards = true),
              icon: const Icon(Icons.visibility, size: 18),
              label: const Text('查看所有人身份'),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantsGrid(ThemeData theme) {
    return LobbyParticipants(
      capacity: _roomCapacity,
      participants: _onlinePeers,
    );
  }

  /// master 参与时发牌后显示自己的身份卡（带动画）
  Widget _buildMyCard(ThemeData theme) {
    final color = roleColor(theme, _myRole!);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, scale, _) => Transform.scale(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 装饰顶部弧
                Container(
                  height: 8, width: 80,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    side: BorderSide(color: color.withValues(alpha: 0.25), width: 1.5),
                  ),
                  child: Container(
                    width: 260,
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 角色图标
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
                          ),
                          child: Icon(Icons.style, size: 38, color: color),
                        ),
                        const SizedBox(height: 24),
                        Text('你的身份', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 2)),
                        const SizedBox(height: 10),
                        Text(_myRole!, style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold, color: color, letterSpacing: 1,
                        )),
                        const SizedBox(height: 6),
                        Container(
                          height: 3, width: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('只有你能看到', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
}

// —————— 预设列表卡片 ——————

class _PresetTile extends StatelessWidget {
  final String name;
  final String roles;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isCustom;
  const _PresetTile({required this.name, required this.roles, required this.onTap, required this.theme, this.isCustom = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isCustom ? theme.colorScheme.primary.withValues(alpha: 0.4) : theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isCustom ? theme.colorScheme.primaryContainer : theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(isCustom ? Icons.person : Icons.auto_awesome, size: 18, color: isCustom ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onTertiaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(roles, style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
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
