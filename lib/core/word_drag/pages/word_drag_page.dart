import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/draggable_word_card_controller.dart';
import '../providers/word_drag_state.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/word_card_content.dart';
import 'word_detail_page.dart';

/// 单词拖拽背词页面
/// 使用 ChangeNotifier 模式管理状态
class WordDragPage extends StatelessWidget {
  const WordDragPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WordDragNotifier(),
      child: const _WordDragPageContent(),
    );
  }
}

class _WordDragPageContent extends StatefulWidget {
  const _WordDragPageContent();

  @override
  State<_WordDragPageContent> createState() => _WordDragPageContentState();
}

class _WordDragPageContentState extends State<_WordDragPageContent> {
  final DraggableWordCardController _cardController = DraggableWordCardController();
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = context.read<WordDragNotifier>();
      notifier.setNavigateCallback(_navigateToDetail);
    });
  }

  void _navigateToDetail() {
    final notifier = context.read<WordDragNotifier>();
    final word = notifier.state.currentWord;
    if (word == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WordDetailPage(
          word: word,
          onComplete: () {
            notifier.onDetailPageComplete();
          },
        ),
      ),
    );
  }

  void _handleOffsetChanged(Offset offset) {
    final notifier = context.read<WordDragNotifier>();
    final screenSize = MediaQuery.of(context).size;

    if (!_isDragging) {
      // 拖动开始
      _isDragging = true;
      notifier.onDragStart();
    }

    notifier.onDragUpdate(offset, screenSize);
  }

  void _handleDragEnd() {
    if (_isDragging) {
      _isDragging = false;
      final notifier = context.read<WordDragNotifier>();
      final screenSize = MediaQuery.of(context).size;
      notifier.onDragEnd(screenSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Stack(
          children: [
            // 顶部进度
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: _buildProgressIndicator(state),
            ),

            // 中心卡片
            Center(
              child: state.hasNextWord
                  ? _buildCardStack(notifier, state)
                  : _buildEmptyState(notifier),
            ),

            // 右上角标新区
            if (state.hasNextWord)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.15,
                child: Opacity(
                  opacity: state.markZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.bookmark_add_outlined,
                    label: '标新',
                    isActive: state.isInMarkZone,
                    onTap: state.isInMarkZone ? notifier.onZoneConfirmed : null,
                  ),
                ),
              ),

            // 右下角删除区
            if (state.hasNextWord)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.60,
                child: Opacity(
                  opacity: state.deleteZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.delete_outline,
                    label: '删除',
                    isActive: state.isInDeleteZone,
                    isDelete: true,
                    onTap: state.isInDeleteZone ? notifier.onZoneConfirmed : null,
                  ),
                ),
              ),

            // 底部提示
            if (state.hasNextWord && state.markZoneOpacity < 0.1 && state.deleteZoneOpacity < 0.1)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 0.5,
                    child: Text(
                      '上: 详情 | 左: 稍后 | 右: 操作',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
                ),
              ),

            // 区域确认提示
            if (state.isInMarkZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _ConfirmHint(label: '松开标记新词', color: Colors.blue)),
              ),

            if (state.isInDeleteZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _ConfirmHint(label: '松开删除', color: Colors.red)),
              ),

            // 成功提示
            if (state.showMarkSuccessHint)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已标记稍后复习', icon: Icons.check_circle)),
              ),

            if (state.showMarkNewSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已标记为新词', icon: Icons.bookmark_add)),
              ),

            if (state.showDeleteSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(child: _SuccessHint(label: '已删除单词', icon: Icons.delete)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack(WordDragNotifier notifier, WordDragState state) {
    return DraggableWordCard(
      controller: _cardController,
      onOffsetChanged: _handleOffsetChanged,
      onDragEnd: _handleDragEnd,
      child: WordCardContent(
        word: state.currentWord!,
        isDragging: state.isDragging,
      ),
    );
  }

  Widget _buildProgressIndicator(WordDragState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${state.words.length} 个单词',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              Text(
                '已复习 ${Word.sampleWords.length - state.words.length}',
                style: TextStyle(color: Colors.green.shade400, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.words.isEmpty
                ? 1.0
                : (Word.sampleWords.length - state.words.length) / Word.sampleWords.length,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation(Colors.green.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WordDragNotifier notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 80, color: Colors.green.shade400),
        const SizedBox(height: 24),
        const Text(
          '太棒了！',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          '已完成全部 ${Word.sampleWords.length} 个单词',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: notifier.resetWords,
          child: const Text('再学一遍'),
        ),
      ],
    );
  }
}

/// 操作区域组件
class _ActionZone extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDelete;
  final VoidCallback? onTap;

  const _ActionZone({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isDelete = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDelete ? Colors.red : Colors.blue;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 80,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [color.shade500, color.shade700]
                : [Colors.grey.shade800, Colors.grey.shade900],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color.shade300.withValues(alpha: 0.8) : Colors.grey.shade700,
            width: 2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 2)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isActive ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(icon, color: isActive ? Colors.white : Colors.grey, size: 36),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 确认提示组件
class _ConfirmHint extends StatelessWidget {
  final String label;
  final Color color;

  const _ConfirmHint({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '松开$label',
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 成功提示组件
class _SuccessHint extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SuccessHint({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
