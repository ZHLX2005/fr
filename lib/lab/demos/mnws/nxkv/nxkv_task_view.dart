import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/note/composer/md_composer.dart';
import '../../../../core/note/note_root_scope.dart';
import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import 'nxkv_motion.dart';
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
///
/// ## 第 3 轮 UI/UX（「继续优化」）改了什么
///
/// 详情页是上一轮 `nxkv_motion.dart` 没铺到的地方，这轮把它接进同一套语言：
///
///   · 动作条：两个 Material `TextButton.icon` → **等宽胶囊**（实心主操作
///     「标完成」+ 淡底「反馈」）+ 圆形刷新（`_PillButton` / `_PillIconButton`）；
///   · 头部：裸 `#19` 小字 → 编号块（与队列页同款），meta 展开从硬插
///     （`if (_metaOpen)`）→ [AnimatedSize] 高度动画 + 箭头 q 弹旋转半圈；
///   · 轮次：左缘竖线 + 两行字 → **真时间线**（圆点实心=最新 / 空心=旧，
///     连线串成链，反馈轮 error 色、总结轮主色，胶囊标签）；
///   · 正文段：点一段可评价原来只有一行小字提示 → `_BlockTap` 按下出淡主色底
///     + 左缘竖条（画在 Stack 背景层、外扩 6dp，文字位置分毫不动）；
///   · 附件：裸图标 + 裸文字 → 卡片 + `NxKvIconTile` 图标底座，图片圆角升到
///     [AppRadius.lg] 与附件卡同档；引用弹窗 `ListTile + Divider` → 圆角卡
///     （抓手 + 引文左缘竖条 + 胶囊动作行，`_QuoteSheet`）；全屏看图去 AppBar
///     改沉浸式（浮层关闭按钮 + 「双指缩放」提示）。
///
/// 「外壳」在 [NxKvPage]：队列 ⇄ 任务的主区切换补了 [AnimatedSwitcher]
/// （淡入 + 3% 右移），点开一条任务不再是硬换屏。
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
              // 编号块：与队列页同一颗（等宽数字，位数变了也不左右抖）。
              // 裸 `#19` 小字在标题上方是「编号」，做成块之后才读得出「这是第几条」。
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '#${t.id}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              NxKvStatusTag(t.status),
              if (t.round > 1) ...[
                const SizedBox(width: 6),
                Container(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('第 ${t.round} 轮', style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant)),
                ),
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
          NxKvPress(
            onTap: () => setState(() => _metaOpen = !_metaOpen),
            semanticLabel: _metaOpen ? '收起任务信息' : '展开任务信息',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
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
                  // 展开箭头跟着状态转半圈（q 弹曲线）：硬切图标会让人以为点错了
                  AnimatedRotation(
                    turns: _metaOpen ? 0.5 : 0,
                    duration: NxKvMotion.base,
                    curve: NxKvMotion.snap,
                    child: Icon(Icons.expand_more_rounded, size: 15, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
          // 高度也要跟着走：`if (_metaOpen)` 直接插会把下面整段正文「弹」下去一屏
          AnimatedSize(
            duration: NxKvMotion.base,
            curve: NxKvMotion.glide,
            alignment: Alignment.topCenter,
            child: _metaOpen ? _meta(t) : const SizedBox(width: double.infinity, height: 0),
          ),
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
        _label('正文', hint: '点一段可评价'),
        if (blocks.isEmpty)
          Text('（正文为空）', style: TextStyle(fontSize: 12, color: cs.outline))
        else
          for (final b in blocks)
            _BlockTap(onTap: () => _onBlockTap(b), child: noteRoot.renderBlock(context, b)),
        if (t.attachments != null && t.attachments!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _label('附件', count: '${t.attachments!.length}'),
          for (final a in t.attachments!) _attachment(a),
        ],
        if (rounds.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _label('轮次', count: '${rounds.length}'),
          for (var i = 0; i < rounds.length; i++)
            _roundTile(rounds[i], isFirst: i == 0, isLatest: i == rounds.length - 1),
        ],
      ],
    );
  }

  /// 段标：一条细线 + 小字，**不套框**。
  ///
  /// 原来是每个分区一个描边框（`NxKvSection`），框里的 padding 又把正文往里挤了
  /// 一圈 —— 一条任务读下来，屏幕左侧永远空着 12dp。分区靠线分就行。
  ///
  /// [count] 是「这一段有几条」（附件数 / 轮次数），做成胶囊跟队列页的徽标同源；
  /// [hint] 是这个分区**能做什么**的提示（正文可点评价）。
  Widget _label(String text, {String? count, String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          if (count != null) ...[
            const SizedBox(width: 6),
            NxKvBadge(count),
          ],
          const Spacer(),
          if (hint != null) ...[
            Icon(Icons.touch_app_rounded, size: 11, color: cs.outline),
            const SizedBox(width: 3),
            Text(hint, style: TextStyle(fontSize: 10, color: cs.outline)),
          ],
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 附件是**可点的物件**，所以给它一个卡片的形（跟队列页任务卡同圆角），
          // 而不是裸图标 + 裸文字：裸行在正文里会被读成「一段说明」。
          NxKvPress(
            onTap: canFetch ? () => _openAttachment(a) : null,
            semanticLabel: '附件 ${a.name}',
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NxKvIconTile(
                    icon: a.isImage ? Icons.image_rounded : Icons.attach_file_rounded,
                    size: 28,
                    iconSize: 15,
                    radius: 8,
                    color: a.isImage ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, style: const TextStyle(fontSize: 12, height: 1.35)),
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
                  if (canFetch) ...[
                    const SizedBox(width: 6),
                    Icon(
                      a.isImage ? Icons.zoom_in_rounded : Icons.download_rounded,
                      size: 16,
                      color: cs.outline,
                    ),
                  ],
                ],
              ),
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuoteSheet(quote: quote),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: quote));
      _toast('已复制');
      return;
    }
    await _commentOn(quote);
  }

  /// 一轮 = 时间线上的一个节点。
  ///
  /// 原来是一条 2dp 竖线 + 两行字：读起来像「一段引用」，看不出先后，也看不出
  /// 哪一轮是**最新的**。改成时间线之后三件事一眼可辨：
  ///
  ///   · 圆点：最新一轮实心、旧的空心（先后有方向）；
  ///   · 连线：把轮次串成一条链（这是「任务链」的视觉，不是几个独立段落）；
  ///   · 胶囊标签：验收反馈用 error 色、完成总结用主色（语气不复用颜色）。
  Widget _roundTile(NxKvRound r, {required bool isFirst, required bool isLatest}) {
    final cs = Theme.of(context).colorScheme;
    final color = r.isFeedback ? cs.error : cs.primary;
    final line = cs.outlineVariant.withValues(alpha: 0.9);
    final dot = isLatest ? 9.0 : 7.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                // 上段连线：第一条不往上连
                SizedBox(
                  height: 5,
                  child: isFirst ? null : Center(child: Container(width: 1.5, color: line)),
                ),
                Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: isLatest ? color : cs.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: isLatest ? 1 : 0.55), width: 1.5),
                  ),
                ),
                // 下段连线：最后一轮（最新）不往下连
                Expanded(
                  child: isLatest ? const SizedBox.shrink() : Center(child: Container(width: 1.5, color: line)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLatest ? 0 : AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isLatest ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '第 ${r.index} 轮 · ${r.label}',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: isLatest ? FontWeight.w700 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.body.isEmpty ? '（没有正文）' : r.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: isLatest ? cs.onSurface.withValues(alpha: 0.88) : cs.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部动作条：只放「对这条任务能做什么」。
  ///
  /// 第 4 轮反馈第二条：「对于任务只标记完成，不要领任务的 btn」。所以这里
  /// **只有**「标完成」—— 没有「领取」。手机是验收端：活由 PC 上的 agent 领走，
  /// 人在手机上读正文、标完成、提反馈。
  ///
  /// 一条还没被领取的任务，标完成会被服务端拦下（`status=blocked`，
  /// `reason=not_claimed`）—— 那个 hint 原样弹出来，而不是把按钮藏掉：
  /// 「点不动」和「为什么点不动」是两件事，藏掉按钮只会让人以为页面坏了。
  ///
  /// 形制：两个**等宽胶囊** + 一颗圆形刷新。原来是两个 `TextButton.icon` 挨在
  /// 左边、右边一大片空 —— 动作条是这页唯一「会动手」的地方，用 Material 的
  /// 文字按钮等于把它降级成一行普通控件；胶囊 + 实心主操作才配得上它的分量。
  Widget _actionBar(kv.LocaltaskGetOutput t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 6, AppSpacing.sm, 6),
      child: Row(
        children: [
          Expanded(
            child: _PillButton(
              label: '标完成',
              icon: Icons.check_rounded,
              primary: true,
              busy: _busy,
              onTap: _busy ? null : _done,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _PillButton(
              label: '反馈',
              icon: Icons.rate_review_rounded,
              onTap: _busy ? null : _feedback,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _PillIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            onTap: _busy ? null : _load,
          ),
        ],
      ),
    );
  }
}

/// 动作条上的胶囊按钮：实心（主操作）/ 淡底（次操作）。
///
/// 高度固定 34：动作条总高 46，比原来的 44 多 2dp，但换来了一颗真正「按得下去」
/// 的按钮 —— 原来那两个 TextButton 的点击区只有文字那一小块。
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = primary ? cs.onPrimary : cs.onSurfaceVariant;
    final bg = primary ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.07);
    final faded = fg.withValues(alpha: 0.45);
    return NxKvPress(
      onTap: onTap,
      scale: 0.96,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: NxKvMotion.base,
        curve: NxKvMotion.soft,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? bg : bg.withValues(alpha: primary ? 0.35 : 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else
              Icon(icon, size: 15, color: enabled ? fg : faded),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: enabled ? fg : faded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动作条右侧的圆形图标按钮（刷新）。
class _PillIconButton extends StatelessWidget {
  const _PillIconButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final btn = NxKvPress(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: tooltip,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.onSurfaceVariant.withValues(alpha: enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, size: 16, color: enabled ? cs.outline : cs.outline.withValues(alpha: 0.4)),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return btn;
    return Tooltip(message: tooltip!, waitDuration: const Duration(milliseconds: 450), child: btn);
  }
}

/// 正文里**可以点的那一段**。
///
/// 每段都能「引用原文 + 评价」，但原来只有段标右边一行小字提示，段落本身按下去
/// 没有任何回应 —— 既不知道能不能点，也不知道点中的是哪一段。
///
/// 这里补的是**按下反馈**：一块淡主色底 + 左缘一道竖条，两者都画在 [Stack] 的
/// 背景层、且左右各外扩 6dp —— 文字位置分毫不动，否则一按整段文字平移，
/// 反而更难看（这也是不能用 `Container` 加 padding 的原因）。
class _BlockTap extends StatefulWidget {
  const _BlockTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_BlockTap> createState() => _BlockTapState();
}

class _BlockTapState extends State<_BlockTap> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: -6,
            right: -6,
            top: 1,
            bottom: 1,
            child: AnimatedContainer(
              duration: _down ? NxKvMotion.fast : NxKvMotion.base,
              curve: _down ? NxKvMotion.glide : NxKvMotion.snap,
              decoration: BoxDecoration(
                color: _down ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          Positioned(
            left: -6,
            top: 3,
            bottom: 3,
            width: 2.5,
            child: AnimatedContainer(
              duration: _down ? NxKvMotion.fast : NxKvMotion.base,
              curve: _down ? NxKvMotion.glide : NxKvMotion.snap,
              decoration: BoxDecoration(
                color: _down ? cs.primary.withValues(alpha: 0.55) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: widget.child),
        ],
      ),
    );
  }
}

/// 「点了一段」之后的那张面板。
///
/// Material 的 `ListTile + Divider` 在这里读起来像一张系统菜单；改成**一张圆角卡**：
/// 上面是引文（左缘一道主色竖条 —— 跟正文按压时冒出来的提示条同一套语言），
/// 下面是两行胶囊动作。这样「按住一段 → 引用 → 写评价」是一条连续的视觉动作，
/// 而不是「点一下弹了个菜单」。
class _QuoteSheet extends StatelessWidget {
  const _QuoteSheet({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: [
          BoxShadow(color: cs.shadow.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 抓手：告诉人这张卡是可以往下推走的
            Container(
              margin: const EdgeInsets.only(top: 9, bottom: 7),
              width: 34,
              height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 2.5)),
                ),
                child: Text(
                  quote.length > 140 ? '${quote.substring(0, 140)}…' : quote,
                  style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _row(
              context,
              icon: Icons.chat_bubble_rounded,
              color: cs.primary,
              title: '评价这一段',
              subtitle: '引用原文 + 写 md，落到任务正文的「反馈修改」',
              onTap: () => Navigator.of(context).pop('comment'),
            ),
            _row(
              context,
              icon: Icons.copy_all_rounded,
              title: '复制原文',
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return NxKvPress(
      onTap: onTap,
      semanticLabel: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
        child: Row(
          children: [
            NxKvIconTile(icon: icon, size: 28, iconSize: 15, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(fontSize: 10, color: cs.outline, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: cs.outline),
          ],
        ),
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
              color: cs.onSurfaceVariant.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppRadius.lg),
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
              Icon(Icons.broken_image_rounded, size: 15, color: cs.error),
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
        // 圆角跟附件卡同一档（AppRadius.lg）：图比卡圆得多会像贴在卡上的贴纸
        return NxKvPress(
          onTap: widget.onTap,
          scale: 0.985,
          semanticLabel: '查看图片 ${widget.attachment.name}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
      // 不用 AppBar：看图页的标题是「哪张图」，一行淡色文件名就够；
      // 常驻一条 56dp 的黑条只会把图往下压，跟「可视空间最大化」相抵。
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: FutureBuilder<Uint8List>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70));
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
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                child: Row(
                  children: [
                    _DarkCircleButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                      semanticLabel: '关闭',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Center(
                  child: Text(
                    '双指缩放 · 点空白处关闭',
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 黑底上的圆形图标按钮（看图页用）。
class _DarkCircleButton extends StatelessWidget {
  const _DarkCircleButton({required this.icon, required this.onTap, this.semanticLabel});

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return NxKvPress(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
