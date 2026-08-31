// lib/core/chess/endgame/chess_endgame_list_page.dart
//
// 残局列表页 —— 全屏页：残局列表 + 快照选择 + 导入 / AI 提示词 / 删除。
//
// 布局（参照 chess_skin_settings_page 的全屏列表风格）：
//   AppBar(title: '残局库', actions: 导入 / AI 提示词)
//   body: ListView（残局卡片 → 点击展开快照列表）
//     快照条目：label + FEN 缩略棋盘预览 + [以此开局] [导出]
//     （"以此开局" pop(snapshot) 返回调用方 → LobbyPage 注入 initial_fen）
//
// 返回语义：pop(ChessEndgameSnapshot) = 选中快照开局；pop(null) = 取消。
// 删除：仅本地条目（source != builtin）露出删除入口（内置 assets 不可删）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../engine/fen_codec.dart';
import '../models/board_state.dart';
import '../skins/chess_skin.dart';
import '../widgets/chess_board.dart';
import 'chess_endgame.dart';
import 'chess_endgame_prompt.dart';
import 'chess_endgame_store.dart';

/// 残局列表页。
class ChessEndgameListPage extends StatefulWidget {
  const ChessEndgameListPage({
    super.key,
    this.store,
    this.skin,
  });

  /// 存储注入（测试用）。null → 生产默认。
  final ChessEndgameStore? store;

  /// 缩略预览用皮肤。null → ChessSkinBundle.byId('1')。
  final ChessSkin? skin;

  @override
  State<ChessEndgameListPage> createState() => _ChessEndgameListPageState();
}

class _ChessEndgameListPageState extends State<ChessEndgameListPage> {
  late final ChessEndgameStore _store = widget.store ?? ChessEndgameStore();

  List<ChessEndgame> _endgames = const [];
  bool _loading = true;
  String? _error;

  /// 当前展开的残局 id（null = 全部收起）。
  String? _expandedId;

  /// 正在导入 / 导出（防双击）。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _store.loadAll();
      if (!mounted) return;
      setState(() {
        _endgames = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  // ─────────────────────────── 动作 ───────────────────────────

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final e = await _store.importFromFile();
      if (!mounted) return;
      if (e == null) {
        // 用户取消或文件非法 —— file_picker 取消返回 null，无法区分，
        // 统一提示（解析失败的文件多半也到不了这里）。
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未导入（取消或文件格式非法）')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入：${e.title}')),
        );
      }
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$err')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(ChessEndgame e) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _store.exportAndShare(e);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$err')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ChessEndgame e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除残局'),
        content: Text('确定删除「${e.title}」？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.delete(e.id);
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$err')),
      );
    }
  }

  void _showPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 生成残局提示词'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(
              kChessEndgameGenPrompt,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(text: kChessEndgameGenPrompt),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('提示词已复制')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _startFrom(ChessEndgameSnapshot snap) {
    Navigator.of(context).pop(snap);
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('残局库'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            tooltip: '导入残局文件',
            onPressed: _busy ? null : _import,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 生成提示词',
            onPressed: _showPrompt,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: _endgames.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('暂无残局，点右上角导入或用 AI 生成')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _endgames.length,
                          itemBuilder: (ctx, i) => _buildCard(_endgames[i]),
                        ),
                ),
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );

  Widget _buildCard(ChessEndgame e) {
    final theme = Theme.of(context);
    final expanded = _expandedId == e.id;
    final deletable = e.source != ChessEndgameSource.builtin;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(
                () => _expandedId = expanded ? null : e.id),
            title: Text(
              e.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _sourceBadge(e.source),
                  const SizedBox(width: 8),
                  if (e.difficulty > 0) ...[
                    Text(
                      '★' * e.difficulty,
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      e.tags.take(3).join(' · '),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${e.snapshots.length} 局面',
                  style: theme.textTheme.bodySmall,
                ),
                if (deletable)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '删除',
                    onPressed: () => _delete(e),
                  ),
                Icon(expanded
                    ? Icons.expand_less
                    : Icons.expand_more),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  if (e.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        e.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  for (var i = 0; i < e.snapshots.length; i++)
                    _buildSnapshotTile(e, i),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSnapshotTile(ChessEndgame e, int index) {
    final theme = Theme.of(context);
    final snap = e.snapshots[index];
    final board = _tryParseFen(snap.fen);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FEN 缩略棋盘预览（解析失败 → 占位图标）。
          SizedBox(
            width: 96,
            height: 96,
            child: board != null
                ? ChessBoard(
                    state: board,
                    skin: widget.skin ??
                        ChessSkinBundle.byId('1'),
                    sideToMove: board.sideToMove,
                    onSquareTap: null, // 预览无交互
                  )
                : const Center(
                    child: Icon(Icons.broken_image_outlined, size: 28),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snap.label ?? '快照 ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snap.fen,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _startFrom(snap),
                      icon: const Icon(Icons.sports_esports, size: 16),
                      label: const Text('以此开局'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '导出分享',
                      onPressed: () => _export(
                        // 单快照导出：构造只含该快照的残局文件。
                        ChessEndgame(
                          id: e.id,
                          title: e.title,
                          description: e.description,
                          createdAt: e.createdAt,
                          source: e.source,
                          tags: e.tags,
                          difficulty: e.difficulty,
                          snapshots: [snap],
                        ),
                      ),
                      icon: const Icon(Icons.ios_share, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceBadge(ChessEndgameSource source) {
    final color = switch (source) {
      ChessEndgameSource.builtin => Colors.blue,
      ChessEndgameSource.imported => Colors.orange,
      ChessEndgameSource.replay => Colors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        source.label,
        style: TextStyle(
          fontSize: 10,
          color: color.withValues(alpha: 1.0),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// FEN → BoardState（null = 非法；预览防御）。
  static BoardState? _tryParseFen(String fen) {
    try {
      return FenCodec.fromFen(fen);
    } on Object {
      return null;
    }
  }
}
