// lib/lab/demos/cowrite_lua/cowrite_widgets.dart
//
// Co-Write Notebook — UI 组件：LobbyEntryPage + OnlineCoWritePage。
//
// 关键设计：
//   - **单表单** LobbyEntryPage（tryJoinOrCreate + 409 撞号/满员区分提示）
//   - **共享昵称** LuaGameAlias（4 个 Lua 游戏共用）
//   - **不需要 ACK**：进入直接到 playing
//   - **编辑器**：多行 TextField + TextEditingController；debounce 250ms 发 EDIT
//   - **首行广播**：监听 ScrollController 偏移 → 换算为"第几行可见" → debounce 300ms 发 BROADCAST_LINE
//   - **自动对齐**：收到 BROADCAST_LINE + 我开启 follow → 调本地 scrollController 跳到自己第 N 行
//   - **冲突防护**：用 broadcaster_version 比较，旧版本不覆盖新版本
//   - **广播权 UI**：单选 toggle（"占用广播权"），只有当无人占用时可点
//   - **保存参考**：按钮 → CoWriteReferenceStore.save → toast
//
// 布局（参考 styles-skill + jungle_chess_lua 的卡片化）：
//   ┌───────────────────────────────┐
//   │ ◀ 房间号  X 正在广播第N行 ▸  │  工具栏（44px 固定）
//   ├───────────────────────────────┤
//   │ ☐ 我自动广播  ☐ 自动对齐      │  选项行（56px 固定）
//   ├───────────────────────────────┤
//   │                               │
//   │  [多行 TextField 编辑器]       │
//   │                               │
//   │                               │
//   ├───────────────────────────────┤
//   │ 在线：Alice、Bob · 我的首行 N  │  状态条（36px 固定）
//   └───────────────────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_device_id.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';

import 'cowrite_constants.dart';
import 'cowrite_engine.dart';
import 'cowrite_save_reference.dart';

// ══════════════════════════════════════════════════════════════
// LobbyEntryPage — 单表单智能匹配（与五子棋/围棋/斗兽棋同一模式）
// ══════════════════════════════════════════════════════════════

class LobbyEntryPage extends StatefulWidget {
  const LobbyEntryPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;

  @override
  State<LobbyEntryPage> createState() => _LobbyEntryPageState();
}

class _LobbyEntryPageState extends State<LobbyEntryPage> {
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    LuaGameAlias.load().then((v) {
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
    LuaGameAlias.notifier.addListener(_onAliasChanged);
  }

  void _onAliasChanged() {
    if (!mounted) return;
    final v = LuaGameAlias.value;
    if (v != _aliasCtrl.text) setState(() => _aliasCtrl.text = v);
  }

  @override
  void dispose() {
    LuaGameAlias.notifier.removeListener(_onAliasChanged);
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4 || code.length > 6) {
      setState(() => _error = '房间码为 4–6 位大写字母数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kCoWriteRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kCoWriteScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: kCoWriteMaxPlayers,
      );
      if (!mounted) return;
      widget.onJoined(h);
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      final body = e.body.toLowerCase();
      final String msg;
      if (e.statusCode == 409 && body.contains('code collision')) {
        msg = '房间号 $code 已被占用，请换一个';
      } else if (e.statusCode == 409 && body.contains('join rejected')) {
        msg = '房间 $code 已满员，无法加入';
      } else if (e.statusCode == 404) {
        msg = '房间号 $code 不存在且创建失败';
      } else {
        msg = '进入失败（${e.statusCode}）';
      }
      setState(() {
        _busy = false;
        _error = msg;
      });
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
    InputDecoration inputDec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.6)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          filled: true,
          fillColor: theme.btnBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.panelBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.panelBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.btnText, width: 1.6),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── 提示行（浅灰块，左对齐）──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.btnText.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text('◐',
                style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '同一房间号进入即可协作；可设置"我的首行广播"和"自动对齐"',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ── 昵称 ──
      TextField(
        controller: _aliasCtrl,
        decoration: inputDec('昵称'),
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: LuaGameAlias.save,
      ),
      const SizedBox(height: 12),

      // ── 房间号 ──
      TextField(
        controller: _codeCtrl,
        decoration: inputDec('房间号（4–6 位大写字母数字）'),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: theme.btnText,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        onSubmitted: (_) => _busy ? null : _go(),
      ),

      // ── 错误提示 ──
      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text('◉',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      height: 1.4)),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      // ── 主按钮 ──
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _busy ? null : _go,
          style: FilledButton.styleFrom(
            backgroundColor: theme.btnText,
            foregroundColor: theme.panelBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.panelBg,
                  ),
                )
              : const Text('进入协作',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2)),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// OnlineCoWritePage — 协作编辑主页面
