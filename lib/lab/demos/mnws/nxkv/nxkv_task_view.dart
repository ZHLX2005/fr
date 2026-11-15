import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/note/composer/md_composer.dart';
import '../../../../core/note/note_root_scope.dart';
import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 一条任务的**正文视图**（不是一整页：外壳由 `NxKvPage` 提供）。
///
/// ## 为什么不带 AppBar / 不自己 push 路由
///
/// 验收反馈第一条是「头部 nav 影响视觉，去掉 nav，确保可视空间最大化」。
/// 所以这一层只负责**内容**：上面没有标题栏，下面只有一条 44dp 的动作条，
/// 中间全给正文。切任务走抽屉，不再靠「返回 → 队列 → 再点一条」三次点击。
///
/// ## 为什么正文排在元信息前面
///
/// 第三条要求是「编辑区有 80% 的编辑空间」。正文是这页唯一需要**读进去**的东西，
/// 流转时间线、附件清单是查证用的次要信息 —— 次要信息压在上面，等于每次都让人
/// 先划过一屏才知道这活要干什么。现在：标题两行 + 一行元信息，正文紧跟着开始。
class NxKvTaskView extends StatefulWidget {
  const NxKvTaskView({
    super.key,
    required this.controller,
    required this.id,
    this.topicKey,
    this.onSwitch,
    this.onBack,
  });

  final NxKvController controller;
  final int id;
  final String? topicKey;

  /// 重开产生**新任务**时，把外壳切到新编号（不再 push 一层新路由）。
  final void Function(int id)? onSwitch;

  /// 回到队列（外壳的返回）。
  final VoidCallback? onBack;

  @override
  State<NxKvTaskView> createState() => _NxKvTaskViewState();
}

