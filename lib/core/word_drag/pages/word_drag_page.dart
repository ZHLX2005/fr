import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/word_drag_state.dart';
import '../widgets/word_card_content.dart';
import 'word_detail_page.dart';

/// 单词拖拽背词页面
/// 使用 CardSwiper 实现卡片滑动，顶部抽屉显示单词列表
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
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<_WordListDrawerState> _drawerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = context.read<WordDragNotifier>();
      notifier.setNavigateCallback(_navigateToDetail);
    });
  }

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
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

  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final notifier = context.read<WordDragNotifier>();

    switch (direction) {
      case CardSwiperDirection.top:
        notifier.onSwipeUp();
        break;
      case CardSwiperDirection.left:
        notifier.onSwipeLeft();
        break;
      case CardSwiperDirection.right:
        notifier.onSwipeRight();
        break;
      default:
        notifier.onSpringBack();
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1e),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部抽屉区域
            _WordListDrawer(
              key: _drawerKey,
              words: state.words,
              currentIndex: state.currentIndex,
              onWordTap: (index) {
                // 跳转到指定单词
              },
            ),

            // 顶部进度
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildProgressIndicator(state),
            ),

            // 中心卡片区域
            Expanded(
              child: Center(
                child: state.hasNextWord
                    ? _buildCardSwiper(notifier, state)
                    : _buildEmptyState(notifier),
              ),
            ),

            // 底部提示
            if (state.hasNextWord)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
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
          ],
        ),
      ),
    );
  }

  Widget _buildCardSwiper(WordDragNotifier notifier, WordDragState state) {
    final cards = state.words.map((word) {
      return WordCardContent(
        word: word,
        isDragging: false,
      );
    }).toList();

    return SizedBox(
      width: 340,
      height: 450,
      child: CardSwiper(
        controller: _cardController,
        cardsCount: cards.length,
        onSwipe: _onSwipe,
        numberOfCardsDisplayed: 2,
        backCardOffset: const Offset(0, 40),
        padding: EdgeInsets.zero,
        isDisabled: false,
        allowedSwipeDirection: const AllowedSwipeDirection.only(
          left: true,
          right: true,
          up: true,
        ),
        cardBuilder: (
          context,
          index,
          horizontalThresholdPercentage,
          verticalThresholdPercentage,
        ) =>
            cards[index],
      ),
    );
  }

  Widget _buildProgressIndicator(WordDragState state) {
    final progress = state.words.isEmpty
        ? 1.0
        : (Word.sampleWords.length - state.words.length) / Word.sampleWords.length;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school, color: Colors.deepPurple.shade300, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${state.words.length} 个单词',
                    style: TextStyle(color: Colors.deepPurple.shade200, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green.shade300, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '已复习 ${Word.sampleWords.length - state.words.length}',
                    style: TextStyle(color: Colors.green.shade200, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: Colors.grey.shade800,
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade400,
                    Colors.purple.shade400,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(WordDragNotifier notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.green.withValues(alpha: 0.3),
                Colors.green.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Icon(Icons.celebration, size: 60, color: Colors.green.shade400),
        ),
        const SizedBox(height: 32),
        const Text(
          '太棒了！',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '已完成全部 ${Word.sampleWords.length} 个单词',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 40),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.shade600,
                Colors.purple.shade600,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: notifier.resetWords,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      '再学一遍',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部抽屉单词列表组件
class _WordListDrawer extends StatefulWidget {
  final List<Word> words;
  final int currentIndex;
  final Function(int) onWordTap;

  const _WordListDrawer({
    super.key,
    required this.words,
    required this.currentIndex,
    required this.onWordTap,
  });

  @override
  State<_WordListDrawer> createState() => _WordListDrawerState();
}

class _WordListDrawerState extends State<_WordListDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightAnimation;
  bool _isExpanded = false;
  static const double _collapsedHeight = 60.0;
  static const double _expandedHeight = 200.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _heightAnimation = Tween<double>(
      begin: _collapsedHeight,
      end: _expandedHeight,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleDrawer() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _heightAnimation,
      builder: (context, child) {
        return Container(
          height: _heightAnimation.value,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.deepPurple.withValues(alpha: 0.2),
                Colors.purple.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(
              color: Colors.deepPurple.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 抽屉手柄和标题
              GestureDetector(
                onTap: _toggleDrawer,
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurple.shade400,
                              Colors.purple.shade400,
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.list_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '单词列表',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${widget.words.length} 个单词待学习',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 单词列表
              if (_isExpanded)
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: widget.words.length,
                    itemBuilder: (context, index) {
                      final word = widget.words[index];
                      final isCurrentWord = index == widget.currentIndex;

                      return GestureDetector(
                        onTap: () => widget.onWordTap(index),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isCurrentWord
                                ? Colors.deepPurple.withValues(alpha: 0.3)
                                : Colors.transparent,
                            border: isCurrentWord
                                ? Border.all(
                                    color: Colors.deepPurple.withValues(alpha: 0.5),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCurrentWord
                                      ? Colors.deepPurple
                                      : Colors.grey.shade700,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  word.text,
                                  style: TextStyle(
                                    color: isCurrentWord
                                        ? Colors.white
                                        : Colors.grey.shade300,
                                    fontSize: 13,
                                    fontWeight: isCurrentWord
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isCurrentWord)
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.deepPurple.shade300,
                                  size: 12,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

