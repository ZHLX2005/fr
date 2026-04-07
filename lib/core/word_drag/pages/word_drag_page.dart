import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import '../models/word.dart';
import '../providers/word_drag_notifier.dart';
import '../providers/word_drag_state.dart';
import '../widgets/category_drop_row.dart';
import '../widgets/word_card_content.dart';

/// 单词拖拽背词页面
///
/// 基于 photoo 实现，支持：
/// - 上滑跳过/查看详情
/// - 左滑稍后复习
/// - 右滑喜欢/掌握
/// - 下滑 > 420px 显示分类桶
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

class _WordDragPageContentState extends State<_WordDragPageContent>
    with TickerProviderStateMixin {
  final GlobalKey<_WordListDrawerState> _drawerKey = GlobalKey();
  final GlobalKey<CategoryDropRowState> _dropRowKey = GlobalKey();

  // 详情页overlay
  Word? _viewingWord;
  OverlayEntry? _detailOverlay;

  // 卡片动画控制器
  late AnimationController _cardControllerX;
  late AnimationController _cardControllerY;
  late AnimationController _cardAlphaController;
  late AnimationController _cardScaleController;

  // 动画值
  double _cardOffsetX = 0;
  double _cardOffsetY = 0;
  double _cardScale = 1;

  // 状态
  bool _isDragging = false;
  bool _isAnimating = false;
  bool _isLeaving = false;

  // Folder mode
  bool _isFolderMode = false;
  String? _activeBucketId;

  // 阈值常量 (基于 photoo)
  static const double _threshold = 160;
  static const double _folderModeThreshold = 420;
  static const double _flingThreshold = 800;

  @override
  void initState() {
    super.initState();
    _cardControllerX = AnimationController.unbounded(vsync: this);
    _cardControllerY = AnimationController.unbounded(vsync: this);
    _cardAlphaController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _cardScaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));

    _cardControllerX.addListener(_onCardAnimation);
    _cardControllerY.addListener(_onCardAnimation);
    _cardAlphaController.addListener(_onCardAnimation);
    _cardScaleController.addListener(_onCardAnimation);
  }

  @override
  void dispose() {
    _cardControllerX.dispose();
    _cardControllerY.dispose();
    _cardAlphaController.dispose();
    _cardScaleController.dispose();
    _detailOverlay?.remove();
    super.dispose();
  }

  void _onCardAnimation() {
    setState(() {
      _cardOffsetX = _cardControllerX.value;
      _cardOffsetY = _cardControllerY.value;
      _cardScale = _cardScaleController.value;
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (_isAnimating || _isLeaving) return;
    setState(() {
      _isDragging = true;
    });
  }

  void _onDragUpdate(double dx, double dy) {
    if (_isAnimating || _isLeaving) return;

    _cardControllerX.value += dx;
    _cardControllerY.value += dy;

    // Folder mode 检测 (基于 photoo: 420px)
    final newFolderMode = _cardControllerY.value > _folderModeThreshold;

    if (newFolderMode != _isFolderMode) {
      setState(() {
        _isFolderMode = newFolderMode;
        if (!newFolderMode) {
          _activeBucketId = null;
        }
      });
    }

    // 更新桶碰撞检测
    if (_isFolderMode) {
      final screenSize = MediaQuery.of(context).size;
      final cardCenter = Offset(
        screenSize.width / 2 + _cardControllerX.value,
        screenSize.height * 0.4 + _cardControllerY.value,
      );
      _dropRowKey.currentState?.updateCardPosition(cardCenter);
    }
  }

  void _onDragEnd(double velocityX, double velocityY) {
    if (_isAnimating || _isLeaving) return;

    final offsetX = _cardControllerX.value;
    final offsetY = _cardControllerY.value;

    // Folder mode 处理
    if (_isFolderMode) {
      if (_activeBucketId != null) {
        // 成功放入桶
        _animateSuckIntoBucket();
        return;
      } else {
        // 没有选择桶，回弹
        _animateSpringBack();
        return;
      }
    }

    // 检查滑动方向
    if (offsetX < -_threshold) {
      // 左滑 - 删除
      _animateSwipeOut(-1500, 0);
      context.read<WordDragNotifier>().onSwipeLeft();
    } else if (offsetX > _threshold) {
      // 右滑 - 掌握
      _animateSwipeOut(1500, 0);
      context.read<WordDragNotifier>().onSwipeRight();
    } else if (offsetY < -_threshold || velocityY < -_flingThreshold) {
      // 上滑 - 查看详情
      _animateSwipeOut(0, -2000);
      _showDetail();
    } else {
      // 回弹
      _animateSpringBack();
    }
  }

  void _animateSwipeOut(double targetX, double targetY) {
    _isAnimating = true;
    _cardControllerX.animateTo(targetX, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    _cardControllerY.animateTo(targetY, duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
        .then((_) {
      _isAnimating = false;
      _isLeaving = true;
    });
  }

  void _animateSuckIntoBucket() {
    _isAnimating = true;
    _cardAlphaController.animateTo(0);
    _cardScaleController.animateTo(0.1);
    _cardControllerY.animateTo(_cardControllerY.value + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
        .then((_) {
      _isAnimating = false;
      _isLeaving = true;
      _activeBucketId = null;
      _isFolderMode = false;
      context.read<WordDragNotifier>().selectBucket(_activeBucketId ?? 'other');
    });
  }

  void _animateSpringBack() {
    _isAnimating = true;

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 2000.0,
      damping: 76.0,
    );

    final simX = SpringSimulation(spring, _cardControllerX.value, 0, 0);
    final simY = SpringSimulation(spring, _cardControllerY.value, 0, 0);

    _cardControllerX.animateWith(simX);
    _cardControllerY.animateWith(simY);

    void onComplete(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _isAnimating = false;
        _cardControllerX.removeStatusListener(onComplete);
        _cardControllerY.removeStatusListener(onComplete);
      }
    }
    _cardControllerX.addStatusListener(onComplete);
    _cardControllerY.addStatusListener(onComplete);
  }

  void _showDetail() {
    final notifier = context.read<WordDragNotifier>();
    final word = notifier.state.currentWord;
    if (word == null) return;

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

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<WordDragNotifier>();
    final state = notifier.state;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1e),
      body: Stack(
        children: [
          // 主内容
          SafeArea(
            child: Column(
              children: [
                // 顶部抽屉
                _WordListDrawer(
                  key: _drawerKey,
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
                    child: state.hasNextWord && !_isLeaving
                        ? _buildCard(notifier, state)
                        : _buildEmptyState(notifier),
                  ),
                ),

                // 底部提示
                if (state.hasNextWord && !_isLeaving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      '上: 详情 | 左: 稍后 | 右: 操作 | 下: 分类',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ),
              ],
            ),
          ),

          // 分类桶
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CategoryDropRow(
              key: _dropRowKey,
              visible: _isFolderMode,
              buckets: _categoryBuckets,
              activeBucketId: _activeBucketId,
              onActiveBucketChanged: (id) {
                setState(() {
                  _activeBucketId = id;
                });
              },
              onBucketSelected: (bucketId) {
                _activeBucketId = bucketId;
                _animateSuckIntoBucket();
              },
            ),
          ),

          // 详情页Overlay
          if (_viewingWord != null)
            _buildDetailOverlay(_viewingWord!),
        ],
      ),
    );
  }

  Widget _buildCard(WordDragNotifier notifier, WordDragState state) {
    final screenSize = MediaQuery.of(context).size;
    final cardWidth = screenSize.width * 0.8;
    final cardHeight = screenSize.height * 0.5;

    // 计算动态缩放
    double dynamicScale = 1.0;
    if (_cardOffsetY < 0) {
      dynamicScale = (1.0 + _cardOffsetY / 1000).clamp(0.9, 1.0);
    } else if (_cardOffsetY > 0) {
      dynamicScale = (1.0 - _cardOffsetY / 1000).clamp(0.5, 1.0);
    }

    // 旋转角度
    final rotation = (_cardOffsetX / 60).clamp(-10.0, 10.0);

    // Action Indicator
    final actionIndicator = _getActionIndicator();

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: GestureDetector(
        onPanStart: _onDragStart,
        onPanUpdate: (details) => _onDragUpdate(details.delta.dx, details.delta.dy),
        onPanEnd: (details) => _onDragEnd(
          details.velocity.pixelsPerSecond.dx,
          details.velocity.pixelsPerSecond.dy,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 底层卡片 (模拟堆叠效果)
            if (state.currentIndex + 1 < state.words.length)
              Positioned(
                top: 20,
                child: Transform.scale(
                  scale: 0.96,
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                  ),
                ),
              ),
            if (state.currentIndex + 2 < state.words.length)
              Positioned(
                top: 40,
                child: Transform.scale(
                  scale: 0.92,
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),

            // 顶层卡片
            Transform.translate(
              offset: Offset(_cardOffsetX, _cardOffsetY),
              child: Transform.scale(
                scale: dynamicScale * _cardScale,
                child: Transform.rotate(
                  angle: rotation * 3.14159 / 180,
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: WordCardContent(
                        word: state.words[state.currentIndex],
                        showDetails: false,
                        isDragging: _isDragging,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Action Indicator
            if (actionIndicator != null)
              Positioned(
                top: 24,
                right: 24,
                child: _ActionIndicator(indicator: actionIndicator),
              ),
          ],
        ),
      ),
    );
  }

  String? _getActionIndicator() {
    if (_isFolderMode) return 'move';
    if (_cardOffsetX > 100) return 'like';
    if (_cardOffsetX < -100) return 'delete';
    if (_cardOffsetY < -100) return 'skip';
    return null;
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

/// Action Indicator 组件
class _ActionIndicator extends StatelessWidget {
  final String indicator;

  const _ActionIndicator({required this.indicator});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String text;

    switch (indicator) {
      case 'like':
        color = const Color(0xFFFF9800);
        icon = Icons.favorite;
        text = 'LIKE';
        break;
      case 'delete':
        color = const Color(0xFFEF4444);
        icon = Icons.delete_outline;
        text = 'DELETE';
        break;
      case 'skip':
        color = const Color(0xFF3B82F6);
        icon = Icons.arrow_upward;
        text = 'SKIP';
        break;
      case 'move':
        color = const Color(0xFF9C27B0);
        icon = Icons.drive_file_move;
        text = 'MOVE';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
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
