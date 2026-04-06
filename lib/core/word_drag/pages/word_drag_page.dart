import 'package:flutter/material.dart';
import '../models/word.dart';
import '../widgets/draggable_word_card.dart';
import '../widgets/word_card_content.dart';
import 'word_detail_page.dart';

/// 单词拖拽背词页面 - 单卡片交互
///
/// 交互说明：
/// - 上滑中心卡片 → 进入详细阅读模式
/// - 右滑 → 右侧显现"标新"区域（上方）和"删除"区域（下方）
/// - 必须拖入相应区域才能执行操作
class WordDragPage extends StatefulWidget {
  const WordDragPage({super.key});

  @override
  State<WordDragPage> createState() => _WordDragPageState();
}

class _WordDragPageState extends State<WordDragPage> {
  List<Word> _words = List.from(Word.sampleWords);
  int _currentIndex = 0;

  bool _showDetails = false;

  // 拖动状态
  double _dragProgress = 0.0; // 整体拖动进度
  double _verticalProgress = 0.0; // 垂直方向进度
  DragDirection _currentDirection = DragDirection.none;

  // 区域激活状态
  bool _isInMarkZone = false; // 标新区域
  bool _isInDeleteZone = false; // 删除区域

  // 操作区状态
  double _markZoneOpacity = 0.0;
  double _deleteZoneOpacity = 0.0;

  // 标记成功提示
  bool _showMarkSuccessHint = false;    // 左滑标记"稍后复习"
  bool _showMarkNewSuccessHint = false; // 标新成功
  bool _showDeleteSuccessHint = false;  // 删除成功

  @override
  void initState() {
    super.initState();
  }

  bool _onCardPositionChanged(Offset cardCenter, Offset dragOffset, bool isSpringBack) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // 弹簧动画期间使用捕获的状态，不更新区域状态
    if (isSpringBack) {
      // 弹簧动画期间：透明度设为0，但保持捕获的区域状态用于后续判断
      if (_markZoneOpacity != 0.0 || _deleteZoneOpacity != 0.0) {
        setState(() {
          _markZoneOpacity = 0.0;
          _deleteZoneOpacity = 0.0;
        });
      }
      return _isInMarkZone || _isInDeleteZone;
    }

