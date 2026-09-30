import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'dart:math' as math;

import '../../../api/pi/pi.dart';
import 'pi_chat_controller.dart';
import 'pi_chat_message.dart';
import 'pi_chat_settings.dart';
import 'pi_chat_settings_page.dart';

/// pi 聊天页 —— 建会话 / 发消息 / SSE 流式渲染 / 历史回读。
///
/// 控制器 [PiChatController] 持有状态；配置来自 [PiChatSettings]
/// （SharedPreferences），消息持久化在 Hive（重启回读即恢复）。
class PiChatPage extends StatefulWidget {
  final PiChatSettings settings;
  final String? initialSessionId;

  const PiChatPage({super.key, required this.settings, this.initialSessionId});

  @override
  State<PiChatPage> createState() => _PiChatPageState();
}

class _PiChatPageState extends State<PiChatPage> {
  late final PiChatController _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// 初始化异常（非 null 时渲染错误页而不是聊天界面）。
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _controller = PiChatController(settings: widget.settings);
    _controller.addListener(_onChange);
    _scroll.addListener(_onScroll);
    // 草稿：输入即存（切会话/退出不丢字 —— 复评 P2-8）
    _input.addListener(_saveDraft);
    _init();
  }

  Future<void> _init() async {
    // 初始化失败**不能**白屏：Hive/path_provider 在异常平台或通道缺失时会抛，
    // 这里捕获后交给 _initError 渲染可读错误页（带重试）。
    try {
      await _controller.ensureInit();
      final sid = widget.initialSessionId;
      if (sid != null && sid.isNotEmpty) {
        await _controller.openSession(sid);
        unawaited(_controller.refreshContextUsage());
      }
      if (mounted) setState(() => _initError = null);
    } catch (e) {
      if (mounted) setState(() => _initError = e);
    }
  }

  /// 草稿 key（无会话时用占位，建会话后迁移）。
  String get _draftKey => _controller.sessionId ?? '__new__';

  String _lastDraftKey = '__new__';

  void _saveDraft() {
    widget.settings.setDraft(_draftKey, _input.text);
  }

  /// 本会话草稿回填（进页面 / 切会话时）。
  void _restoreDraft() {
    final key = _draftKey;
    if (key == _lastDraftKey) return;
    _lastDraftKey = key;
    final draft = widget.settings.draftOf(key);
    if (draft.isNotEmpty && _input.text.isEmpty) {
      _input.text = draft;
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    }
  }

  /// 重新初始化（错误页的重试按钮）。
  Future<void> _retryInit() async {
    setState(() => _initError = null);
    await _init();
  }

  /// 是否显示「滚动到底」浮标（用户不在底部时）。
  bool _showScrollToBottom = false;

  /// 距底部多少像素内算「在底部」。
  static const double _bottomThreshold = 80;

  bool get _isAtBottom {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return (pos.maxScrollExtent - pos.pixels) <= _bottomThreshold;
  }

  void _onScroll() {
    final show = !_isAtBottom;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onChange() {
    if (mounted) {
      _restoreDraft();
      setState(() {});
    }
    // 只在用户本来就贴着底部时才自动跟随（上翻看历史时不打断他）
    if (_scroll.hasClients && _isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          // 平滑跟随（ChatGPT/Claude 的做法）：短动画而非硬拽，
          // 长回复时不抖动。用户主动上翻时 _isAtBottom 变 false 自动停跟。
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
          if (_showScrollToBottom) setState(() => _showScrollToBottom = false);
        }
      });
    } else if (_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && !_showScrollToBottom) {
          setState(() => _showScrollToBottom = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _scroll.removeListener(_onScroll);
    _input.removeListener(_saveDraft);
    _controller.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // 流式/创建会话进行中**不清输入框**（两类忙态都由 controller 层拒绝；
    // 此前只查 sending —— 创建会话最长 180s 的窗口把同样一类数据丢失
    // 重新引进来，第 6 次复评探针实锤）。
    if (_controller.sending || _controller.creating) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_controller.creating
            ? '正在创建会话，请稍候（输入已保留）'
            : '正在生成回复，请稍候（输入已保留）'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _input.clear();
    widget.settings.setDraft(_draftKey, '');
    // 待发图片 → pi 的 images 参数（[{type:image,data,mimeType}]）
    List<Object>? images;
    if (_controller.hasPendingImages) {
      images = [
        for (final img in _controller.pendingImages)
          {
            'type': 'image',
            'data': img.base64,
            'mimeType': img.name.endsWith('.png') ? 'image/png' : 'image/jpeg',
          },
      ];
    }
    final accepted = await _controller.send(text, images: images);
    // 未被受理（建会话失败/网络不通等）→ 把文本**回填输入框**，
    // 否则用户输入被永久吞掉（第 8 次复评 P2 实锤）。
    if (!accepted && mounted && _input.text.isEmpty) {
      _input.text = text;
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    }
  }

  /// 选图（相册）→ base64 入待发队列。
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      _controller.addImage(x.name, base64Encode(bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选图失败: $e')),
        );
      }
    }
  }

  /// 模型选择底部弹层：拉服务端清单 → 点选 → set_model 命令。
  Future<void> _showModelPicker() async {
    final endpoint = PiModelsEndpoint(config: () => widget.settings.toApiConfig());
    try {
      final catalog = await endpoint.list();
      if (!mounted) return;
      final current = _controller.currentModelId;
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('选择模型',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              if (catalog.models.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('服务端未返回可用模型（请在 pi-web 设置页配置模型凭据）',
                      style: Theme.of(ctx).textTheme.bodySmall),
                )
              else
                for (final m in catalog.models)
                  ListTile(
                    leading: Icon(
                      m.qualifiedId == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                    ),
                    title: Text(m.displayName),
                    subtitle: Text(m.qualifiedId,
                        style: Theme.of(ctx).textTheme.bodySmall),
                    onTap: () => Navigator.pop(ctx, m.qualifiedId),
                  ),
            ],
          ),
        ),
      );
      if (selected != null && selected != current) {
        await _controller.switchModel(selected);
      }
    } on PiApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取模型清单失败: ${e.message}')),
        );
      }
    } finally {
      endpoint.close();
    }
  }

  /// 改名对话框（AppBar 长按触发）。
  Future<void> _renameDialog() async {
    final controller = TextEditingController(text: _controller.sessionName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '会话名'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      await _controller.renameSession(controller.text);
    }
    controller.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PiChatSettingsPage(settings: widget.settings),
    ));
    setState(() {}); // 设置可能已变化
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 初始化失败优先展示错误页（避免整页空白）
    final initError = _initError;
    if (initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('pi')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.storage_outlined,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('本地存储初始化失败', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText('$initError',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retryInit,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final configured = _controller.canChat;
    return Scaffold(
      appBar: AppBar(
        // 会话名优先（服务端 rename 的结果）；没有才退化。
        // 不再显示 sessionId 乱码（复评 #6）。长按改名（rename 端点此前
        // 在库里躺了六轮没有 UI 入口 —— 复评 #1）。
        // 副标题：上下文占用（ChatGPT/Claude 都有容量提示；复评 P2-8）
        bottom: (_controller.contextUsage == null ||
                ((_controller.contextUsage?['percent'] as num?) ?? 0) <= 0)
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(14),
                child: _ContextBar(usage: _controller.contextUsage!),
              ),
        title: GestureDetector(
          onLongPress: _controller.sessionId == null
              ? null
              : () => _renameDialog(),
          child: Text(() {
            final name = _controller.sessionName;
            if (name != null && name.isNotEmpty) return 'pi · $name';
            if (_controller.sessionId == null) return 'pi 新对话';
            return 'pi 对话';
          }()),
        ),
        actions: [
          // 模型切换（复评 #9：端点全在库里却让用户手填字符串）
          IconButton(
            tooltip: '切换模型',
            icon: const Icon(Icons.tune),
            onPressed: configured ? _showModelPicker : null,
          ),
          IconButton(
            tooltip: _controller.creating
                ? '正在创建…'
                : _controller.sending
                    ? '生成中，请先中止'
                    : '新建会话',
            icon: _controller.creating
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_comment_outlined),
            // 发送中/创建中禁用：切走会泄漏气泡；无防重入会点出 N 个会话。
            onPressed: configured && !_controller.sending && !_controller.creating
                ? () => _controller.newSession()
                : null,
          ),
          if (_controller.sending)
            IconButton(
              tooltip: '中止',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => _controller.abort(),
            ),
          // 思考档位 + 设置（合并进菜单，AppBar 不再拥挤）
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'settings') {
                _openSettings();
              } else if (v.startsWith('think:')) {
                _controller.setThinkingLevel(v.substring(6));
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                enabled: false,
                height: 28,
                child: Text('思考档位', style: TextStyle(fontSize: 12)),
              ),
              for (final lvl in const [
                'off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'
              ])
                PopupMenuItem(
                  value: 'think:$lvl',
                  height: 36,
                  child: Row(
                    children: [
                      Icon(
                        _controller.thinkingLevel == lvl
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(_thinkingLabel(lvl)),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'settings',
                height: 40,
                child: Row(children: [
                  Icon(Icons.settings_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('设置'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: !configured
          ? _NotConfiguredView(onOpenSettings: _openSettings)
          : Column(
              children: [
                if (_controller.lastError != null)
                  Material(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline),
                      title: Text(_controller.lastError!,
                          style: theme.textTheme.bodySmall),
                      // 可手动关闭（此前常驻直到下次成功发送 —— 评分 #11）
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _controller.clearError,
                        tooltip: '关闭',
                      ),
                    ),
                  ),
                Expanded(
                  child: _controller.messages.isEmpty
                      ? _EmptyChatView(hasSession: _controller.sessionId != null)
                      : Stack(
                          children: [
                            ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              itemCount: _controller.messages.length,
                              itemBuilder: (context, i) {
                                final msgs = _controller.messages;
                                final m = msgs[i];
                                // 日期分隔条（复评：跨天会话只有 HH:mm 定位不了）
                                final prev = i > 0 ? msgs[i - 1] : null;
                                final showDay = prev == null ||
                                    !_sameDay(prev.createdAt, m.createdAt);
                                final bubble = _Bubble(
                                  message: m,
                                  // 携带这一条的身份（多失败轮次时不带身份会
                                  // 重发错内容 —— 第 7 次复评探针 G）
                                  onRetry: m.error != null
                                      ? () => _controller.retryLast(
                                            failedMessage: m,
                                          )
                                      : null,
                                );
                                if (!showDay) return bubble;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _DayDivider(day: m.createdAt),
                                    bubble,
                                  ],
                                );
                              },
                            ),
                            // 「滚动到底」浮标：用户上翻看历史时出现，一键回到最新
                            if (_showScrollToBottom)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: FloatingActionButton.small(
                                  heroTag: 'pi_scroll_bottom',
                                  onPressed: _jumpToBottom,
                                  tooltip: '回到最新',
                                  child: const Icon(Icons.arrow_downward),
                                ),
                              ),
                          ],
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 待发图片预览条（复评 P2-8：图片输入此前零 UI）
                        if (_controller.hasPendingImages)
                          SizedBox(
                            height: 56,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (var i = 0;
                                    i < _controller.pendingImages.length;
                                    i++)
                                  Stack(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: MemoryImage(base64Decode(
                                                _controller
                                                    .pendingImages[i].base64)),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _controller.removeImage(i),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.error,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close,
                                                size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        Row(
                      children: [
                        // 附件（拍照/相册；prompt 的 images 端点此前零 UI）
                        IconButton(
                          tooltip: '添加图片',
                          icon: const Icon(Icons.image_outlined),
                          onPressed: _pickImage,
                        ),
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              // 桌面：Enter（无 Shift）发送；Shift+Enter 换行
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                _send();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                            controller: _input,
                            // 关键路径：进页面即可打字（少一次点击）
                            autofocus: true,
                            minLines: 1,
                            maxLines: 5,
                            // 软键盘显示「换行」而不是「发送」：桌面/外接键盘上
                            // 换行键可达（此前 TextInputAction.send 占用了它，
                            // maxLines:5 形同虚设 —— 复评 #13）。发送用按钮，
                            // 桌面回车仍然发送（onSubmitted）。
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: '发消息…',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: (_controller.sending || _controller.creating)
                              ? null
                              : _send,
                          icon: _controller.sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                        ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final PiChatMessage message;

  /// 失败重发回调（仅 assistant 错误气泡用；null 表示不可重发）。
  final VoidCallback? onRetry;

  const _Bubble({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final hasError = message.error != null;
    final isStreaming = !message.done;

    final color = isUser
        ? theme.colorScheme.primaryContainer
        : (hasError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest);
    final fg = isUser
        ? theme.colorScheme.onPrimaryContainer
        : (hasError
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onSurface);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 长按气泡 = 复制（与系统 IM 一致的手势）
            GestureDetector(
              onLongPress: message.text.isEmpty
                  ? null
                  : () => _copy(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                // 宽度基于布局约束而非屏幕尺寸：横屏/平板/分屏下都成立
                constraints: BoxConstraints(
                    maxWidth: math.min(
                        MediaQuery.of(context).size.width * 0.78, 520)),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 工具活动（agent 的核心过程）：显示在正文之前，
                    // 让用户在等待时看得到「它在干活」
                    if (message.toolActivity.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.build_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.55)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                message.toolActivity,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (message.text.isEmpty && message.pending)
                      Text('发送中…',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: fg.withValues(alpha: 0.6)))
                    else if (message.done && message.text.isEmpty &&
                        message.error == null && !isUser)
                      // 纯工具调用轮：模型只调了工具没输出文本。此前落到
                      // SelectableText('') = 零高度空气泡，用户只看到一个裸
                      // 时间戳，不知发生了什么（第 8 次复评 P5 探针 E）。
                      Text('本轮无文本输出（见上方工具活动）',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: fg.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ))
                    else if (isStreaming && message.text.isEmpty)
                      // 首个 delta 到达前的「正在思考」三点（复评 #9：
                      // 空白色块毫无信息量）
                      _ThinkingDots(color: fg)
                    else if (!isUser && message.done)
                      // agent 回复含代码/列表/加粗：完成后走 markdown 渲染
                      //（流式中保持纯文本，避免半截语法闪烁）。
                      // SelectionArea 包一层：MarkdownRendererWidget 内部是
                      // selectable:false（全项目共享组件的性能取舍，不在这里改它），
                      // 但回复恰恰最需要选中复制（复评多轮扣分项）。
                      SelectionArea(
                        // 代码块增强：独立容器 + 横向滚动 + 复制按钮
                        //（复评 #6：agent 输出代码是高频内容，此前只能整条复制）
                        child: MarkdownBody(
                          data: message.text,
                          selectable: false,
                          shrinkWrap: true,
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.4, color: fg),
                            code: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurface,
                              backgroundColor: Colors.transparent,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: theme.colorScheme.surface
                                  .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                            // 气泡内标题阶收紧（复评 P2-7：h1 复用 headlineLarge
                            // 在 520px 气泡里过大）
                            h1: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            h2: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            h3: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          // 只注册块级 'pre'：此前注册 'code' 会把**行内代码**
                          // 也渲染成全宽块 + 复制按钮（第 9 次复评探针 H）
                          builders: {
                            'pre': _CodeBlockBuilder(theme: theme, fg: fg),
                          },
                        ),
                      )
                    else
                      SelectableText(message.text,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: fg, height: 1.35)),
                    // 流式末尾的闪烁光标（"正在生成"的视觉信号）
                    if (isStreaming && message.text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _TypingCursor(color: fg),
                    ],
                    // 中止/中断的独立状态行（stopped 是字段，不污染正文）
                    if (message.stopped && message.done) ...[
                      const SizedBox(height: 4),
                      Text('已停止',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg.withValues(alpha: 0.6),
                          )),
                    ],
                    if (hasError) ...[
                      const SizedBox(height: 6),
                      Text(message.error!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                      if (onRetry != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('重发'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            // 元信息行：时间戳 + 状态（状态按语义着色 —— 此前一刀切
            // onSurface alpha .45，失败与进行中视觉无差，复评 P2）
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                _metaLine(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _metaColor(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine() {
    final t = message.createdAt;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final stamp = '$hh:$mm';
    if (message.role == 'user' && message.pending) return '$stamp · 发送中';
    if (message.error != null) return '$stamp · 失败';
    if (!message.done) return '$stamp · 生成中';
    return stamp;
  }

  Color? _metaColor(ThemeData theme) {
    if (message.error != null) return theme.colorScheme.error;
    if (message.role == 'user' && message.pending) {
      return theme.colorScheme.primary;
    }
    if (!message.done) return theme.colorScheme.tertiary;
    return theme.colorScheme.onSurface.withValues(alpha: 0.45);
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 流式末尾的闪烁光标。
class _TypingCursor extends StatefulWidget {
  final Color color;

  const _TypingCursor({required this.color});

  @override
  State<_TypingCursor> createState() => _TypingCursorState();
}

class _TypingCursorState extends State<_TypingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 8,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _NotConfiguredView extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _NotConfiguredView({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text('尚未配置 pi 服务',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('需要服务地址与 device token', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

/// 空态：企业级做法是给「这是什么 + 下一步做什么」，而不是一行灰字。
class _EmptyChatView extends StatelessWidget {
  final bool hasSession;

  const _EmptyChatView({required this.hasSession});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.forum_outlined,
                  size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              hasSession ? '开始对话' : 'pi 对话',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '直接在下方输入即可。\n'
              '回复由服务端 pi agent 流式返回，可随时中止。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「正在思考」三点跳动（首个流式 delta 到达前的占位指示）。
class _ThinkingDots extends StatefulWidget {
  final Color color;

  const _ThinkingDots({required this.color});

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // 三个点错相跳动
            final phase = (_c.value - i * 0.2) % 1.0;
            final lift = (phase < 0.5 ? phase : 1 - phase) * 2; // 0..2
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, -lift),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.5 + lift * 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 两个时间是否同一天。
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 日期分隔条（今天 / 昨天 / 具体日期）。
class _DayDivider extends StatelessWidget {
  final DateTime day;

  const _DayDivider({required this.day});

  static String label(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return '今天';
    final y = now.subtract(const Duration(days: 1));
    if (_sameDay(d, y)) return '昨天';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label(day),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// 思考档位的中文标签。
String _thinkingLabel(String level) => const {
      'off': '关闭',
      'minimal': '最少',
      'low': '低',
      'medium': '中',
      'high': '高',
      'xhigh': '极高',
      'max': '最大',
    }[level] ??
    level;

/// AppBar 下方的上下文占用细条（ChatGPT/Claude 的容量提示）。
class _ContextBar extends StatelessWidget {
  final Map<String, dynamic> usage;

  const _ContextBar({required this.usage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (usage['percent'] is num)
        ? (usage['percent'] as num).toDouble()
        : 0.0;
    final ratio = (percent / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.08),
                color: ratio > 0.85
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '上下文 ${percent.toStringAsFixed(0)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// 代码块构建器：等宽字体 + 横向滚动 + 右上角复制按钮。
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  final Color fg;

  _CodeBlockBuilder({required this.theme, required this.fg});

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // ★ flutter_markdown 的块级 builder 契约：visitText 必须产内容。
    // 缺这个会让「行内样式元素 + 代码块收尾」形态（agent 回复最高频：
    // 「行内样式元素 + 代码块收尾」形态触发 builder.dart:267 断言崩溃
    //（第 10 次复评探针 S5c 实锤 debug 红屏）。文本交给 visitElementAfter。
    return Text(
      text.text,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
    );
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _build(element.textContent);
  }

  Widget _build(String code) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 顶掉默认样式，避免与 MarkdownBody 的 pre 装饰叠加
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Builder(builder: (context) {
            return IconButton(
              tooltip: '复制代码',
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('代码已复制'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            );
          }),
        ),
      ],
    );
  }
}
