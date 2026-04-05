import 'package:flutter/material.dart';
import '../models/word.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/delete_zone.dart';
import '../widgets/word_card_content.dart';

/// 单词拖拽背词页面
///
/// 交互说明：
/// - 上滑中心卡片 → 进入详细阅读模式
/// - 右滑卡片 → 拖动到删除区，释放删除
/// - 左滑卡片 → 稍后重学
class WordDragPage extends StatefulWidget {
  const WordDragPage({super.key});

  @override
  State<WordDragPage> createState() => _WordDragPageState();
}

class _WordDragPageState extends State<WordDragPage> {
  List<Word> _words = List.from(Word.sampleWords);
  int _currentIndex = 0;

  bool _showDetails = false;
  bool _isInDeleteZone = false;

  final GlobalKey _deleteZoneKey = GlobalKey();
  Rect _deleteZoneRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateDeleteZoneRect();
    });
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

  void _onDragUpdate(DragUpdateDetails details, Offset cardCenter) {
    if (_deleteZoneRect != Rect.zero) {
      setState(() {
        _isInDeleteZone = _deleteZoneRect.contains(cardCenter);
      });
    }
  }

  void _deleteCurrentWord() {
    if (_words.isEmpty) return;

    setState(() {
      _words.removeAt(_currentIndex);
      if (_currentIndex >= _words.length && _currentIndex > 0) {
        _currentIndex--;
      }
      _showDetails = false;
      _isInDeleteZone = false;
    });
  }

  void _markAsMastered() {
    if (_words.isEmpty) return;

    setState(() {
      _words[_currentIndex].mastered = true;
      _words.removeAt(_currentIndex);
      if (_currentIndex >= _words.length && _currentIndex > 0) {
        _currentIndex--;
      }
      _showDetails = false;
    });
  }

  void _onSwipeUp() {
    setState(() {
      _showDetails = true;
    });
    // 显示详情后自动返回
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _showDetails) {
        setState(() {
          _showDetails = false;
        });
      }
    });
  }

  void _onSwipeRight() {
    // 右滑删除
    _deleteCurrentWord();
  }

  void _onSwipeLeft() {
    // 左滑标记为稍后重学
    _markAsMastered();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('背单词'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _words = List.from(Word.sampleWords);
                _currentIndex = 0;
              });
            },
            child: const Text('重置'),
          ),
        ],
      ),
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

            // 中心卡片区域
            Center(
              child: _words.isEmpty
                  ? _buildEmptyState()
                  : _buildCardStack(),
            ),

            // 底部删除区
            if (_words.isNotEmpty)
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: DeleteZone(
                    key: _deleteZoneKey,
                    isActive: _isInDeleteZone,
                    onDeleteConfirmed: _deleteCurrentWord,
                  ),
                ),
              ),

            // 删除区提示
            if (_words.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.arrow_back,
                        color: Colors.grey.withOpacity(0.5),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '左滑: 稍后重学',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        '右滑: 删除',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        color: Colors.grey.withOpacity(0.5),
                        size: 14,
                      ),
                    ],
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
                '已掌握 ${Word.sampleWords.length - _words.length}',
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
    return DraggableWordCard(
      onSwipeUp: _onSwipeUp,
      onSwipeRight: _onSwipeRight,
      onSwipeLeft: _onSwipeLeft,
      onDragUpdate: (details) {
        // 计算卡片中心位置
        final screenCenter = MediaQuery.of(context).size.center(Offset.zero);
        _onDragUpdate(details, screenCenter);
      },
      onCardStateChanged: (state) {
        setState(() {});
      },
      child: WordCardContent(
        word: _words[_currentIndex],
        showDetails: _showDetails,
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
      ],
    );
  }
}