class _NxKvTaskViewState extends State<NxKvTaskView> {
  kv.LocaltaskGetOutput? _task;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// 「更多」：流转细节收在标题下面，默认不展开（那是查证用的，不是每次都要看）。
  bool _metaOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NxKvTaskView old) {
    super.didUpdateWidget(old);
    // 抽屉里换了任务、或重开切到了新编号：这一层要重新取正文
    if (old.id != widget.id || old.topicKey != widget.topicKey) {
      _metaOpen = false;
      _load();
    }
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
        if (widget.onSwitch != null) {
          widget.onSwitch!(r.id);
        } else {
          await _load();
        }
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
    if (_loading && t == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && t == null) {
      return NxKvNotice(
        text: '这条任务打不开',
        detail: _error,
        actionLabel: '重试',
        onAction: _load,
        isError: true,
      );
    }
    if (t == null) return const SizedBox.shrink();

    return Column(
      children: [
        _header(t),
        Expanded(child: _body(t)),
        _actionBar(t),
      ],
    );
  }

  /// 标题区：三行以内解决 —— 编号/状态、标题、一行元信息（可展开更详细）。
  Widget _header(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    final topic = widget.controller.selected?.name ?? widget.topicKey ?? '—';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.sm, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${t.id}', style: TextStyle(fontSize: 11, color: cs.outline)),
              const SizedBox(width: AppSpacing.xs),
              NxKvStatusTag(t.status),
              if (t.round > 1) ...[
                const SizedBox(width: AppSpacing.xs),
                Text('第 ${t.round} 轮', style: TextStyle(fontSize: 10, color: cs.outline)),
              ],
              const Spacer(),
              if (_busy)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            titleOf(t.text, max: 200),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
          ),
          InkWell(
            onTap: () => setState(() => _metaOpen = !_metaOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$topic · ${humanTime(t.createdAt)}入队'
                      '${t.claimedByName.isEmpty ? '' : ' · ${t.claimedByName}'}'
                      '${t.reopenCount > 0 ? ' · 重开 ${t.reopenCount} 次' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.outline),
                    ),
                  ),
                  Icon(
                    _metaOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 14,
                    color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_metaOpen) _meta(t),
        ],
      ),
    );
  }

  Widget _meta(kv.LocaltaskGetOutput t) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs, right: AppSpacing.xs),
      child: Column(
        children: [
          NxKvMetaRow(
            '领取',
            t.consumedAt.isEmpty ? '还没人领' : '${humanTime(t.consumedAt)}（等 ${humanDuration(t.pickupSec)}）',
          ),
          if (t.completedAt.isNotEmpty) NxKvMetaRow('完成', humanTime(t.completedAt)),
          if (t.claimedByName.isNotEmpty) NxKvMetaRow('领取方', t.claimedByName),
        ],
      ),
    );
  }

  Widget _body(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    final rounds = extractRounds(t.text);
    final body = bodyWithoutRounds(t.text);
    final noteRoot = NoteRootScope.of(context).noteRoot;
    final blocks = noteRoot.parseMarkdown(body);

    return ListView(
      // 正文贴着标题开始：上边距 0，靠 header 自己的下边距提供呼吸
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: [
        _label('正文', trailing: '点一段可评价'),
        if (blocks.isEmpty)
          Text('（正文为空）', style: TextStyle(fontSize: 12, color: cs.outline))
        else
          for (final b in blocks)
            InkWell(
              onTap: () => _onBlockTap(b),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: noteRoot.renderBlock(context, b),
              ),
            ),
        if (t.attachments != null && t.attachments!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _label('附件', trailing: '${t.attachments!.length}'),
          for (final a in t.attachments!) _attachment(a),
        ],
        if (rounds.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _label('轮次', trailing: '${rounds.length}'),
          for (final r in rounds) _roundTile(r),
        ],
      ],
    );
  }

  /// 段标：一条细线 + 小字，**不套框**。
  ///
  /// 原来是每个分区一个描边框（`NxKvSection`），框里的 padding 又把正文往里挤了
  /// 一圈 —— 一条任务读下来，屏幕左侧永远空着 12dp。分区靠线分就行。
  Widget _label(String text, {String? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const Spacer(),
          if (trailing != null) Text(trailing, style: TextStyle(fontSize: 10, color: cs.outline)),
        ],
      ),
    );
  }

  /// 附件：**经网络取回本体**，不再只报 PC 上的路径。
  ///
  /// 第 4 轮反馈第三条：「当前附件也应该通过网络传输到手机端展示」。以前这里写的是
  /// `本机：D:\…\x.png` —— 那行字在手机上没有意义：路径在 PC 的盘上，手机既打不开
  /// 也画不出来。现在：
  ///
  ///   · 图片 → 经桥取字节，**内联画出来**，点开全屏可缩放；
  ///   · 其它文件 → 同样取字节落到手机临时目录，再交给系统打开（docx / zip / pdf）；
  ///   · 取失败 → 这一条自己说清「取不回来」，不连累整页正文。
  ///
  /// 服务端给的本机路径仍然保留一行小字：PC 上的 agent 要读的是那个路径，
  /// 端侧只是多了一条自己的路。
  Widget _attachment(kv.LocaltaskGetAttachment a) {
    final cs = Theme.of(context).colorScheme;
    final canFetch = a.kind == 'file' && a.id.isNotEmpty;
    final showImage = canFetch && a.isImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canFetch ? () => _openAttachment(a) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(a.isImage ? Icons.image_outlined : Icons.attach_file, size: 14, color: cs.outline),
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
                      // 服务端给的 PC 路径照旧透出（那是 agent 侧的事实），
                      // 但不再是「附件在哪」的唯一答案
                      if (a.localPath != null && a.localPath!.isNotEmpty)
                        Text(
                          'PC 上：${a.localPath}',
                          style: TextStyle(fontSize: 10, color: cs.outline.withValues(alpha: 0.85)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (canFetch)
                  Icon(
                    a.isImage ? Icons.zoom_in : Icons.download_outlined,
                    size: 15,
                    color: cs.outline,
                  ),
              ],
            ),
          ),
          if (showImage) ...[
            const SizedBox(height: AppSpacing.xs),
            _RemoteImage(
              controller: widget.controller,
              attachment: a,
              onTap: () => _openAttachment(a),
            ),
          ],
        ],
      ),
    );
  }

  /// 点附件：图片进全屏、其它文件先落盘再交给系统打开。
  Future<void> _openAttachment(kv.LocaltaskGetAttachment a) async {
    if (a.isImage) {
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImagePage(controller: widget.controller, attachment: a),
      ));
      return;
    }
    if (kIsWeb) {
      _toast('网页端不落盘：图片能看，文件请到 PC 上打开');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await widget.controller.attachmentBytes(a.id);
      final dir = await getTemporaryDirectory();
      final safeName = a.name.isEmpty ? a.id : a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}/nxkv_att/$safeName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(file.path);
      if (r.type != ResultType.done) {
        _toast('已保存到手机：${file.path}（系统没有能打开它的应用）');
      }
    } catch (e) {
      _toast('附件取不回来：${NxKvController.humanize(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 0, AppSpacing.xs),
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

  /// 底部动作条：44dp 高，只放「对这条任务能做什么」。
  ///
  /// 第 4 轮反馈第二条：「对于任务只标记完成，不要领任务的 btn」。所以这里
  /// **只有**「标完成」—— 没有「领取」。手机是验收端：活由 PC 上的 agent 领走，
  /// 人在手机上读正文、标完成、提反馈。
  ///
  /// 一条还没被领取的任务，标完成会被服务端拦下（`status=blocked`，
  /// `reason=not_claimed`）—— 那个 hint 原样弹出来，而不是把按钮藏掉：
  /// 「点不动」和「为什么点不动」是两件事，藏掉按钮只会让人以为页面坏了。
  Widget _actionBar(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _busy ? null : _done,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('标完成', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _feedback,
            icon: const Icon(Icons.rate_review_outlined, size: 16),
            label: const Text('反馈', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.refresh, color: cs.outline),
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
    );
  }
}

/// 内联图片：**字节经桥取回来**，直接画在正文里。
///
/// 为什么不走 `Image.network`：附件地址在 PC 的 nx-kv 上，取它要带 mn-ws 的
/// 门禁头与应用标识 —— 那是 [MnWsEndpoint] 的活，`Image.network` 只会带个裸 URL
/// 过去，结果必然是 401/404。所以先取字节，再 `Image.memory`。
class _RemoteImage extends StatefulWidget {
  const _RemoteImage({
    required this.controller,
    required this.attachment,
    required this.onTap,
  });

  final NxKvController controller;
  final kv.LocaltaskGetAttachment attachment;
  final VoidCallback onTap;

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.attachmentBytes(widget.attachment.id);
  }

  void _retry() {
    setState(() {
      _future = widget.controller.attachmentBytes(widget.attachment.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: AppSpacing.xs),
                Text('正从 PC 传过来…', style: TextStyle(fontSize: 10, color: cs.outline)),
              ],
            ),
          );
        }
        if (snap.hasError) {
          return Row(
            children: [
              Icon(Icons.broken_image_outlined, size: 14, color: cs.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '取不回来：${NxKvController.humanize(snap.error!)}',
                  style: TextStyle(fontSize: 10, color: cs.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('重试', style: TextStyle(fontSize: 10)),
              ),
            ],
          );
        }
        final bytes = snap.data ?? Uint8List(0);
        if (bytes.isEmpty) {
          return Text('（这张图是空的）', style: TextStyle(fontSize: 10, color: cs.outline));
        }
        return InkWell(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Text('这张图画不出来（格式不支持）', style: TextStyle(fontSize: 10, color: cs.outline)),
            ),
          ),
        );
      },
    );
  }
}

/// 全屏看图：黑底 + 可双指缩放，四个角都能拖。
class _ImagePage extends StatefulWidget {
  const _ImagePage({required this.controller, required this.attachment});

  final NxKvController controller;
  final kv.LocaltaskGetAttachment attachment;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.attachmentBytes(widget.attachment.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.attachment.name, style: const TextStyle(fontSize: 14)),
      ),
      body: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final bytes = snap.data;
          if (snap.hasError || bytes == null || bytes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  '取不回来：${snap.hasError ? NxKvController.humanize(snap.error!) : '空文件'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
