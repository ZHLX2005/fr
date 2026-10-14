// lib/lab/demos/cowrite_lua_demo.dart
//
// Co-Write Notebook（双人协作笔记本）— v3 Lua 状态机版。
//
// 流程：
//   - 输入昵称 + 房间号 → 点击"进入协作"
//   - 服务端 join 尝试：404 → 用此号创建新房间
//   - 双方进入后直接 playing（不需要 ACK；不是游戏）
//   - 任一方编辑 → 全量同步内容
//   - 单方可"占用广播权" → 把自己视图首行行号广播给对方
//   - 对方开启"自动对齐" → 滚动位置跟随
//   - "保存参考"按钮 → SharedPreferences 存当前内容（按 roomCode 分 key）
//
// 入口：GameLobbyPage（lib/core/game_kit/lobby）—— 单表单 smartMatch。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'cowrite_lua/cowrite_engine.dart' show RoomHandle;
import 'cowrite_lua/cowrite_widgets.dart' show OnlineCoWritePage;
import 'cowrite_lua/cowrite_save_reference.dart';
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/cowrite/lobby/cowrite_lobby_spec.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class CoWriteLuaDemo extends DemoPage {
  CoWriteLuaDemo();
  @override
  String get title => '协作笔记（联机）';

  @override
  String get slug => 'cowrite-lua';

  @override
  String get description => '双人协作笔记本 · Lua 服务端权威 · 首行广播 + 自动对齐视图';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.tool;

  @override
  Widget buildPage(BuildContext context) => const CoWriteLuaPage();
}

void registerCoWriteLuaDemo() => demoRegistry.register(CoWriteLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class CoWriteLuaPage extends StatefulWidget {
  const CoWriteLuaPage({super.key});

  @override
  State<CoWriteLuaPage> createState() => _CoWriteLuaPageState();
}

class _CoWriteLuaPageState extends State<CoWriteLuaPage> {
  RoomHandle? _handle;
  bool _showReferences = false;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onStarted(RoomHandle h, LobbyStartedCtx ctx) =>
      setState(() => _handle = h);

  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    if (_handle != null) {
      return Scaffold(
        backgroundColor: bg,
        body: OnlineCoWritePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    if (_showReferences) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('本地参考'),
          backgroundColor: bg,
          foregroundColor: theme.btnText,
          elevation: 0,
        ),
        body: SafeArea(child: _ReferencesView(onBack: () {
          setState(() => _showReferences = false);
        })),
      );
    }
    return Column(
      children: [
        Expanded(
          child: GameLobbyPage(
            spec: kCoWriteLobbySpec,
            // trailingEntry 不能 const —— 运行时构造 slots
            slots: GameLobbySlots(
              trailingEntry: (context) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showReferences = true),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.btnSub,
                    ),
                    icon: const Icon(Icons.bookmarks_outlined, size: 18),
                    label: const Text('查看本地参考',
                        style: TextStyle(letterSpacing: 1)),
                  ),
                ),
              ),
            ),
            onStarted: _onStarted,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 本地参考列表视图
// ══════════════════════════════════════════════════════════════

class _ReferencesView extends StatefulWidget {
  const _ReferencesView({required this.onBack});
  final VoidCallback onBack;

  @override
  State<_ReferencesView> createState() => _ReferencesViewState();
}

class _ReferencesViewState extends State<_ReferencesView> {
  List<String> _codes = const [];
  Map<String, String> _contents = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final codes = await CoWriteReferenceStore.listAll();
    final map = <String, String>{};
    for (final c in codes) {
      final content = await CoWriteReferenceStore.load(c);
      if (content != null) map[c] = content;
    }
    if (!mounted) return;
    setState(() {
      _codes = codes;
      _contents = map;
      _loading = false;
    });
  }

  Future<void> _delete(String code) async {
    await CoWriteReferenceStore.remove(code);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _refresh();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('已删除参考 $code'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copy(String code, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已复制参考 $code 到剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _open(String code, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ReferenceDetailDialog(code: code, content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border,
                size: 48, color: theme.btnSub.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('暂无本地参考', style: TextStyle(color: theme.btnSub)),
            const SizedBox(height: 8),
            Text('在协作页点工具栏的「保存参考」',
                style: TextStyle(color: theme.btnSub, fontSize: 12)),
            const SizedBox(height: 16),
            TextButton(onPressed: widget.onBack, child: const Text('返回')),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final code in _codes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReferenceCard(
                    code: code,
                    content: _contents[code] ?? '',
                    onOpen: () => _open(code, _contents[code] ?? ''),
                    onCopy: () => _copy(code, _contents[code] ?? ''),
                    onDelete: () => _delete(code),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    required this.code,
    required this.content,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
  });

  final String code;
  final String content;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final preview = content.length > 80
        ? '${content.substring(0, 80)}…'
        : (content.isEmpty ? '(空)' : content);
    return Material(
      color: theme.panelBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.panelBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.btnText.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.btnText.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: theme.btnText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '复制全文',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: onCopy,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: theme.btnSub),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.btnText.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${content.length} 字 · 点击查看全文',
                style: TextStyle(color: theme.btnSub, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceDetailDialog extends StatelessWidget {
  const _ReferenceDetailDialog({required this.code, required this.content});
  final String code;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Dialog(
      backgroundColor: theme.panelBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: theme.btnText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${content.length} 字',
                style: TextStyle(color: theme.btnSub, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.btnText.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.btnText.withValues(alpha: 0.1),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content.isEmpty ? '(空)' : content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: theme.btnText,
                        fontFamily: 'monospace',
                      ),
                    ),
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