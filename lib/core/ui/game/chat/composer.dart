part of 'main.dart';

/// 嵌入式 composer：emoji 行 + 文字输入 + 发送
/// 仅 _composerOpen 时构造；文字草稿与输入控件由 [_BoardChatOverlayState] 持有，
/// 关闭时草稿存 _draftText、controller / focusNode 由宿主复用，重开不丢内容。
class _Composer extends StatefulWidget {
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final bool enabled;
  final bool sending;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ValueChanged<String> onTextChanged;
  final Future<void> Function(String emojiId) onSendEmoji;

  /// 返回 true = 已发出（据此决定是否清空输入框）
  final Future<bool> Function(String text) onSendText;
  final VoidCallback onClose;
  // 双 tab 记录面板：本局对话历史（去重后展示）
  final List<ChatEvent> events;
  final String myDeviceId;

  const _Composer({
    required this.emojiBundle,
    required this.fileResolver,
    required this.enabled,
    required this.sending,
    required this.textController,
    required this.focusNode,
    required this.onTextChanged,
    required this.onSendEmoji,
    required this.onSendText,
    required this.onClose,
    required this.events,
    required this.myDeviceId,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  // 双 tab 状态：'emoji' / 'history'
  String _tab = 'emoji';

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    widget.onTextChanged(widget.textController.text);
  }

  @override
  void dispose() {
    widget.textController.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _doSendEmoji(String id) async {
    await widget.onSendEmoji(id);
  }

  Future<void> _doSendText() async {
    final text = widget.textController.text.trim();
    if (text.isEmpty || !widget.enabled || widget.sending) return;
    // 发送成功才清空：被节流 / 失败时保留草稿，避免用户输入被吞
    final sent = await widget.onSendText(text);
    if (!mounted || !sent) return;
    widget.textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        // mock: border:1px solid var(--text-1) 硬黑边（F2 身份色）
        side: const BorderSide(color: Color(0xFF1A1A1A)),
      ),
      // mock: box-shadow 0 8px 24px rgba(0,0,0,0.14) + 0 2px 4px rgba(0,0,0,0.06)
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          // mock: padding: 8px 4px 8px 8px (LTRB) — top 从 4 → 8
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部 head：双 tab + 关闭按钮
              _buildHead(scheme),
              const SizedBox(height: 6),
              // tab 内容区
              if (_tab == 'emoji')
                _buildEmojiGrid(scheme)
              else
                _buildHistoryList(scheme),
              const SizedBox(height: 6),
              // 文字输入 + 发送（底部固定）
              _buildInputRow(scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部 head：表情 / 记录 tab（segmented control 容器）+ 关闭按钮
  /// mock .tabs: bg #FAFAF7, radius 6, padding 2, gap 2 (F2 风格分段控件)
  Widget _buildHead(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAF7), // var(--bg)
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                _buildTab('表情', 'emoji', scheme),
                _buildTab('记录', 'history', scheme,
                    count: _uniqueHistory().length),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 关闭按钮
        InkWell(
          onTap: widget.onClose,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 16, color: Color(0xFF9B9B9B)),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, String key, ColorScheme scheme, {int? count}) {
    final active = _tab == key;
    final badge = (count != null && count > 0)
        ? Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFC2410C) : const Color(0xFF2A6FDB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : null;
    return InkWell(
      onTap: () => setState(() => _tab = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            if (badge != null) badge,
          ],
        ),
      ),
    );
  }

  /// emoji tab：从 [EmojiBundle] 渲染 KV 上的真实表情图片
  /// （board_chat_overlay.dart 原版 line 810-834 的行为）。
  Widget _buildEmojiGrid(ColorScheme scheme) {
    final entries = widget.emojiBundle.entries;
    if (entries.isEmpty) {
      // 表情包尚未加载完成（chess_room_page 的 _ensureEmojiBundle 异步）——
      // 占位避免空 grid 闪一下。
      return const SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 156),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        childAspectRatio: 1.0,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        padding: EdgeInsets.zero,
        children: [
          for (final entry in entries)
            InkResponse(
              onTap: widget.enabled && !widget.sending
                  ? () => _doSendEmoji(entry.id)
                  : null,
              radius: 18,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(6),
                child: _EmojiImage(
                  image: entry.imageProvider(widget.fileResolver),
                  id: entry.id,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 记录 tab：本局 ChatEvent 列表（去重）
  Widget _buildHistoryList(ColorScheme scheme) {
    final items = _uniqueHistory();
    if (items.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: Text(
          '还没有消息',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 156),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 3),
        itemBuilder: (ctx, i) {
          final e = items[i];
          final isMe = e.from == widget.myDeviceId;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFF2A6FDB) : const Color(0xFFC2410C),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isMe ? '我' : '对方',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isMe ? const Color(0xFF2A6FDB) : const Color(0xFFC2410C),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildHistoryBody(e, scheme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryBody(ChatEvent e, ColorScheme scheme) {
    if (e.isEmoji) {
      final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
      if (entry == null) {
        return const SizedBox(width: 22, height: 22);
      }
      return SizedBox(
        width: 22,
        height: 22,
        child: _EmojiImage(
          image: entry.imageProvider(widget.fileResolver),
          id: entry.id,
        ),
      );
    }
    return Text(
      e.text ?? '',
      style: TextStyle(
        fontSize: 11,
        height: 1.3,
        color: scheme.onSurface,
      ),
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: widget.textController,
              focusNode: widget.focusNode,
              // 发送在途时不再禁用输入框：禁用会让聚焦中的输入框失焦、
              // 收起 IME，连发体验很差；重复发送由 _doSendText 的 sending
              // 守卫 + 按钮可用态兜住。
              enabled: widget.enabled,
              maxLines: 1,
              maxLength: 40,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _doSendText(),
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: '说点什么…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                counterText: '',
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // 可用态必须跟着输入内容实时刷新：此前 onPressed 直接读
        // textController.text，但 textController 的 listener 只把草稿转给父层
        // （父层不 setState），本层不 rebuild → 输入后按钮仍是灰的，得切 tab
        // 触发重建才会亮。这里用 ValueListenableBuilder 只重建按钮本身。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.textController,
          builder: (ctx, value, _) {
            final canSend = widget.enabled &&
                !widget.sending &&
                value.text.trim().isNotEmpty;
            return SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: canSend ? _doSendText : null,
                // mock: 黑色 1px 边框 + 黑色背景 + 白字 + radius 6 (F2 硬黑 identity)
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFF1A1A1A)),
                  ),
                ),
                child: const Text('发', style: TextStyle(fontSize: 12)),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 提取本局去重历史（仅保留文字/表情）
  List<ChatEvent> _uniqueHistory() {
    final seen = <String>{};
    final out = <ChatEvent>[];
    for (final e in widget.events) {
      final key = '${e.kind.name}:${e.id}:${e.seq}';
      if (seen.add(key)) out.add(e);
    }
    return out;
  }
}
