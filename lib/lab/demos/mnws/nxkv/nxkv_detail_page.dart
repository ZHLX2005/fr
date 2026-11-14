import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../core/note/composer/md_composer.dart';
import '../../../../core/note/note_root_scope.dart';
import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 任务详情：正文按**块**渲染（与块编辑器同一套策略），轮次按时间线读。
///
/// 为什么正文用块渲染而不是一段 `SelectableText`：
/// 任务正文本来就是 md（服务端 `md_to_block` 那套的同一份语法），块渲染下标题是标题、
/// 列表是列表、callout 是 callout —— 用户在手机上看的是「任务长什么样」，
/// 不是「一段源码」。这也是「参考块编辑器」这条反馈的落点。
class NxKvTaskDetailPage extends StatefulWidget {
  const NxKvTaskDetailPage({
    super.key,
    required this.controller,
    required this.id,
    this.topicKey,
  });

  final NxKvController controller;
  final int id;
  final String? topicKey;

  @override
  State<NxKvTaskDetailPage> createState() => _NxKvTaskDetailPageState();
}

class _NxKvTaskDetailPageState extends State<NxKvTaskDetailPage> {
  kv.LocaltaskGetOutput? _task;
  bool _loading = true;
  String? _error;

  /// 正在跑的动作（完成 / 反馈），挡住重复点。
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await widget.controller.task(widget.id, widget.topicKey);
      if (!mounted) return;
      setState(() {
        _task = t;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = NxKvController.humanize(e);
        _loading = false;
      });
    }
  }

  // ── 动作 ──────────────────────────────────────────────────

  Future<void> _claimThis() async {
    final topic = widget.controller.selected;
    if (topic == null) return;
    setState(() => _busy = true);
    try {
      await widget.controller.claim(topic);
      await _load();
      await widget.controller.refresh();
    } catch (e) {
      _toast('领取失败：${NxKvController.humanize(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    final t = _task;
    if (t == null) return;
    final md = await openMdComposer(
      context,
      title: '完成 #${t.id}',
      hint: '写清「做了什么 / 怎么验的 / 遗留」——这段会直接进任务链。',
      initialText: '## 本轮做了什么\n\n- \n\n## 怎么验的\n\n- \n\n## 遗留\n\n- 无\n',
      submitLabel: '标记完成',
      templates: const ['完成总结'],
    );
    if (md == null || md.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await widget.controller.done(t.id, widget.topicKey, md);
      if (!mounted) return;
      if (r.status == 'blocked') {
        _toast(r.hint ?? '现在还不能标完成（时间目标未到 / 未领取）');
      } else {
        _toast('已标记完成');
        await _load();
        await widget.controller.refresh();
      }
    } catch (e) {
      _toast('标记失败：${NxKvController.humanize(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _feedback() async {
    final t = _task;
    if (t == null) return;
    final md = await openMdComposer(
      context,
      title: '验收反馈 · #${t.id}',
      hint: '说清哪里不对、期望是什么。提交后任务会重开为下一轮，旧的压进历史。',
      submitLabel: '提交反馈',
      templates: const ['验收反馈'],
    );
    if (md == null || md.trim().isEmpty) return;
    await _reopen(t.id, kind: 'reopen', md: md);
  }

  /// 段落级「引用评价」：锚定的是**这一整段的原文**，不是一次文本选区。
  Future<void> _commentOn(String quote) async {
    final t = _task;
    if (t == null) return;
    final md = await openMdComposer(
      context,
      title: '评价这一段',
      hint: '针对上面这段说点什么；提交后作为「反馈修改」追加到任务正文。',
      quote: quote,
      submitLabel: '提交评价',
    );
    if (md == null || md.trim().isEmpty) return;
    await _reopen(t.id, kind: 'comment', md: md, quote: quote);
  }

  Future<void> _reopen(int id, {required String kind, required String md, String? quote}) async {
    setState(() => _busy = true);
    try {
      final r = await widget.controller.feedback(id, widget.topicKey, kind: kind, md: md, quote: quote);
      await widget.controller.refresh();
      if (!mounted) return;
      _toast(kind == 'comment' ? '已提交评价（#${r.id}）' : '已提交反馈，任务重开为 #${r.id}');
      // 重开产生的是**新任务**：留在旧任务上只会看到一份已被历史压住的正文
      if (r.id != id) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => NxKvTaskDetailPage(
            controller: widget.controller,
            id: r.id,
            topicKey: widget.topicKey,
          ),
        ));
      } else {
        await _load();
      }
    } catch (e) {
      _toast('提交失败：${NxKvController.humanize(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = _task;
    return Scaffold(
      appBar: AppBar(
        title: Text('任务 #${widget.id}', style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: _loading && t == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null && t == null
              ? NxKvNotice(text: '这条任务打不开', detail: _error, actionLabel: '重试', onAction: _load, isError: true)
              : _body(t!),
      bottomNavigationBar: t == null ? null : _bottomBar(t),
    );
  }

  Widget _body(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    final rounds = extractRounds(t.text);
    final body = bodyWithoutRounds(t.text);
    final noteRoot = NoteRootScope.of(context).noteRoot;
    final blocks = noteRoot.parseMarkdown(body);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // 标题 + 状态
        Text(
          titleOf(t.text, max: 200),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            NxKvStatusTag(t.status),
            const SizedBox(width: AppSpacing.xs),
            if (t.round > 1) ...[
              Text('第 ${t.round} 轮', style: TextStyle(fontSize: 11, color: cs.outline)),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (t.reopenCount > 0)
              Text('重开 ${t.reopenCount} 次', style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // 元信息
        NxKvSection(
          title: '这活是怎么流转的',
          child: Column(
            children: [
              NxKvMetaRow('主题', widget.controller.selected?.name ?? widget.topicKey ?? '—'),
              NxKvMetaRow('入队', humanTime(t.createdAt)),
              NxKvMetaRow('领取', t.consumedAt.isEmpty ? '还没人领' : '${humanTime(t.consumedAt)}（等 ${humanDuration(t.pickupSec)}）'),
              NxKvMetaRow('上线', t.consumedAt.isEmpty ? '—' : '${humanTime(t.createdAt)} → ${humanTime(t.consumedAt)}'),
              if (t.completedAt.isNotEmpty) NxKvMetaRow('完成', humanTime(t.completedAt)),
              if (t.claimedByName.isNotEmpty) NxKvMetaRow('领取方', t.claimedByName),
            ],
          ),
        ),

        // 附件
        if (t.attachments != null && t.attachments!.isNotEmpty)
          NxKvSection(
            title: '附件',
            trailing: Text('${t.attachments!.length}', style: TextStyle(fontSize: 11, color: cs.outline)),
            child: Column(
              children: [
                for (final a in t.attachments!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          a.isImage ? Icons.image_outlined : Icons.attach_file,
                          size: 14,
                          color: cs.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name, style: const TextStyle(fontSize: 12)),
                              Text(
                                [a.kindLabel, a.sizeText, if (a.note != null && a.note!.isNotEmpty) a.note!].join(' · '),
                                style: TextStyle(fontSize: 10, color: cs.outline, height: 1.5),
                              ),
                              // 本机路径是「附件到底在哪」的唯一答案：有就直说，
                              // 没有（未同步）就把同步命令摆出来，不让人猜。
                              Text(
                                (a.localPath != null && a.localPath!.isNotEmpty)
                                    ? '本机：${a.localPath}'
                                    : (a.cmd != null && a.cmd!.isNotEmpty ? '需同步：${a.cmd}' : '未落盘'),
                                style: TextStyle(fontSize: 10, color: cs.outline.withValues(alpha: 0.85)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // 正文（块渲染；点一段 = 锚定这一段）
        NxKvSection(
          title: '正文',
          trailing: Text('点一段可评价', style: TextStyle(fontSize: 10, color: cs.outline)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (blocks.isEmpty)
                Text('（正文为空）', style: TextStyle(fontSize: 12, color: cs.outline))
              else
                for (final b in blocks)
                  InkWell(
                    onTap: () => _onBlockTap(b),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: noteRoot.renderBlock(context, b),
                    ),
                  ),
            ],
          ),
        ),

        // 轮次时间线
        if (rounds.isNotEmpty)
          NxKvSection(
            title: '轮次（${rounds.length}）',
            child: Column(
              children: [
                for (final r in rounds) _roundTile(r),
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Future<void> _onBlockTap(Block block) async {
    final quote = plainText(block.content.toPlainText());
    if (quote.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
              child: Text(
                quote.length > 100 ? '${quote.substring(0, 100)}…' : quote,
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.chat_bubble_outline, size: 18),
              title: const Text('评价这一段', style: TextStyle(fontSize: 13)),
              subtitle: const Text('引用原文 + 写 md，落到任务正文的「反馈修改」', style: TextStyle(fontSize: 10)),
              onTap: () => Navigator.of(ctx).pop('comment'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.copy_all_outlined, size: 18),
              title: const Text('复制原文', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: quote));
      _toast('已复制');
      return;
    }
    await _commentOn(quote);
  }

  Widget _roundTile(NxKvRound r) {
    final cs = Theme.of(context).colorScheme;
    final color = r.isFeedback ? cs.error : cs.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color.withValues(alpha: 0.55), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${r.index} 轮 · ${r.label}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            r.body.isEmpty ? '（没有正文）' : r.body,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    final pending = t.status == 'pending';
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          children: [
            if (pending)
              FilledButton.icon(
                onPressed: _busy ? null : _claimThis,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('领取'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy ? null : _done,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('标完成'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : _feedback,
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('验收反馈'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const Spacer(),
            if (_busy)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}
