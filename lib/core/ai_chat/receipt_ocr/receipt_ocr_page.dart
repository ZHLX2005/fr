import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../services/ai_chat/ai_chat_provider.dart';
import '../../../services/message_strategy/data/receipt_ocr_message_data.dart';
import '../../../services/message_strategy/factory/factory.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../ai_chat_settings_page.dart';
import 'receipt_ocr_api.dart';
import 'receipt_ocr_history.dart';
import 'receipt_ocr_history_store.dart';

/// 小票 OCR 聊天页 —— IM 风格。
///
/// 用户从相册/相机选图 → 右侧用户气泡（缩略图）→ 调 flex 接口 →
/// 左侧 assistant 气泡（receipt_ocr 交互卡，每行 ✓ 记入 / × 拒绝）。
///
/// LLM 配置（apiKey/model/baseURL/type）共享 [AIChatProvider] 的 settings，
/// 与 ai_chat_settings_page 同一份，不重复存储。
class ReceiptOcrPage extends StatefulWidget {
  const ReceiptOcrPage({super.key});

  @override
  State<ReceiptOcrPage> createState() => _ReceiptOcrPageState();
}

/// 单条聊天记录。user 图片在右，assistant 卡片 / loading 在左。
class _ChatEntry {
  final String id;
  final bool isUser;
  final String? imagePath; // user 图片本地路径
  final IMessageData? card; // assistant 卡片（receipt_ocr）
  final bool isLoading;

  const _ChatEntry({
    required this.id,
    required this.isUser,
    this.imagePath,
    this.card,
    this.isLoading = false,
  });
}

class _ReceiptOcrPageState extends State<ReceiptOcrPage> {
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final ReceiptOcrApi _api = ReceiptOcrApi();
  final List<_ChatEntry> _entries = [];

  /// 当前选中的待发送图片（选完才显示发送按钮）。
  String? _pendingImage;
  bool _busy = false;

