import 'package:flutter/material.dart';
import '../models/word.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/delete_zone.dart';
import '../widgets/word_card_content.dart';

/// 单词拖拽背词页面
///
/// 交互说明：
/// - 上滑中心卡片 → 进入详细阅读模式
/// - 右滑卡片 → 显示右侧删除区，拖入区域释放才删除
/// - 左滑卡片 → 稍后重学
class WordDragPage extends StatefulWidget {
  const WordDragPage({super.key});

  @override
  State<WordDragPage> createState() => _WordDragPageState();
}

class _WordDragPageState extends State<WordDragPage>
    with SingleTickerProviderStateMixin {
  List<Word> _words = List.from(Word.sampleWords);
  int _currentIndex = 0;

  bool _showDetails = false;
  bool _isInDeleteZone = false;
  double _dragProgress = 0.0;
  double _deleteZoneOpacity = 0.0; // 删除区透明度，随距离变化

  // 删除区位置
  final GlobalKey _deleteZoneKey = GlobalKey();
  Rect _deleteZoneRect = Rect.zero;

  // 详情展示动画
  late AnimationController _detailsController;

  // 卡片状态引用
  DraggableCardState? _cardState;

  @override
  void initState() {
    super.initState();
    _detailsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateDeleteZoneRect();
    });
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _updateDeleteZoneRect() {
    final RenderBox? box =
        _deleteZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      setState(() {
        _deleteZoneRect = box.localToGlobal(Offset.zero) & box.size;
      });
    }
  }

  void _onHorizontalDragProgress(double progress) {
    setState(() {
      _dragProgress = progress;
    });
  }

  void _onCardPositionChanged(Offset cardCenter) {
    if (_deleteZoneRect == Rect.zero) return;

    // 计算卡片中心到删除区的距离
    final zoneCenter = _deleteZoneRect.center;
    final distance = (cardCenter - zoneCenter).distance;

    // 最大检测距离（屏幕宽度）
    final maxDistance = MediaQuery.of(context).size.width * 0.6;

    // 根据距离计算透明度（距离越近，透明度越高）
    // 超过 maxDistance 时 opacity 为 0，进入删除区时 opacity 为 1
    double opacity = 1.0 - (distance / maxDistance).clamp(0.0, 1.0);

    // 检测是否进入删除区
    final expandedRect = _deleteZoneRect.inflate(30);
    final isInZone = expandedRect.contains(cardCenter);

    if (isInZone != _isInDeleteZone || (opacity - _deleteZoneOpacity).abs() > 0.05) {
      setState(() {
        _isInDeleteZone = isInZone;
        _deleteZoneOpacity = opacity.clamp(0.0, 1.0);
      });
    }
  }

  void _onSwipeUp() {
    setState(() {
      _showDetails = true;
    });
    _detailsController.forward();
  }

  void _onSwipeRight() {
    // 右滑 - 这里实际上不会自动删除
    // 删除需要拖入删除区
  }

  void _onSwipeLeft() {
    _markAsReviewed();
  }

  void _deleteCurrentWord() {
    if (_words.isEmpty) return;

    setState(() {
      _words.removeAt(_currentIndex);
      if (_currentIndex >= _words.length && _currentIndex > 0) {
        _currentIndex--;
      }
      _resetState();
    });
  }

  void _markAsReviewed() {
    if (_words.isEmpty) return;

    setState(() {
      // 将单词移到最后
      final word = _words.removeAt(_currentIndex);
      _words.add(word);
      _resetState();
    });
  }

  void _resetState() {
    setState(() {
      _showDetails = false;
      _isInDeleteZone = false;
      _dragProgress = 0.0;
      _deleteZoneOpacity = 0.0;
    });
    _detailsController.reset();
    _cardState?.reset();
  }

  void _confirmDelete() {
    if (_isInDeleteZone) {
      _cardState?.completeSwipeRight();
      Future.delayed(const Duration(milliseconds: 350), () {
        _deleteCurrentWord();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              child: _buildProgressIndicator(),
            ),

            // 中心卡片
            Center(
              child: _words.isEmpty
                  ? _buildEmptyState()
                  : _buildCardStack(),
            ),

            // 右侧删除区 - 随卡片靠近逐渐显现
            if (_words.isNotEmpty && _deleteZoneOpacity > 0.01)
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: DeleteZone(
                    key: _deleteZoneKey,
                    isActive: _isInDeleteZone,
                    opacity: _deleteZoneOpacity,
                    progress: _dragProgress,
                    onDeleteTriggered: _confirmDelete,
                  ),
                ),
              ),

            // 底部提示 - 删除区显现时隐藏
            if (_words.isNotEmpty && _deleteZoneOpacity < 0.1)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Opacity(
                    opacity: 0.5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: Colors.grey.shade400,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '左滑: 稍后重学',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Text(
                          '右滑: 删除',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          color: Colors.grey.shade400,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 删除确认提示
            if (_isInDeleteZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '松开手指删除',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_words.length} 个单词',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              Text(
                '已复习 ${Word.sampleWords.length - _words.length}',
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _words.isEmpty
                ? 1.0
                : (Word.sampleWords.length - _words.length) /
                    Word.sampleWords.length,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation(Colors.green.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildCardStack() {
    return DeleteZoneDetector(
      zoneRect: _deleteZoneRect,
      onZoneStatusChanged: (isInZone) {
        setState(() {
          _isInDeleteZone = isInZone;
        });
      },
      onDeleteTriggered: _confirmDelete,
      child: DraggableWordCard(
        onSwipeUp: _onSwipeUp,
        onSwipeRight: _onSwipeRight,
        onSwipeLeft: _onSwipeLeft,
        onHorizontalDragProgress: _onHorizontalDragProgress,
        onCardPositionChanged: _onCardPositionChanged,
        onCardStateChanged: (state) {
          _cardState = state;
        },
        child: WordCardContent(
          word: _words[_currentIndex],
          showDetails: _showDetails,
          isDragging: _dragProgress > 0,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 80,
          color: Colors.green.shade400,
        ),
        const SizedBox(height: 24),
        const Text(
          '太棒了！',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已完成全部 ${Word.sampleWords.length} 个单词',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () {
            setState(() {
              _words = List.from(Word.sampleWords);
              _currentIndex = 0;
            });
          },
          child: const Text('再学一遍'),
        ),
      ],
    );
  }
}