    // 计算右侧两个区域的位置
    // 标新区：右侧上方
    // 删除区：右侧下方
    final markZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.15,
      80,
      screenHeight * 0.25,
    );
    final deleteZoneRect = Rect.fromLTWH(
      screenWidth - 100,
      screenHeight * 0.6,
      80,
      screenHeight * 0.25,
    );

    // 计算卡片中心位置
    final cardCenterInScreen = screenSize.center(Offset.zero) + dragOffset;

    // 检测是否进入标新区（右上）
    final markExpanded = markZoneRect.inflate(30);
    final inMark = markExpanded.contains(cardCenterInScreen);

    // 检测是否进入删除区（右下）
    final deleteExpanded = deleteZoneRect.inflate(30);
    final inDelete = deleteExpanded.contains(cardCenterInScreen);

    // 计算水平方向进度（用于显示右侧区域）
    final horizontalProgress = (dragOffset.dx / (screenWidth * 0.4)).clamp(0.0, 1.0);

    // 计算垂直方向进度
    final verticalProgress = (dragOffset.dy.abs() / (screenHeight * 0.2)).clamp(0.0, 1.0);

    // 根据方向计算各区域透明度
    double newMarkOpacity = 0.0;
    double newDeleteOpacity = 0.0;

    if (dragOffset.dx > 20) {
      // 右滑
      if (dragOffset.dy < -30) {
        // 右上 - 标新
        newMarkOpacity = horizontalProgress * (1 - verticalProgress * 0.5);
      } else if (dragOffset.dy > 30) {
        // 右下 - 删除
        newDeleteOpacity = horizontalProgress * (1 - verticalProgress * 0.5);
      } else {
        // 正右 - 两个都显示一点
        newMarkOpacity = horizontalProgress * 0.5;
        newDeleteOpacity = horizontalProgress * 0.5;
      }
    }

    if ((newMarkOpacity - _markZoneOpacity).abs() > 0.05 ||
        (newDeleteOpacity - _deleteZoneOpacity).abs() > 0.05 ||
        inMark != _isInMarkZone ||
        inDelete != _isInDeleteZone) {
      setState(() {
        _markZoneOpacity = newMarkOpacity.clamp(0.0, 1.0);
        _deleteZoneOpacity = newDeleteOpacity.clamp(0.0, 1.0);
        _isInMarkZone = inMark;
        _isInDeleteZone = inDelete;
      });
    }
    return inMark || inDelete;
  }

  void _onHorizontalDragProgress(double progress) {
    setState(() {
      _dragProgress = progress;
    });
  }

  void _navigateToDetail() {
    if (_words.isEmpty || _currentIndex >= _words.length) return;
    final word = _words[_currentIndex];

    // 进入详情页时就切换到下一个单词
    setState(() {
      _currentIndex = (_currentIndex + 1) % _words.length;
      _showDetails = false;
      _dragProgress = 0.0;
      _verticalProgress = 0.0;
      _currentDirection = DragDirection.none;
      _isInMarkZone = false;
      _isInDeleteZone = false;
      _markZoneOpacity = 0.0;
      _deleteZoneOpacity = 0.0;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WordDetailPage(
          word: word,
          onComplete: () {
            // 学完后重置状态（已经在 navigate 时切换了）
            setState(() {
              _showDetails = false;
              _dragProgress = 0.0;
              _verticalProgress = 0.0;
              _currentDirection = DragDirection.none;
              _isInMarkZone = false;
              _isInDeleteZone = false;
              _markZoneOpacity = 0.0;
              _deleteZoneOpacity = 0.0;
            });
          },
        ),
      ),
    );
  }

  void _onSwipeUp() {
    if (_words.isEmpty) return;
    // 上滑 → 跳转到详情页
    _navigateToDetail();
  }

  void _onSwipeLeft() {
    _markAsReviewed();
  }

  void _onMarkZone() {
    // 显示标新成功提示
    setState(() {
      _showMarkNewSuccessHint = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showMarkNewSuccessHint = false;
        });
      }
    });
    // 执行标记新词
    _markAsNew(true);
  }

  void _onDeleteZone() {
    // 显示删除成功提示
    setState(() {
      _showDeleteSuccessHint = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showDeleteSuccessHint = false;
        });
      }
    });
    // 执行删除
    _deleteCurrentWord(wasFromZone: true);
  }

  void _deleteCurrentWord({bool wasFromZone = false}) {
    if (_words.isEmpty) return;

    setState(() {
      _words.removeAt(_currentIndex);
      // 确保索引有效
      if (_words.isNotEmpty && _currentIndex >= _words.length) {
        _currentIndex = _words.length - 1;
      }
      _showDetails = false;
      _dragProgress = 0.0;
      _verticalProgress = 0.0;
      _currentDirection = DragDirection.none;
      _isInMarkZone = false;
      _isInDeleteZone = false;
      _markZoneOpacity = 0.0;
      _deleteZoneOpacity = 0.0;
    });
  }

  void _markAsNew([bool wasFromZone = false]) {
    if (_words.isEmpty) return;

    // wasFromZone=true 表示从标新区域触发，直接执行标记新词逻辑
    // wasFromZone=false 表示右滑未进区域，跳转到详情页
    if (!wasFromZone) {
      _navigateToDetail();
      return;
    }

    // 执行标记新词逻辑
    setState(() {
      // 将当前单词移到列表末尾
      final word = _words.removeAt(_currentIndex);
      _words.add(word);
      // 确保索引有效
      if (_currentIndex >= _words.length && _currentIndex > 0) {
        _currentIndex = _words.length - 1;
      }
      _showDetails = false;
      _dragProgress = 0.0;
      _verticalProgress = 0.0;
      _currentDirection = DragDirection.none;
      _isInMarkZone = false;
      _isInDeleteZone = false;
      _markZoneOpacity = 0.0;
      _deleteZoneOpacity = 0.0;
      // 显示标新成功提示
      _showMarkNewSuccessHint = true;
    });

    // 2秒后自动隐藏提示
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showMarkNewSuccessHint = false;
        });
      }
    });
  }

  void _markAsReviewed() {
    if (_words.isEmpty) {
      debugPrint('_markAsReviewed: words is empty, returning');
      return;
    }

    debugPrint('_markAsReviewed: BEFORE - words.length=${_words.length}, currentIndex=$_currentIndex, showDetails=$_showDetails');

    setState(() {
      final word = _words.removeAt(_currentIndex);
      _words.add(word);
      debugPrint('_markAsReviewed: AFTER remove/add - words.length=${_words.length}, currentIndex=$_currentIndex');
      // 确保索引有效
      if (_currentIndex >= _words.length && _currentIndex > 0) {
        _currentIndex = _words.length - 1;
        debugPrint('_markAsReviewed: adjusted index to $_currentIndex');
      }
      _showDetails = false;
      _dragProgress = 0.0;
      _verticalProgress = 0.0;
      _currentDirection = DragDirection.none;
      _isInMarkZone = false;
      _isInDeleteZone = false;
      _markZoneOpacity = 0.0;
      _deleteZoneOpacity = 0.0;
      // 显示标记成功提示
      _showMarkSuccessHint = true;
      debugPrint('_markAsReviewed: state updated, showing word at index $_currentIndex');
    });

    // 2秒后自动隐藏提示
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showMarkSuccessHint = false;
        });
      }
    });
  }

  void _resetState() {
    setState(() {
      _showDetails = false;
      _dragProgress = 0.0;
      _verticalProgress = 0.0;
      _currentDirection = DragDirection.none;
      _isInMarkZone = false;
      _isInDeleteZone = false;
      _markZoneOpacity = 0.0;
      _deleteZoneOpacity = 0.0;
    });
  }

  /// 重置区域状态（弹簧动画完成时调用）
  void _resetZoneState() {
    // 无条件调用 setState 确保 UI 重建，防止透明度为 0 但状态未更新导致区域"消失"后无法再触发
    setState(() {
      _isInMarkZone = false;
      _isInDeleteZone = false;
    });
  }

  void _confirmMark() {
    // 立即捕获区域状态（避免 200ms 后状态被重置）
    final wasInMarkZone = _isInMarkZone;
    if (wasInMarkZone) {
      // 显示标新成功提示
      setState(() {
        _showMarkNewSuccessHint = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showMarkNewSuccessHint = false;
          });
        }
      });
      // 延迟执行标记新词
      Future.delayed(const Duration(milliseconds: 200), () {
        _markAsNew(true);
      });
    }
  }

  void _confirmDelete() {
    // 立即捕获区域状态
    final wasInDeleteZone = _isInDeleteZone;
    if (wasInDeleteZone) {
      // 显示成功提示
      setState(() {
        _showDeleteSuccessHint = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showDeleteSuccessHint = false;
          });
        }
      });
      // 延迟执行删除
      Future.delayed(const Duration(milliseconds: 200), () {
        _deleteCurrentWord(wasFromZone: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('WordDragPage: BUILD - words.length=${_words.length}, currentIndex=$_currentIndex, showDetails=$_showDetails');
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

            // 右上角标新区
            if (_words.isNotEmpty)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.15,
                child: Opacity(
                  opacity: _markZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.bookmark_add_outlined,
                    label: '标新',
                    isActive: _isInMarkZone,
                    onTap: _confirmMark,
                  ),
                ),
              ),

            // 右下角删除区
            if (_words.isNotEmpty)
              Positioned(
                right: 16,
                top: MediaQuery.of(context).size.height * 0.60,
                child: Opacity(
                  opacity: _deleteZoneOpacity.clamp(0.0, 1.0),
                  child: _ActionZone(
                    icon: Icons.delete_outline,
                    label: '删除',
                    isActive: _isInDeleteZone,
                    isDelete: true,
                    onTap: _confirmDelete,
                  ),
                ),
              ),

            // 底部提示
            if (_words.isNotEmpty && _markZoneOpacity < 0.1 && _deleteZoneOpacity < 0.1)
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
                        Icon(Icons.swipe, color: Colors.grey.shade400, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '上: 详情 | 左: 稍后 | 右: 操作',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 标新确认提示
            if (_isInMarkZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: _ConfirmHint(label: '松开标记新词', color: Colors.blue),
                ),
              ),

            // 删除确认提示
            if (_isInDeleteZone)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: _ConfirmHint(label: '松开删除', color: Colors.red),
                ),
              ),

            // 左滑标记成功提示
            if (_showMarkSuccessHint)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '已标记稍后复习',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 标新成功提示
            if (_showMarkNewSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark_add, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '已标记为新词',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 删除成功提示
            if (_showDeleteSuccessHint)
              Positioned(
                bottom: 160,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '已删除单词',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              Text(
                '已复习 ${Word.sampleWords.length - _words.length}',
                style: TextStyle(color: Colors.green.shade400, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _words.isEmpty
                ? 1.0
                : (Word.sampleWords.length - _words.length) / Word.sampleWords.length,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation(Colors.green.shade400),
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildCardStack() {
    // 双重检查确保索引有效
    if (_words.isEmpty || _currentIndex >= _words.length) {
      return _buildEmptyState();
    }
    return DraggableWordCard(
      key: ValueKey('${_words[_currentIndex].id}-$_currentIndex'),
      onSwipeUp: _onSwipeUp,
      onSwipeLeft: _onSwipeLeft,
      onSwipeRight: _navigateToDetail, // 非区域右滑 → 详情页
      onMarkZoneAction: _onMarkZone,
      onDeleteZoneAction: _onDeleteZone,
      onHorizontalDragProgress: _onHorizontalDragProgress,
      onCardPositionChanged: (cardCenter, dragOffset, isSpringBack) {
        return _onCardPositionChanged(cardCenter, dragOffset, isSpringBack);
      },
      onRightThresholdFirstCrossed: () {
        // WordDragPage 的区域状态已更新，这里不需要额外操作
      },
      onSpringBackComplete: _resetZoneState,
      child: WordCardContent(
        word: _words[_currentIndex],
        showDetails: _showDetails,
        isDragging: _dragProgress > 0,
      ),
    );
  }

  Widget _buildEmptyState() {
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
      onTap: isActive ? onTap : null,
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
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isActive ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                icon,
                color: isActive ? Colors.white : Colors.grey,
                size: 36,
              ),
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

enum DragDirection { none, up, left, right, down }
