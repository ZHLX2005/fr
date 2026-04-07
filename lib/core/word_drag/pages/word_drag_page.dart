import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/word_drag_state.dart';
import '../widgets/category_drop_row.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/word_card_content.dart';
import 'word_detail_page.dart';

/// 单词拖拽背词页面
///
/// 基于 photoo 实现，支持：
/// - 上滑跳过/查看详情
/// - 左滑稍后复习
/// - 右滑喜欢/掌握
/// - 下滑 > 300px 显示分类桶
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

/// 分类桶配置
const _categoryBuckets = [
  CategoryBucket(
    id: 'noun',
    name: '名词',
    icon: Icons.category,
    color: Color(0xFF3B82F6),
  ),
  CategoryBucket(
    id: 'verb',
    name: '动词',
    icon: Icons.play_arrow,
    color: Color(0xFF10B981),
  ),
  CategoryBucket(
    id: 'adj',
    name: '形容词',
    icon: Icons.color_lens,
    color: Color(0xFFF59E0B),
  ),
  CategoryBucket(
    id: 'adv',
    name: '副词',
    icon: Icons.speed,
    color: Color(0xFF8B5CF6),
  ),
  CategoryBucket(
    id: 'other',
    name: '其他',
    icon: Icons.more_horiz,
    color: Color(0xFF6B7280),
  ),
];

class _WordDragPageContent extends StatefulWidget {
  const _WordDragPageContent();

  @override
  State<_WordDragPageContent> createState() => _WordDragPageContentState();
}

class _WordDragPageContentState extends State<_WordDragPageContent> {
  final GlobalKey<_WordListDrawerState> _drawerKey = GlobalKey();
  final GlobalKey<CategoryDropRowState> _dropRowKey = GlobalKey();

  // 是否正在拖动
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

  void _onDragStart() {
    setState(() {
      _isDragging = true;
    });
    context.read<WordDragNotifier>().onDragStart();
  }

  void _onDragUpdate(double x, double y) {
    // 不需要 setState，动画由 DraggableWordCard 内部处理
    final screenSize = MediaQuery.of(context).size;
    context.read<WordDragNotifier>().onDragUpdate(
      Offset(x, y),
      screenSize,
    );

    // 如果是 folder mode，更新碰撞检测
    final notifier = context.read<WordDragNotifier>();
    if (notifier.state.isFolderMode) {
      final cardCenter = Offset(
        screenSize.width / 2 + x,
        screenSize.height * 0.4 + y,
      );
      _dropRowKey.currentState?.updateCardPosition(cardCenter);
    }
  }

  bool _onDragEnd(double x, double y) {
    final notifier = context.read<WordDragNotifier>();

    // 检查是否是下滑桶模式
    final isFolderMode = y > 300;

    if (isFolderMode) {
      notifier.enterFolderMode();
      setState(() {
        _isDragging = false;
      });
      return true; // 消耗事件，不回弹
    }

    setState(() {
      _isDragging = false;
    });
    return false;
  }

  void _onDragCancel() {
    setState(() {
      _isDragging = false;
    });
    context.read<WordDragNotifier>().onSpringBack();
  }

  void _onSwipeLeft() {
    context.read<WordDragNotifier>().onSwipeLeft();
  }

  void _onSwipeRight() {
    context.read<WordDragNotifier>().onSwipeRight();
  }

  void _onSwipeUp() {
    context.read<WordDragNotifier>().onSwipeUp();
  }

  void _onBucketSelected(String bucketId) {
    context.read<WordDragNotifier>().selectBucket(bucketId);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1e),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
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
                        ? _buildCardStack(notifier, state)
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
                          '上: 详情 | 左: 稍后 | 右: 操作 | 下: 分类',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 分类桶选择行 (覆盖在卡片下方)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CategoryDropRow(
                key: _dropRowKey,
                visible: state.isFolderMode,
                buckets: _categoryBuckets,
                activeBucketId: state.activeCategoryBucketId,
                onBucketSelected: _onBucketSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack(WordDragNotifier notifier, WordDragState state) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.85;
    final cardHeight = screenSize.height * 0.55;

    // 计算要显示的卡片数量 (最多3张)
    final displayCount = (state.words.length - state.currentIndex).clamp(0, 3);
    final cards = <Widget>[];

    for (int i = displayCount - 1; i >= 0; i--) {
      final wordIndex = state.currentIndex + i;
      if (wordIndex >= state.words.length) continue;

      final word = state.words[wordIndex];
      final isTopCard = i == 0;

      cards.add(
        Positioned(
          child: DraggableWordCard(
            index: wordIndex,
            isTopCard: isTopCard,
            stackIndex: i,
            onSwipeLeft: isTopCard && !_isDragging ? _onSwipeLeft : null,
            onSwipeRight: isTopCard && !_isDragging ? _onSwipeRight : null,
            onSwipeUp: isTopCard && !_isDragging ? _onSwipeUp : null,
            onDragStart: isTopCard ? _onDragStart : null,
            onDragUpdate: isTopCard ? _onDragUpdate : null,
            onDragEnd: isTopCard ? _onDragEnd : null,
            onDragCancel: isTopCard ? _onDragCancel : null,
            child: WordCardContent(
              word: word,
              isDragging: isTopCard && _isDragging,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: cards,
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
