import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/word_drag_state.dart';
import '../widgets/category_drop_row.dart';
import '../widgets/word_card_content.dart';
import '../widgets/draggable_word_card.dart';

/// 单词拖拽背词页面
///
/// 基于 photoo NativeVoiceLikeActivity.kt 实现
/// 支持：上滑跳过、左滑稍后复习、右滑掌握、下滑 > 420px 显示分类桶
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
  final GlobalKey<CategoryDropRowState> _dropRowKey = GlobalKey();

  // Folder mode 状态
  bool _isFolderMode = false;
  String? _activeBucketId;
  final CategoryDropEdgeScrollState _edgeScrollState = CategoryDropEdgeScrollState();

  // 当前查看的单词详情
  Word? _viewingWord;

  // 阈值常量 (匹配 DraggableWordCard)
  static const double _folderDropRowThreshold = 300; // 显示桶选择器

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1e),
      body: SafeArea(
        child: Stack(
          children: [
            // 主内容
            Column(
              children: [
                // 顶部抽屉
                _WordListDrawer(
                  words: state.words,
                  currentIndex: state.currentIndex,
                  onWordTap: (index) {},
                ),

                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildProgressIndicator(state),
                ),

                // 卡片区域
                Expanded(
                  child: Center(
                    child: state.hasNextWord
                        ? _buildCard(notifier, state)
                        : _buildEmptyState(notifier),
                  ),
                ),

                // 底部提示
                if (state.hasNextWord)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      '上: 详情 | 左: 稍后 | 右: 操作 | 下: 分类',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
              ],
            ),

            // 分类桶 (photoo: padding bottom = 24dp)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: CategoryDropRow(
                key: _dropRowKey,
                visible: _isFolderMode,
                buckets: _categoryBuckets,
                activeBucketId: _activeBucketId,
                edgeScrollState: _edgeScrollState,
                onActiveBucketChanged: (id) {
                  setState(() {
                    _activeBucketId = id;
                  });
                },
                onBucketSelected: (bucketId) {
                  notifier.selectBucket(bucketId);
                  _exitFolderMode();
                },
              ),
            ),

            // 详情页
            if (_viewingWord != null)
              _buildDetailOverlay(_viewingWord!),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(WordDragNotifier notifier, WordDragState state) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.8;
    final cardHeight = screenSize.height * 0.6;

    // Kotlin 使用 BiasAlignment(0f, -0.12f) 将卡片上移 12% 屏幕高度
    // 这使得卡片顶部位置从 0.2 * screenHeight 变为 0.08 * screenHeight
    // Dart 使用 Alignment.center，需要手动应用这个偏移
    // 卡片中心位置 = 0.2 * screenHeight - 0.12 * screenHeight + cardHeight/2 = 0.08 * screenHeight + cardHeight/2
    Offset getCardCenter(double offsetX, double offsetY) {
      final cardCenterY = screenSize.height * 0.08 + cardHeight / 2;
      return Offset(
        screenSize.width / 2 + offsetX,
        cardCenterY + offsetY,
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // 底层卡片 (模拟堆叠效果)
        if (state.currentIndex + 1 < state.words.length)
          _buildBackgroundCard(cardWidth, cardHeight, 1),
        if (state.currentIndex + 2 < state.words.length)
          _buildBackgroundCard(cardWidth, cardHeight, 2),

        // 顶层卡片 (使用 ValueKey 确保 currentIndex 改变时重建)
        DraggableWordCard(
          key: ValueKey('top_card_${state.currentIndex}'),
          isTopCard: true,
          stackIndex: 0,
          index: state.currentIndex,
          onSwipeLeft: () {
            notifier.onSwipeLeft();
          },
          onSwipeRight: () {
            notifier.onSwipeRight();
          },
          onSwipeUp: () {
            // 上滑跳过 - 先捕获当前单词显示详情，再跳到下一个
            final wordToShow = notifier.state.currentWord;
            notifier.onSwipeUp();
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && wordToShow != null) {
                _showDetail(wordToShow);
              }
            });
          },
          onFolderModeDragEnd: (x, y) {
            // 检查是否在桶上
            final cardCenter = getCardCenter(x, y);
            _updateBucketCollision(cardCenter, x);
            return _activeBucketId != null;
          },
          onDragUpdate: (x, y) {
            // 检测是否显示桶选择器 (300px)
            if (y > _folderDropRowThreshold) {
              if (!_isFolderMode) {
                setState(() {
                  _isFolderMode = true;
                });
                // 延迟碰撞检测到下一帧，确保 CategoryDropRow 已构建
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updateBucketCollision(getCardCenter(x, y), x);
                });
              } else {
                _updateBucketCollision(getCardCenter(x, y), x);
              }
              // 更新边缘滚动状态
              _edgeScrollState.cardCenterX = getCardCenter(x, y).dx;
              _edgeScrollState.screenWidth = screenSize.width;
              _edgeScrollState.visible = true;
            } else if (_isFolderMode) {
              _exitFolderMode();
              _edgeScrollState.visible = false;
            }
          },
          onDetail: () {
            _showDetail(state.currentWord!);
          },
          child: WordCardContent(
            word: state.words[state.currentIndex],
            showDetails: false,
            isDragging: false,
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundCard(double width, double height, int stackIndex) {
    // 匹配 DraggableWordCard 的堆叠公式
    final scale = 1.0 - (stackIndex * 0.04);
    final yOffset = stackIndex * 15.0;
    // Kotlin 中背景卡片只显示缩放的阴影，不显示实际内容
    // 这里用带阴影的半透明容器模拟堆叠效果
    return Transform.translate(
      offset: Offset(0, yOffset),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8 * stackIndex.toDouble(),
                offset: Offset(0, 2 * stackIndex.toDouble()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateBucketCollision(Offset cardCenter, double offsetX) {
    // 先强制更新桶位置，确保碰撞检测有最新数据
    _dropRowKey.currentState?.forceUpdateRects();
    _dropRowKey.currentState?.updateCardPosition(cardCenter, offsetX);
  }

  void _exitFolderMode() {
    setState(() {
      _isFolderMode = false;
      _activeBucketId = null;
    });
    // 同时清除 CategoryDropRow 中的活跃桶状态
    _dropRowKey.currentState?.clearActiveBucket();
  }

  void _showDetail(Word word) {
    setState(() {
      _viewingWord = word;
    });
  }

  void _hideDetail() {
    setState(() {
      _viewingWord = null;
    });
    context.read<WordDragNotifier>().onDetailPageComplete();
  }

  Widget _buildDetailOverlay(Word word) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _hideDetail,
        child: Container(
          color: Colors.black.withValues(alpha: 0.9),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    word.text,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    word.phonetic,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      word.definition,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF2D2D44),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.format_quote, color: Colors.blue.shade400, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '例句',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          word.example,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.blue.shade900,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '点击任意处关闭',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                  colors: [Colors.deepPurple.shade400, Colors.purple.shade400],
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
              colors: [Colors.deepPurple.shade600, Colors.purple.shade600],
            ),
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
            ),
          ),
          child: Column(
            children: [
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
                        child: const Icon(Icons.list_alt, color: Colors.white, size: 20),
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
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isCurrentWord
                                ? Colors.deepPurple.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCurrentWord ? Colors.deepPurple : Colors.grey.shade700,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
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
                                    color: isCurrentWord ? Colors.white : Colors.grey.shade300,
                                    fontSize: 13,
                                    fontWeight: isCurrentWord ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
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
