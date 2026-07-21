// lib/lab/demos/team_card_demo.dart
//
// 团建卡牌 Demo —— 谁是卧底 / 狼人杀 类型的身份分配器
//
// 场景：master 建房 → 设定人数 + 身份模板 → 玩家加入 → master 发牌
//
// 通信走 localnet 引擎（RelayTransport pub/sub）：
// - master publish('room/<code>/events', {type:'deal', assignments, words})
// - 全量广播，每个客户端按 transport.myNodeId 过滤出自己的身份
// - 应用层信任：所有客户端都能收到全量数据，只显示自己的（团建场景）
//
// 身份分配规则：
// - master 按在线玩家数 + 自己 = N，从模板生成 N 张身份卡
// - 随机 shuffle 后 publish
// - 每个客户端收到 assignments[myNodeId] = '卧底'/'平民'/...

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import '../lab_container.dart';

// 预设身份模板（角色名 → 数量比例）
const _kRelayUrl = 'http://47.110.80.47:8988';

class _RoleTemplate {
  final String name;
  final String desc;
  final List<_RoleDef> roles; // 角色定义列表（身份 + 占比）

  const _RoleTemplate({
    required this.name,
    required this.desc,
    required this.roles,
  });
}

class _RoleDef {
  final String id; // 身份 ID（用于 assignments value）
  final String label; // 显示名
  final int ratio; // 数量比例（实际数 = round(N * ratio / totalRatio)）

  const _RoleDef({required this.id, required this.label, required this.ratio});
}

const _kTemplates = <_RoleTemplate>[
  _RoleTemplate(
    name: '谁是卧底',
    desc: '1 卧底 + 其余平民（词不同）',
    roles: [
      _RoleDef(id: 'undercover', label: '卧底', ratio: 1),
      _RoleDef(id: 'civilian', label: '平民', ratio: 7),
    ],
  ),
  _RoleTemplate(
    name: '狼人杀（6人）',
    desc: '2 狼人 + 1 预言家 + 1 女巫 + 2 村民',
    roles: [
      _RoleDef(id: 'wolf', label: '狼人', ratio: 2),
      _RoleDef(id: 'seer', label: '预言家', ratio: 1),
      _RoleDef(id: 'witch', label: '女巫', ratio: 1),
      _RoleDef(id: 'villager', label: '村民', ratio: 2),
    ],
  ),
];

class TeamCardDemo extends DemoPage {
  @override
  String get title => '团建卡牌';

  @override
  String get slug => 'team-card';

  @override
  String get description => '谁是卧底/狼人杀 身份分配（master 发牌）';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const TeamCardDemoPage();
}

class TeamCardDemoPage extends StatefulWidget {
  const TeamCardDemoPage({super.key});

  @override
  State<TeamCardDemoPage> createState() => _TeamCardDemoPageState();
}

class _TeamCardDemoPageState extends State<TeamCardDemoPage> {
  bool _isMaster = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('团建卡牌')),
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
                ? const _MasterView()
                : const _PlayerView(),
          ),
        ],
      ),
    );
  }
}

// ============ Master 视图：建房 + 配身份 + 发牌 ============

class _MasterView extends StatefulWidget {
  const _MasterView();

  @override
  State<_MasterView> createState() => _MasterViewState();
}

class _MasterViewState extends State<_MasterView> {
  int _templateIdx = 0;
  int _maxPlayers = 6;
  String _alias = '房主';
  fw.RelayTransport? _transport;
  String? _roomCode;
  String? _token;
  final _onlinePeers = <fw.RemoteEvent>[]; // peer-joined 事件流
  final Set<String> _onlineDeviceIds = {};
  StreamSubscription<fw.RemoteEvent>? _sub;
  bool _busy = false;
  String? _error;
  bool _dealt = false;

