// 全局圆环 → KV 清单提交面板。
//
// 目标：点圆环 → 敲一句话 → 提交，全程不离开当前页面。
// 快捷 topic 只是"少打几个字"的糖，读失败不挡提交。
//
// 注意 groupId：圆环可能在用户从没打开过 KV 清单页时被点开，那时
// activeGroupProvider 还是初始值 0。所以提交前必须先 load() 一次，
// 否则会把任务写进服务端默认组，而不是用户选的工作空间。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../lab/demos/kvcli_todo/active_group_provider.dart';
import '../../lab/demos/kvcli_todo/todo_submit_service.dart';
import '../context_colors.dart';
import 'const_global_ring.dart';

/// 弹出提交面板。成功提交返回 true。
///
/// [context] 必须是一个带 Navigator 的 context —— 圆环挂在 Navigator 之上，
/// 它自己的 context 里没有 Navigator，调用方要传 `navigatorKey.currentContext`。
Future<bool> showRingSubmitSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RingSubmitSheet(),
  );
  return ok ?? false;
}

class _RingSubmitSheet extends ConsumerStatefulWidget {
  const _RingSubmitSheet();

  @override
  ConsumerState<_RingSubmitSheet> createState() => _RingSubmitSheetState();
}

class _RingSubmitSheetState extends ConsumerState<_RingSubmitSheet> {
  final _topicCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();

  List<String> _topics = const [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTopics());
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /// 解析当前工作空间的 groupId（0 → null，后端回落默认组）。
  Future<int?> _resolveGroupId() async {
    await ref.read(activeGroupProvider.notifier).load();
    return TodoSubmitService.toGroupId(ref.read(activeGroupProvider));
  }

  Future<void> _loadTopics() async {
    try {
      final gid = await _resolveGroupId();
      final topics =
          await ref.read(todoSubmitServiceProvider).loadTopics(groupId: gid);
      if (!mounted) return;
      setState(() => _topics = topics);
    } catch (_) {
      // 候选 chip 是锦上添花，读不到就退化成纯手工输入
    }
  }

  Future<void> _submit() async {
    final topic = _topicCtrl.text.trim();
    final text = _textCtrl.text.trim();
    if (topic.isEmpty || text.isEmpty) {
      _toast('主题与任务文本均必填');
      return;
    }

    setState(() => _submitting = true);
    try {
      final gid = await _resolveGroupId();
      await ref
          .read(todoSubmitServiceProvider)
          .submitQuick(topic: topic, text: text, groupId: gid);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('提交失败：$e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 键盘弹起时把面板顶上去
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: colors.outline),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '提交 KV 需求',
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (_topics.isNotEmpty) ...[
              _buildTopicChips(colors),
              const SizedBox(height: 10),
            ],
            _buildTopicField(colors),
            const SizedBox(height: 10),
            _buildTextField(colors),
            const SizedBox(height: 14),
            _buildSubmitButton(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicChips(ColorStrategy colors) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _topics.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = _topics[i];
          return GestureDetector(
            onTap: () {
              _topicCtrl.text = t;
              _textFocus.requestFocus();
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outline),
              ),
              child: Text(
                t,
                style: TextStyle(color: colors.textMuted, fontSize: 13),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopicField(ColorStrategy colors) {
    return TextField(
      controller: _topicCtrl,
      textInputAction: TextInputAction.next,
      style: TextStyle(color: colors.text),
      decoration: InputDecoration(
        labelText: '主题',
        hintText: '任务归到哪个 topic',
        labelStyle: TextStyle(color: colors.textMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTextField(ColorStrategy colors) {
    return TextField(
      controller: _textCtrl,
      focusNode: _textFocus,
      autofocus: true,
      minLines: 1,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      style: TextStyle(color: colors.text),
      decoration: InputDecoration(
        labelText: '任务文本',
        hintText: '一句话说清要做什么',
        labelStyle: TextStyle(color: colors.textMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSubmitButton(ColorStrategy colors) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ConstGlobalRing.size / 3),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('提交'),
      ),
    );
  }
}
