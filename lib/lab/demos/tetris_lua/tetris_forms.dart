// lib/lab/demos/tetris_lua/tetris_forms.dart
// 俄罗斯方块 — 建房 / 加入表单（独立叶子组件，从 widgets 拆出降文件行数）。

import 'package:flutter/material.dart';

import 'engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';

Widget aliasField(BoardThemeData theme) => TextField(
  decoration: InputDecoration(
    labelText: '昵称',
    hintText: '输入你的昵称',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    labelStyle: TextStyle(color: theme.btnSub),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: theme.panelBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: kTetrisAccent, width: 2),
    ),
  ),
  style: TextStyle(color: theme.btnText),
);

// ══════════════════════════════════════════════════════════════
// Setup Page（建房）
// ══════════════════════════════════════════════════════════════

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.onCreated});
  final void Function(RoomHandle) onCreated;
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  // 默认空：避免 TetrisAliasPrefs.load() 异步回调把用户刚输入的昵称覆盖回旧值。
  final _aliasCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    TetrisAliasPrefs.load().then((v) {
      // 仅在用户还没输入（text 为空）时填入历史昵称，杜绝覆盖 race。
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kTetrisRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'tet-host-${DateTime.now().microsecondsSinceEpoch}',
      );
      await TetrisAliasPrefs.save(t.alias);
      final h = await t.createRoom(
        script: kTetrisScript,
        initialParams: {'device_id': t.deviceId, 'alias': t.alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      widget.onCreated(h);
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
    final theme = BoardTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded, size: 64, color: kTetrisAccent),
            const SizedBox(height: 16),
            Text(
              '建房等对手',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.btnText,
              ),
            ),
            const SizedBox(height: 24),
            aliasField(theme),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.meeting_room),
              label: Text(_busy ? '创建中…' : '创建房间'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                foregroundColor: kTetrisAccent,
                side: const BorderSide(color: kTetrisAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Join Page（加入）
// ══════════════════════════════════════════════════════════════

class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;
  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  // 默认空：同 SetupPage，避免 load 覆盖用户输入。
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    TetrisAliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = '房间码为 6 位数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kTetrisRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'tet-guest-${DateTime.now().microsecondsSinceEpoch}',
      );
      await TetrisAliasPrefs.save(t.alias);
      final h = await t.joinRoom(code: code);
      if (!mounted) return;
      widget.onJoined(h);
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
    final theme = BoardTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.login_rounded, size: 64, color: kTetrisAccent),
              const SizedBox(height: 16),
              Text(
                '加入房间',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.btnText,
                ),
              ),
              const SizedBox(height: 24),
              aliasField(theme),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                  labelText: '房间码',
                  hintText: '6 位数字',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelStyle: TextStyle(color: theme.btnSub),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.panelBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: kTetrisAccent, width: 2),
                  ),
                ),
                style: TextStyle(color: theme.btnText),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _join,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_busy ? '加入中…' : '加入'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  foregroundColor: kTetrisAccent,
                  side: const BorderSide(color: kTetrisAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