  Future<void> _createRoom() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await fw.RelayTransport.create(
        relayUrl: _kRelayUrl,
        alias: _alias,
      );
      final info = await t.createRoom(fw.RoomConfig(
        maxPlayers: _maxPlayers,
        schema: {'template': _kTemplates[_templateIdx].name},
        canStartBeforeFull: true,
      ));
      _transport = t;
      _roomCode = info.code;
      _token = info.token;
      _onlineDeviceIds.add(t.myNodeId); // master 自己算一个
      _sub = t.subscribe('room/${info.code}/events').listen((ev) {
        if (ev.payload['type'] == 'peer-joined' ||
            ev.payload['type'] == 'peer-online') {
          setState(() {
            _onlineDeviceIds.add(ev.payload['deviceId'] as String? ?? '');
            _onlinePeers.add(ev);
          });
        }
      });
      setState(() => _busy = false);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '创建失败: $e';
      });
    }
  }

  Future<void> _dealCards() async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;

    // 生成身份列表
    final template = _kTemplates[_templateIdx];
    final n = _onlineDeviceIds.length;
    final roles = <String>[];
    for (final def in template.roles) {
      final count = max(1, (n * def.ratio / template.roles.fold(0, (s, r) => s + r.ratio)).round());
      for (var i = 0; i < count; i++) {
        roles.add(def.id);
      }
    }
    // 裁剪/补齐到 n
    while (roles.length > n) {
      roles.removeLast();
    }
    while (roles.length < n) {
      roles.add(template.roles.last.id);
    }
    roles.shuffle();

    // 分配：deviceId → 身份 id
    final deviceIds = _onlineDeviceIds.toList();
    final assignments = <String, String>{};
    for (var i = 0; i < deviceIds.length; i++) {
      assignments[deviceIds[i]] = roles[i];
    }

    // 广播全量（客户端各自过滤）
    await t.publish('room/$code/events', {
      'type': 'deal',
      'template': template.name,
      'assignments': assignments,
      'labels': {for (final d in template.roles) d.id: d.label},
    });
    setState(() => _dealt = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _transport?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_roomCode == null) {
      return _buildSetup(theme);
    }
    return _buildLobby(theme);
  }

  Widget _buildSetup(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('选择身份模板', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < _kTemplates.length; i++)
          ListTile(
            leading: Icon(
              _templateIdx == i ? Icons.radio_button_checked : Icons.radio_button_off,
              color: theme.colorScheme.primary,
            ),
            title: Text(_kTemplates[i].name),
            subtitle: Text(_kTemplates[i].desc),
            onTap: () => setState(() => _templateIdx = i),
          ),
        const SizedBox(height: 16),
        Text('房间人数上限: $_maxPlayers', style: theme.textTheme.titleMedium),
        Slider(
          value: _maxPlayers.toDouble(),
          min: 3,
          max: 12,
          divisions: 9,
          label: '$_maxPlayers',
          onChanged: (v) => setState(() => _maxPlayers = v.round()),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: '你的名字',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _alias = v.trim().isEmpty ? '房主' : v.trim(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _createRoom,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.meeting_room),
          label: const Text('创建房间'),
        ),
      ],
    );
  }

  Widget _buildLobby(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('房间号', style: theme.textTheme.labelSmall),
                Text(_roomCode!, style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                )),
                const SizedBox(height: 8),
                Text('Token（分享给玩家）', style: theme.textTheme.labelSmall),
                Text(_token!, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 8),
                Text('模板: ${_kTemplates[_templateIdx].name}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('在线: ${_onlineDeviceIds.length} / $_maxPlayers 人',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._onlineDeviceIds.map((id) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(id.length > 8 ? '${id.substring(0, 8)}...' : id),
              dense: true,
            )),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _dealt ? null : _dealCards,
          icon: const Icon(Icons.style),
          label: Text(_dealt ? '已发牌' : '开始发牌'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

// ============ Player 视图：加入 + 收身份 ============

class _PlayerView extends StatefulWidget {
  const _PlayerView();

  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> {
  final _codeCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  fw.RelayTransport? _transport;
  StreamSubscription<fw.RemoteEvent>? _sub;
  bool _busy = false;
  String? _error;
  bool _joined = false;
  // 收到的身份
  String? _myRoleLabel;
  String? _templateName;

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    if (code.length != 6 || token.isEmpty) {
      setState(() => _error = '请输入 6 位房间号和 token');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await fw.RelayTransport.create(relayUrl: _kRelayUrl, alias: alias);
      await t.joinRoom(code, token);
      _transport = t;
      _sub = t.subscribe('room/$code/events').listen((ev) {
        if (ev.payload['type'] == 'deal') {
          final assignments = (ev.payload['assignments'] as Map?)?.cast<String, String>() ?? {};
          final labels = (ev.payload['labels'] as Map?)?.cast<String, String>() ?? {};
          final myRole = assignments[t.myNodeId];
          setState(() {
            _templateName = ev.payload['template'] as String?;
            _myRoleLabel = myRole != null ? (labels[myRole] ?? myRole) : null;
          });
        }
      });
      setState(() {
        _busy = false;
        _joined = true;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '加入失败: $e';
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _transport?.close();
    _codeCtrl.dispose();
    _tokenCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_myRoleLabel != null) {
      return _buildCard(theme);
    }
    if (_joined) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text('已加入房间，等待发牌...',
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _aliasCtrl,
          decoration: const InputDecoration(labelText: '你的名字', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          decoration: const InputDecoration(labelText: '房间号（6位）', border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtrl,
          decoration: const InputDecoration(labelText: 'Token', border: OutlineInputBorder()),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _joinRoom,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: const Text('加入房间'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }

  Widget _buildCard(ThemeData theme) {
    final isWolf = _myRoleLabel == '狼人';
    return Center(
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isWolf ? Icons.visibility_off : Icons.style,
                  size: 64, color: isWolf ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(_templateName ?? '身份卡',
                  style: theme.textTheme.labelSmall),
              const SizedBox(height: 8),
              Text(_myRoleLabel!,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('只你能看到自己的身份',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

void registerTeamCardDemo() {
  demoRegistry.register(TeamCardDemo());
}