// ══════════════════════════════════════════════════════════════

class OnlineCoWritePage extends StatefulWidget {
  const OnlineCoWritePage({
    super.key,
    required this.handle,
    required this.onLeave,
  });
  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override
  State<OnlineCoWritePage> createState() => _OnlineCoWritePageState();
}

class _OnlineCoWritePageState extends State<OnlineCoWritePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;

  late final CoWriteRoom _room;
  late final TextEditingController _editorCtrl;
  late final ScrollController _scrollCtrl;

  Timer? _editDebounce;
  Timer? _broadcastDebounce;

  /// 当前本地文本是否与服务端一致（用于判断 EDIT 是否要发）。
  String _localEcho = '';

  /// 收到的最新广播版本号（防止本地 scroll 事件回放覆盖新广播）。
  int? _lastBroadcastVersion;

  /// 当前是否开启"自动对齐"（本地偏好，从快照读）。
  bool _amFollowing = false;

  /// 当前是否开启"我自动广播"（仅当持有广播权时生效）。
  bool _iAmBroadcaster = false;

  @override
  void initState() {
    super.initState();
    _room = CoWriteRoom(widget.handle);
    _editorCtrl = TextEditingController();
    _scrollCtrl = ScrollController();

    // 初始快照（CreateRoom 后立即有 content 字段）
    final initial = widget.handle.latest;
    if (initial != null) {
      final c = CoWriteRoom.content(initial);
      _editorCtrl.text = c;
      _localEcho = c;
      _amFollowing = CoWriteRoom.amFollowing(initial, _room.deviceId);
      _iAmBroadcaster = CoWriteRoom.amBroadcaster(initial, _room.deviceId);
    }

    _editorCtrl.addListener(_onLocalEdit);
    _scrollCtrl.addListener(_onLocalScroll);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  @override
  void dispose() {
    _editDebounce?.cancel();
    _broadcastDebounce?.cancel();
    _sub?.cancel();
    _editorCtrl.removeListener(_onLocalEdit);
    _scrollCtrl.removeListener(_onLocalScroll);
    _editorCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── 本地编辑 → debounce 发 EDIT ──

  void _onLocalEdit() {
    final text = _editorCtrl.text;
    if (text == _localEcho) return;
    _localEcho = text;
    _editDebounce?.cancel();
    _editDebounce = Timer(kCoWriteEditDebounce, () {
      _room.edit(text);
    });
  }

  // ── 本地滚动 → debounce 发 BROADCAST_LINE（仅当持有广播权）──

  void _onLocalScroll() {
    if (!_iAmBroadcaster) return;
    if (!_scrollCtrl.hasClients) return;
    final line = _currentFirstVisibleLine();
    _broadcastDebounce?.cancel();
    _broadcastDebounce = Timer(kCoWriteBroadcastDebounce, () {
      _room.broadcastLine(line);
    });
  }

  /// 把当前 ScrollController.offset 反推为"第几行可见"（1-indexed）。
  ///
  /// 算法：用编辑器字体的 lineHeight + 顶部 padding 估算每像素 = 多少行。
  /// 留 5px 容差避免抖动。
  int _currentFirstVisibleLine() {
    if (!_scrollCtrl.hasClients) return 1;
    final offset = _scrollCtrl.offset;
    final fontSize = 16.0; // 与编辑器 style 一致
    final lineHeight = fontSize * 1.5;
    // TextField 内置 padding ≈ vertical: 12
    const topPadding = 12.0;
    final line = ((offset + topPadding) / lineHeight).floor() + 1;
    return line.clamp(1, 9999);
  }

  /// 把"目标第 N 行"转换为 ScrollController 应该滚到的 offset。
  double _lineToOffset(int line) {
    final fontSize = 16.0;
    final lineHeight = fontSize * 1.5;
    const topPadding = 12.0;
    return (line - 1) * lineHeight - topPadding;
  }

  // ── 快照处理 ──

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prev = _snap;
    _snap = s;

    // 1) 服务端 content → 本地编辑器（避免覆盖正在输入的字符）
    final newContent = CoWriteRoom.content(s);
    if (newContent != _localEcho && _editorCtrl.text != newContent) {
      // 只在本地没有未提交的修改时同步
      final selection = _editorCtrl.selection;
      _editorCtrl.value = TextEditingValue(
        text: newContent,
        selection: selection.isValid && selection.end <= newContent.length
            ? selection
            : TextSelection.collapsed(offset: newContent.length),
      );
      _localEcho = newContent;
    }

    // 2) follow 偏好
    final newFollow = CoWriteRoom.amFollowing(s, _room.deviceId);
    final newBroadcaster = CoWriteRoom.amBroadcaster(s, _room.deviceId);

    // 3) 自动对齐：仅当对方广播 + 自己是 follower + 版本号更新
    final newVersion = CoWriteRoom.broadcasterVersion(s);
    final newLine = CoWriteRoom.broadcasterLine(s);
    final shouldFollow =
        newFollow && !newBroadcaster && newVersion != null && newLine != null;

    if (shouldFollow && newVersion != _lastBroadcastVersion) {
      _lastBroadcastVersion = newVersion;
      // 仅在远距离时才 animateTo，避免每条广播都抖
      final target = _lineToOffset(newLine);
      final current = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0;
      final delta = (target - current).abs();
      if (_scrollCtrl.hasClients && delta > 24) {
        _scrollCtrl.animateTo(
          target.clamp(
            _scrollCtrl.position.minScrollExtent,
            _scrollCtrl.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    } else if (newVersion != null && newVersion > (_lastBroadcastVersion ?? 0)) {
      _lastBroadcastVersion = newVersion;
    }

    // 4) 触发 UI 重绘（follow / broadcaster 状态变化）
    if (newFollow != _amFollowing || newBroadcaster != _iAmBroadcaster) {
      setState(() {
        _amFollowing = newFollow;
        _iAmBroadcaster = newBroadcaster;
      });
    } else {
      // 即使状态没变也要刷新（snapshot.version 变了）
      setState(() {});
    }

    // 兜底：避免 prev 未使用警告
    if (prev == null) return;
  }

  // ── 动作 ──

  Future<void> _toggleBroadcaster() async {
    if (_iAmBroadcaster) {
      await _room.stopBroadcast();
    } else {
      // 先看当前是否有人占用（本地读快照）
      final current = _snap;
      final cur = CoWriteRoom.broadcasterId(current);
      if (cur != null && cur != _room.deviceId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${CoWriteRoom.broadcasterAlias(current) ?? "对方"} 正在广播，请等其停止后再试'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      await _room.startBroadcast();
    }
  }

  Future<void> _toggleFollow() async {
    await _room.setFollow(!_amFollowing);
  }

  Future<void> _saveReference() async {
    final content = CoWriteRoom.content(_snap);
    final code = _snap?.roomCode ?? '';
    final ok = await CoWriteReferenceStore.save(code, content);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已保存到本地参考' : '保存失败'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(theme, context),
            _buildOptionRow(theme, context),
            Expanded(child: _buildEditor(theme, context)),
            _buildStatusBar(theme, context),
          ],
        ),
      ),
    );
  }

  // ── 工具栏 ──

  Widget _buildToolbar(BoardThemeData theme, BuildContext context) {
    final code = _snap?.roomCode ?? '------';
    final broadcasterAlias = CoWriteRoom.broadcasterAlias(_snap);
    final broadcasterLine = CoWriteRoom.broadcasterLine(_snap);
    final String statusText;
    if (broadcasterAlias == null) {
      statusText = '无人广播';
    } else if (broadcasterAlias == _aliasOrMe()) {
      statusText = '你正在广播第 $broadcasterLine 行';
    } else {
      statusText = '$broadcasterAlias 正在广播第 $broadcasterLine 行';
    }
    return SizedBox(
      height: kCoWriteToolbarHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.panelBg.withValues(alpha: 0.5),
          border: Border(
            bottom: BorderSide(color: theme.panelBorder.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(
          children: [
            // 房间号 chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.btnText.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.btnText.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: theme.btnText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: broadcasterAlias == null
                      ? theme.btnSub
                      : theme.btnText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _saveReference,
              icon: const Icon(Icons.bookmark_add_outlined, size: 16),
              label: const Text('保存参考',
                  style: TextStyle(fontSize: 12, letterSpacing: 1)),
              style: TextButton.styleFrom(
                foregroundColor: theme.btnText,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: widget.onLeave,
              icon: const Icon(Icons.exit_to_app, size: 16),
              label: const Text('退出',
                  style: TextStyle(fontSize: 12, letterSpacing: 1)),
              style: TextButton.styleFrom(
                foregroundColor: theme.btnSub,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _aliasOrMe() {
    final id = _room.deviceId;
    return CoWriteRoom.players(_snap)[id] ?? id;
  }

  // ── 选项行（两开关 + 状态提示） ──

  Widget _buildOptionRow(BoardThemeData theme, BuildContext context) {
    final bcHeldByOther = CoWriteRoom.broadcasterId(_snap) != null &&
        !_iAmBroadcaster;
    return SizedBox(
      height: kCoWriteOptionRowHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.panelBg.withValues(alpha: 0.3),
          border: Border(
            bottom: BorderSide(color: theme.panelBorder.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _OptionToggle(
                label: _iAmBroadcaster ? '我正在广播' : '我自动广播首行',
                active: _iAmBroadcaster,
                disabled: !_iAmBroadcaster && bcHeldByOther,
                disabledHint: bcHeldByOther ? '他人占用中' : null,
                onTap: _toggleBroadcaster,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OptionToggle(
                label: _amFollowing ? '自动对齐：开' : '自动对齐：关',
                active: _amFollowing,
                onTap: _toggleFollow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 编辑器 ──

  Widget _buildEditor(BoardThemeData theme, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(kCoWriteEditorRadius),
          border: Border.all(color: theme.panelBorder),
          boxShadow: [
            BoxShadow(
              color: theme.btnText.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kCoWriteEditorRadius),
          child: TextField(
            controller: _editorCtrl,
            scrollController: _scrollCtrl,
            maxLines: null,
            minLines: 8,
            expands: false,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: theme.btnText,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '在此输入笔记…\n对方可看到你正在编辑的内容。',
              hintStyle: TextStyle(
                color: theme.btnSub.withValues(alpha: 0.6),
                fontSize: 15,
                height: 1.5,
                fontFamily: 'monospace',
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  // ── 底部状态条 ──

  Widget _buildStatusBar(BoardThemeData theme, BuildContext context) {
    final players = CoWriteRoom.players(_snap);
    final names = players.values.toList();
    final myLine = _currentFirstVisibleLine();
    return SizedBox(
      height: kCoWriteStatusBarHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.panelBg.withValues(alpha: 0.5),
          border: Border(
            top: BorderSide(color: theme.panelBorder.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.people_alt_outlined,
                size: 14, color: theme.btnSub),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '在线：${names.isEmpty ? "—" : names.join("、")}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.btnSub, fontSize: 12, letterSpacing: 1),
              ),
            ),
            Text(
              '我的首行：第 $myLine 行',
              style: TextStyle(
                color: _iAmBroadcaster ? theme.btnText : theme.btnSub,
                fontSize: 12,
                fontWeight:
                    _iAmBroadcaster ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 小组件：选项 toggle
// ══════════════════════════════════════════════════════════════

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.active,
    required this.onTap,
    this.disabled = false,
    this.disabledHint,
  });

  final String label;
  final bool active;
  final bool disabled;
  final String? disabledHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final bg = disabled
        ? theme.btnSub.withValues(alpha: 0.06)
        : active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : theme.btnText.withValues(alpha: 0.04);
    final fg = disabled
        ? theme.btnSub.withValues(alpha: 0.6)
        : active
            ? Theme.of(context).colorScheme.primary
            : theme.btnText;
    final border = disabled
        ? theme.btnSub.withValues(alpha: 0.2)
        : active
            ? Theme.of(context).colorScheme.primary
            : theme.btnText.withValues(alpha: 0.25);
    return Tooltip(
      message: disabledHint ?? '',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.5,
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
}