  late final MessageWidgetFactory _factory =
      GetIt.instance<MessageWidgetFactory>();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// 启动时从 prefs 加载历史记录到聊天列表。
  /// 用户发新消息也会 append 到历史；只在用户主动清理时才删。
  Future<void> _loadHistory() async {
    final list = await ReceiptOcrHistoryStore.load();
    if (!mounted) return;
    final entries = <_ChatEntry>[];
    for (final h in list) {
      final absPath = await ReceiptOcrHistoryStore.resolveImagePath(h.imageFileName);
      if (absPath == null) continue; // 图片已被外部删除则跳过
      entries.add(_ChatEntry(
        id: '${h.id}-u',
        isUser: true,
        imagePath: absPath,
      ));
      entries.add(_ChatEntry(
        id: '${h.id}-a',
        isUser: false,
        card: ReceiptOcrMessageData(result: h.result, historyId: h.id),
      ));
    }
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
    });
    if (_entries.isNotEmpty) _scrollToBottom();
  }

  /// 用户主动清理：清空 prefs + 删除 docs 里的所有图片 + 重置当前列表。
  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理历史记录'),
        content: const Text('确定清空所有小票识别历史？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ReceiptOcrHistoryStore.clear();
    if (!mounted) return;
    setState(() => _entries.clear());
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent.isFinite) {
        _scroll.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _pendingImage = x.path);
  }

  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x != null) setState(() => _pendingImage = x.path);
  }

  Future<void> _send() async {
    final path = _pendingImage;
    if (path == null || _busy) return;

    final settings = context.read<AIChatProvider>().settings;
    if (!settings.isConfigured) {
      _promptConfig();
      return;
    }

    setState(() {
      _busy = true;
      _pendingImage = null;
      _entries.add(_ChatEntry(id: _uid(), isUser: true, imagePath: path));
      _entries.add(_ChatEntry(id: _uid(), isUser: false, isLoading: true));
    });
    _scrollToBottom();

    try {
      final bytes = await File(path).readAsBytes();
      final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final result = await _api.recognize(settings: settings, imageBase64: b64);

      if (!mounted) return;
      // 写历史（图片复制到 docs，结果存 prefs）
      final history = ReceiptOcrHistory(
        id: _uid(),
        createdAt: DateTime.now(),
        result: result,
        imageFileName: 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ReceiptOcrHistoryStore.add(
        history: history,
        sourceImagePath: path,
      );

      setState(() {
        // 用卡片替换最后一条 loading
        final lastIdx = _entries.indexWhere((e) => e.isLoading);
        if (lastIdx >= 0) {
          _entries[lastIdx] = _ChatEntry(
            id: '${history.id}-a',
            isUser: false,
            card: ReceiptOcrMessageData(result: result, historyId: history.id),
          );
        }
        _busy = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final lastIdx = _entries.indexWhere((e) => e.isLoading);
        if (lastIdx >= 0) {
          // loading 替换成错误提示文本卡
          _entries[lastIdx] = _ChatEntry(
            id: _uid(),
            isUser: false,
            card: _ErrorCardData(message: '识别失败：$e'),
          );
        }
        _busy = false;
      });
      _scrollToBottom();
    }
  }

  void _promptConfig() => _openSettings(prompt: true);

  void _openSettings({bool prompt = false}) {
    if (prompt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先配置 LLM API Key'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: _navigateToSettings,
          ),
        ),
      );
      return;
    }
    _navigateToSettings();
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AIChatSettingsPage()),
    );
  }

  String _uid() => '${DateTime.now().microsecondsSinceEpoch}-${_entries.length}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(Icons.receipt_long, size: 18, color: accent),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('小票', style: TextStyle(fontSize: 16)),
                  Text(
                    'OCR 识别 → 快速比价',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 清理历史（边框强调 IconButton）
          IconButton(
            tooltip: '清理历史',
            onPressed: _entries.isEmpty ? null : _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          // 设置（边框强调 IconButton）
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? _buildEmpty(theme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _buildBubble(_entries[i], theme),
                  ),
          ),
          _buildInputBar(theme, accent),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatEntry e, ThemeData theme) {
    if (e.isUser) {
      // 用户图片气泡：右对齐
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.55,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.zero,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(e.imagePath!), fit: BoxFit.cover),
          ),
        ),
      );
    }

    // assistant 气泡：左对齐
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        child: e.isLoading
            ? _buildLoading(theme)
            : e.card is _ErrorCardData
                ? _buildError(theme, (e.card as _ErrorCardData).message)
                : _factory.create(context, e.card!),
      ),
    );
  }

  Widget _buildError(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.zero,
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.zero,
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '识别中…',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme, Color accent) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            // 相册
            _iconBtn(
              icon: Icons.photo_outlined,
              color: accent,
              onTap: _busy ? null : _pickFromGallery,
              tooltip: '相册',
            ),
            const SizedBox(width: 4),
            // 相机
            _iconBtn(
              icon: Icons.camera_alt_outlined,
              color: accent,
              onTap: _busy ? null : _pickFromCamera,
              tooltip: '拍照',
            ),
            const SizedBox(width: 8),
            // 待发送图片缩略图 or 提示
            Expanded(
              child: _pendingImage != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_pendingImage!),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _pendingImage = null),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close,
                                    size: 12,
                                    color: theme.colorScheme.onError),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      '选一张小票图片开始识别',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // 发送
            _sendBtn(accent, theme),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    final disabled = onTap == null;
    final c = disabled ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1),
      ),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: c),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _sendBtn(Color accent, ThemeData theme) {
    final enabled = _pendingImage != null && !_busy;
    final c = enabled ? accent : accent.withValues(alpha: 0.35);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1.5),
      ),
      child: IconButton(
        onPressed: enabled ? _send : null,
        tooltip: '发送',
        icon: _busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c),
              )
            : Icon(Icons.send, size: 20, color: c),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final hintColor = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '小票 OCR',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hintColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点底部相册 / 相机选一张小票，\n识别后每行可 ✓ 记入比价 / × 拒绝',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: hintColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 识别失败的简易文本卡（不走 strategy，直接渲染）。
/// 复用 IMessageData 接口让 factory 无需特判 —— 但 factory 不认识这个 type，
/// 故这里不通过 factory，而是页面内联渲染（见 _buildBubble 调用处需特判）。
/// 简化：这里直接定义，_buildBubble 里 card 是它时直接渲染 Container。
class _ErrorCardData implements IMessageData {
  final String message;
  const _ErrorCardData({required this.message});
  @override
  String get type => '__receipt_error';
}