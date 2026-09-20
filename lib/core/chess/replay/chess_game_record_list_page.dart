// lib/core/chess/replay/chess_game_record_list_page.dart
//
// 对局回放库列表页 —— 全屏页：已保存整局列表 + 删除 + 进入回放。
//
// 布局（参照 ChessEndgameListPage 的全屏列表风格）：
//   AppBar(title: '对局回放库')
//   body: ListView（整局卡片：标题 / 保存日期 / 手数 / 终局徽标）
//     点击卡片 → push ChessGameReplayPage（离线回放：快照列表选步开始）
//     trailing 删除按钮（全部为本地条目，均可删）→ 确认弹窗 → delete
//
// 与残局库的差异：无内置 assets / 无导入导出（对局记录纯本地产物）。

import 'package:flutter/material.dart';

import '../skins/chess_skin.dart';
import 'chess_game_record.dart';
import 'chess_game_record_store.dart';
import 'chess_game_replay_page.dart';

/// 对局回放库列表页。
class ChessGameRecordListPage extends StatefulWidget {
  const ChessGameRecordListPage({
    super.key,
    this.store,
    this.skin,
  });

  /// 存储注入（测试用）。null → 生产默认。
  final ChessGameRecordStore? store;

  /// 回放页皮肤透传。null → 回放页内回退默认皮肤。
  final ChessSkin? skin;

  @override
  State<ChessGameRecordListPage> createState() =>
      _ChessGameRecordListPageState();
}

class _ChessGameRecordListPageState extends State<ChessGameRecordListPage> {
  late final ChessGameRecordStore _store =
      widget.store ?? ChessGameRecordStore();

  List<ChessGameRecord> _records = const [];
  bool _loading = true;
  String? _error;

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
        _records = list;
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

  Future<void> _delete(ChessGameRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对局'),
        content: Text('确定删除「${r.title}」？此操作不可恢复。'),
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
      await _store.delete(r.id);
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$err')),
      );
    }
  }

  void _openReplay(ChessGameRecord r) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChessGameReplayPage(record: r, skin: widget.skin),
      ),
    );
  }

  /// savedAt ISO → 本地展示（yyyy-MM-dd HH:mm；解析失败回退原文）。
  String _formatDate(String savedAt) {
    final dt = DateTime.tryParse(savedAt)?.toLocal();
    if (dt == null) return savedAt;
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('对局回放库'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: _records.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                '暂无已保存的对局\n在房间终局复盘时点「保存整局」即可入库',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _records.length,
                          itemBuilder: (ctx, i) =>
                              _buildCard(_records[i]),
                        ),
                ),
    );
  }

  Widget _buildCard(ChessGameRecord r) {
    final theme = Theme.of(context);
    final statusLabel = chessGameStatusLabel(r.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        onTap: () => _openReplay(r),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.history_edu,
            size: 22,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          r.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                _formatDate(r.savedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${r.moveCount} 手',
                style: theme.textTheme.bodySmall,
              ),
              if (statusLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '删除',
          onPressed: () => _delete(r),
        ),
      ),
    );
  }
}
